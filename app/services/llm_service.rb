# frozen_string_literal: true

require "json"
require "httparty"
require "timeout"
require "logger"
require "uri"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/array/wrap"
require "active_support/core_ext/string/filters"

# LlmService sends normalized survey feedback to an Ollama-hosted LLM and
# returns a safe, structured result that never raises to callers.
class LlmService
  DEFAULT_MODEL = "gemma:2b"
  DEFAULT_TIMEOUT_SECONDS = 20
  ERROR_DETAIL_LIMIT = 300
  GENERATE_PATH = "/api/generate"
  CHAT_PATH = "/api/chat"

  def initialize(
    api_url: ENV["LLM_API_URL"],
    model: ENV["LLM_MODEL"].presence || DEFAULT_MODEL,
    timeout_seconds: ENV.fetch("LLM_TIMEOUT_SECONDS", DEFAULT_TIMEOUT_SECONDS).to_i,
    include_scale_summary: false,
    logger: nil
  )
    @api_url = api_url.to_s.strip
    @model = model.to_s.strip
    @timeout_seconds = timeout_seconds
    @include_scale_summary = include_scale_summary
    @logger = logger || default_logger
  end

  # Public entry point for analysis.
  #
  # input can be:
  # - parser output hash containing :dataset and/or :respondents
  # - dataset array [{ team:, responses: [] }]
  # - respondents array [{ responses: [{ type:, answer: }] }]
  # - simple array of strings
  #
  # prompt can be provided directly. If omitted, a small default prompt is used.
  # endpoint supports :generate (default) and :chat.
  def analyze(input:, prompt: nil, endpoint: :generate)
    return config_error("LLM_API_URL is missing") if @api_url.blank?
    return config_error("LLM_MODEL is missing") if @model.blank?

    normalized = normalize_input(input)
    if normalized[:responses].empty?
      return error_result(
        code: "no_feedback",
        message: "No textual feedback found to analyze",
        details: normalized[:stats]
      )
    end

    final_prompt = resolve_prompt(prompt: prompt, normalized: normalized)
    perform_request(final_prompt: final_prompt, endpoint: endpoint, normalized: normalized)
  rescue StandardError => e
    @logger.error("LlmService analyze failed: #{e.class} - #{e.message}")
    error_result(code: "llm_service_error", message: "LLM unavailable", details: e.message)
  end

  # Convenience method when callers already have a plain string array.
  def analyze_responses(responses, prompt: nil, endpoint: :generate)
    analyze(input: responses, prompt: prompt, endpoint: endpoint)
  end

  # Exposes final prompt construction for console usage and prompt tuning work.
  # This keeps prompt iteration separate from HTTP/network behavior.
  def preview_prompt(input:, prompt: nil)
    normalized = normalize_input(input)
    resolve_prompt(prompt: prompt, normalized: normalized)
  end

  private

  def perform_request(final_prompt:, endpoint:, normalized:)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    url = endpoint_url(endpoint)

    body = request_payload(endpoint: endpoint, prompt: final_prompt)
    headers = {
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }

    @logger.info(
      "LlmService request: endpoint=#{endpoint} model=#{@model} " \
      "response_count=#{normalized[:responses].size}"
    )

    response = HTTParty.post(
      url,
      headers: headers,
      body: body.to_json,
      timeout: @timeout_seconds
    )

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    @logger.info("LlmService response: status=#{response.code} duration_ms=#{elapsed_ms}")

    parse_http_response(response: response, endpoint: endpoint, elapsed_ms: elapsed_ms)
  rescue StandardError => e
    handle_transport_error(e)
  end

  # Converts supported input shapes into a clean array of text strings plus stats.
  #
  # Supported shapes include:
  # - parser hash with :dataset and/or :respondents
  # - direct dataset/respondents arrays
  # - plain array of text strings
  #
  # This method intentionally does not parse CSV files. It only consumes already
  # structured Ruby objects from the parser pipeline.
  def normalize_input(input)
    if input.is_a?(Hash)
      dataset = fetch_key(input, :dataset)
      respondents = fetch_key(input, :respondents)

      return normalize_dataset(dataset) if dataset.present?
      return normalize_respondents(respondents) if respondents.present?
    end

    if input.is_a?(Array)
      return normalize_dataset(input) if dataset_array?(input)
      return normalize_respondents(input) if respondents_array?(input)
      return normalize_string_array(input)
    end

    normalize_string_array(Array.wrap(input))
  end

  def dataset_array?(input)
    input.first.is_a?(Hash) && (fetch_key(input.first, :responses).present? || fetch_key(input.first, :team).present?)
  end

  def respondents_array?(input)
    return false unless input.first.is_a?(Hash)

    first_responses = fetch_key(input.first, :responses)
    first_responses.is_a?(Array) && first_responses.first.is_a?(Hash) && fetch_key(first_responses.first, :answer).present?
  end

  def normalize_dataset(dataset)
    responses = []
    grouped = Hash.new { |h, k| h[k] = [] }
    dropped_count = 0

    Array.wrap(dataset).each do |entry|
      team = fetch_key(entry, :team).to_s.strip
      team = "Unknown Team" if team.blank?

      Array.wrap(fetch_key(entry, :responses)).each do |response_text|
        cleaned = response_text.to_s.strip
        if cleaned.blank?
          dropped_count += 1
          next
        end

        grouped[team] << cleaned
        responses << cleaned
      end
    end

    {
      responses: responses,
      grouped_by_team: grouped,
      stats: {
        text_count: responses.size,
        scale_count: 0,
        dropped_count: dropped_count
      }
    }
  end

  def normalize_respondents(respondents)
    text_responses = []
    grouped = Hash.new { |h, k| h[k] = [] }
    text_count = 0
    scale_count = 0
    dropped_count = 0

    Array.wrap(respondents).each do |respondent|
      respondent_team = fetch_key(fetch_key(respondent, :metadata) || {}, :team).to_s.strip
      respondent_team = "Unknown Team" if respondent_team.blank?

      Array.wrap(fetch_key(respondent, :responses)).each do |response|
        question = fetch_key(response, :question).to_s.strip
        answer = fetch_key(response, :answer).to_s.strip
        type = fetch_key(response, :type).to_s.strip.downcase

        if answer.blank?
          dropped_count += 1
          next
        end

        if type == "text"
          text_count += 1
          text_responses << answer
          grouped[respondent_team] << answer
          next
        end

        if type == "scale"
          scale_count += 1
          next unless @include_scale_summary

          # Keep scale summaries compact so they remain prompt-friendly while still
          # preserving context when included by configuration.
          summary_line = question.blank? ? "Scale feedback: #{answer}" : "Scale feedback (#{question}): #{answer}"
          text_responses << summary_line
          grouped[respondent_team] << summary_line
        end
      end
    end

    {
      responses: text_responses,
      grouped_by_team: grouped,
      stats: {
        text_count: text_count,
        scale_count: scale_count,
        dropped_count: dropped_count
      }
    }
  end

  def normalize_string_array(strings)
    cleaned = Array.wrap(strings).map { |value| value.to_s.strip }.reject(&:blank?)

    {
      responses: cleaned,
      grouped_by_team: { "Ungrouped" => cleaned },
      stats: {
        text_count: cleaned.size,
        scale_count: 0,
        dropped_count: Array.wrap(strings).size - cleaned.size
      }
    }
  end

  # Direct prompt strings are sent as-is so prompt writers have full control.
  # If prompt is omitted, the default prompt template is used.
  def resolve_prompt(prompt:, normalized:)
    return prompt if prompt.is_a?(String) && prompt.present?

    build_default_prompt(normalized)
  end

  # Keeps prompt logic simple and easy to modify for future prompt-refinement tasks.
  def build_default_prompt(normalized)
    lines = []
    lines << "Analyze this client survey feedback."
    lines << "Return: (1) sentiment summary, (2) potential conflicts/risks, (3) concise action items."
    lines << "If there is uncertainty, say so briefly."
    lines << ""
    lines << "Feedback entries:"

    normalized[:grouped_by_team].each do |team, team_responses|
      next if team_responses.empty?

      lines << "Team: #{team}"
      team_responses.each { |response| lines << "- #{response}" }
    end

    lines.join("\n")
  end

  def endpoint_url(endpoint)
    base = @api_url.to_s.sub(%r{/$}, "")

    # If caller already provided a fully qualified endpoint path, keep it.
    return base if base.match?(%r{/api/(generate|chat)\z})

    path = endpoint.to_sym == :chat ? CHAT_PATH : GENERATE_PATH
    "#{base}#{path}"
  end

  def request_payload(endpoint:, prompt:)
    if endpoint.to_sym == :chat
      {
        model: @model,
        messages: [ { role: "user", content: prompt } ],
        stream: false
      }
    else
      {
        model: @model,
        prompt: prompt,
        stream: false
      }
    end
  end

  # Parses Ollama HTTP response and safely falls back to raw text when needed.
  def parse_http_response(response:, endpoint:, elapsed_ms:)
    status = response.code.to_i
    body_text = response.body.to_s
    parsed_body = safe_json_parse(body_text)

    unless status.between?(200, 299)
      details = parsed_body.is_a?(Hash) ? parsed_body : body_text.truncate(ERROR_DETAIL_LIMIT)
      return error_result(
        code: "llm_http_error",
        message: "LLM unavailable",
        details: { status: status, body: details }
      )
    end

    # For successful responses we attempt multiple parse paths in order:
    # 1) expected Ollama fields (response/message.content)
    # 2) full parsed JSON body (if no expected field exists)
    # 3) raw HTTP body text fallback
    extracted_output = extract_llm_output(parsed_body, endpoint)
    if extracted_output.nil? && parsed_body.is_a?(Hash)
      return success_result(
        data: parsed_body,
        meta: {
          endpoint: endpoint.to_sym,
          model: @model,
          status: status,
          duration_ms: elapsed_ms,
          parsed_as: "json"
        }
      )
    end

    extracted_output = body_text if extracted_output.nil?
    if extracted_output.blank?
      return error_result(
        code: "invalid_llm_response",
        message: "LLM unavailable",
        details: "Response body was empty"
      )
    end

    # Some models return JSON as a string in `response`; decode when possible.
    structured = safe_json_parse(extracted_output)
    data = structured.nil? ? extracted_output : structured

    success_result(
      data: data,
      meta: {
        endpoint: endpoint.to_sym,
        model: @model,
        status: status,
        duration_ms: elapsed_ms,
        parsed_as: structured.nil? ? "text" : "json"
      }
    )
  end

  def extract_llm_output(parsed_body, endpoint)
    return nil unless parsed_body.is_a?(Hash)

    if endpoint.to_sym == :chat
      message = fetch_key(parsed_body, :message)
      chat_content = fetch_key(message, :content).to_s if message.is_a?(Hash)
      return chat_content if chat_content.present?
    end

    generated_text = fetch_key(parsed_body, :response).to_s
    return generated_text if generated_text.present?

    nil
  end

  def safe_json_parse(value)
    return nil if value.blank?

    JSON.parse(value)
  rescue JSON::ParserError
    nil
  end

  def fetch_key(hash, key)
    return nil unless hash.is_a?(Hash)

    hash[key] || hash[key.to_s]
  end

  def success_result(data:, meta: {})
    {
      ok: true,
      data: data,
      error: nil,
      meta: meta
    }
  end

  def config_error(message)
    error_result(code: "configuration_error", message: message)
  end

  # Maps request-level exceptions to stable, caller-safe error codes.
  def handle_transport_error(error)
    code = transport_error_code(error)
    @logger.error("LlmService transport failure: #{error.class} - #{error.message}")
    error_result(code: code, message: "LLM unavailable", details: safe_error_detail(error.message))
  end

  def transport_error_code(error)
    case error
    when Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, Errno::ETIMEDOUT
      "llm_timeout"
    when Errno::ECONNREFUSED, SocketError, Errno::EHOSTUNREACH, Errno::ECONNRESET
      "llm_unreachable"
    when URI::InvalidURIError
      "invalid_llm_url"
    else
      # HTTParty and SSL errors usually indicate transport-level service issues.
      if defined?(OpenSSL::SSL::SSLError) && error.is_a?(OpenSSL::SSL::SSLError)
        "llm_ssl_error"
      elsif defined?(HTTParty::Error) && error.is_a?(HTTParty::Error)
        "llm_transport_error"
      else
        "llm_service_error"
      end
    end
  end

  def safe_error_detail(message)
    message.to_s.truncate(ERROR_DETAIL_LIMIT)
  end

  def error_result(code:, message:, details: nil)
    {
      ok: false,
      data: nil,
      error: {
        code: code,
        message: message,
        details: details
      },
      meta: {
        endpoint: @api_url,
        model: @model
      }
    }
  end

  def default_logger
    if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
      Rails.logger
    else
      Logger.new($stdout)
    end
  end
end
