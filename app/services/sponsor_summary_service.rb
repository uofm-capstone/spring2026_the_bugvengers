# frozen_string_literal: true

require "logger"
require "active_support/core_ext/object/blank"

# SponsorSummaryService coordinates the upload-time summary pipeline for sponsor CSVs.
#
# Why this service exists:
# - Keeps controller actions focused on HTTP flow rather than parsing/LLM orchestration.
# - Guarantees the expensive LLM call only happens during upload-triggered execution.
# - Provides a single place to document fallback behavior for future team maintenance.
class SponsorSummaryService
  # The prompt is centralized here so future teams can tune summary behavior
  # without changing controller logic or UI code paths.
  DEFAULT_PROMPT = "Use only the provided survey data and return exactly 3 sentences only: " \
                   "sentence 1 must state overall sentiment by including stating Positive, Mixed, or Negative; " \
                   "sentence 2 must summarize notable positives prioritizing repeated patterns " \
                   "(e.g., if scale responses are mostly/all 'Exceeded expectations', say that explicitly); " \
                   "sentence 3 must summarize notable negatives " \
                   "(e.g, if there are responses saying that something needs to improved, say that explicitly), " \
                   "or say 'None explicitly reported.' if there are none. " \
                   "Do not make up anything that is not in the parsed CSV data."

  # We intentionally keep this fallback in the same bullet format used by
  # LlmService#format_three_sentence_summary so the UI can render one shape.
  FALLBACK_SUMMARY_TEXT = [
    "Overall sentiment: N/A",
    "- Positives: Summary unavailable because the LLM could not complete analysis.",
    "- Negatives: None explicitly reported."
  ].join("\n")

  def initialize(
    semester:,
    sprint_number:,
    parser_class: CSVSurveyParserService,
    llm_service_builder: nil,
    logger: nil
  )
    # Semester is injected so this service can be reused in upload actions,
    # console scripts, and future background jobs.
    @semester = semester
    # Sprint is normalized once to avoid repeated type coercion and subtle
    # branching bugs when controller params arrive as strings.
    @sprint_number = sprint_number.to_s.strip
    # Parser and LLM builder are injectable to keep tests fast and isolated.
    @parser_class = parser_class
    @llm_service_builder = llm_service_builder
    @logger = logger || default_logger
  end

  # Performs parse + LLM analysis and returns a stable hash contract.
  #
  # Return shape:
  # - ok: true/false
  # - summary_text: final bullet text shown in Summary modal
  # - rows_count: parsed row count for modal metadata
  # - message: short operator-facing message for upload response feedback
  # - error_code: machine-friendly classification for logging/metrics
  def generate
    # Step 1: Select the correct ActiveStorage attachment for the sprint.
    # Invalid sprint values should fail gracefully and never raise into controller.
    attachment_name = sponsor_attachment_name_for_sprint
    unless attachment_name
      return failure_result(
        error_code: "invalid_sprint",
        message: "Invalid sprint number for sponsor summary generation.",
        rows_count: 0
      )
    end

    # Step 2: Ensure upload exists before parsing. This protects from stale UI
    # state where a summary request can race with attachment changes.
    attachment = @semester.public_send(attachment_name)
    unless attachment&.attached?
      return failure_result(
        error_code: "missing_attachment",
        message: "No sponsor CSV is attached for this sprint.",
        rows_count: 0
      )
    end

    # Step 3: Parse through the shared CSV parser so summary logic follows the
    # same column/normalization rules already used by the Questions modal.
    parsed = parse_attachment(attachment)
    rows_count = parsed[:rows].to_a.size

    # If parser reports errors, we do not call LLM. This prevents generating
    # misleading sentiment from malformed or partially understood data.
    if parsed[:errors].present?
      return failure_result(
        error_code: "parse_error",
        message: "Sponsor CSV parsing failed; summary was not generated.",
        rows_count: rows_count
      )
    end

    # Respondents are the canonical LLM input shape in this app.
    # Blank respondents means there is nothing meaningful to summarize.
    if parsed[:respondents].blank?
      return failure_result(
        error_code: "no_responses",
        message: "Sponsor CSV parsed successfully but had no usable responses for summary generation.",
        rows_count: rows_count
      )
    end

    # include_scale_summary is enabled so repeated Likert patterns can appear
    # in sentence 2 as requested by the status-page rubric expectations.
    llm_service = build_llm_service
    llm_result = llm_service.analyze(
      input: { respondents: parsed[:respondents] },
      prompt: DEFAULT_PROMPT
    )

    # Upload should still succeed when LLM fails; controller can show warning
    # while preserving stored CSV data for teams and instructors.
    unless llm_result[:ok]
      llm_error_code = llm_result.dig(:error, :code).to_s.strip
      llm_error_message = llm_result.dig(:error, :message).to_s.strip
      diagnostic_suffix = [llm_error_code.presence, llm_error_message.presence].compact.join(" - ")
      diagnostic_suffix = "unknown_llm_error" if diagnostic_suffix.blank?

      # Include diagnostic details so upload warning text can immediately point
      # maintainers toward config vs network vs model-tag issues.
      return failure_result(
        error_code: "llm_error",
        message: "CSV upload succeeded, but summary generation could not be completed (#{diagnostic_suffix}).",
        rows_count: rows_count
      )
    end

    formatted = llm_service.format_three_sentence_summary(llm_result[:data].to_s)
    summary_text = formatted[:bullet_text].to_s.strip

    # Empty output is treated as a failure state so UI remains explicit and
    # predictable rather than displaying blank or misleading summary text.
    if summary_text.blank?
      return failure_result(
        error_code: "empty_summary",
        message: "LLM returned an empty summary output.",
        rows_count: rows_count
      )
    end

    {
      ok: true,
      summary_text: summary_text,
      rows_count: rows_count,
      message: "Sponsor summary generated successfully.",
      error_code: nil
    }
  rescue StandardError => e
    # Last-resort guardrail: never let upload flow crash due to parser/LLM
    # integration exceptions. Fail closed with deterministic fallback text.
    @logger.error("SponsorSummaryService failed for semester=#{safe_semester_id}: #{e.class} - #{e.message}")

    failure_result(
      error_code: "service_exception",
      message: "CSV upload succeeded, but summary generation encountered an unexpected error.",
      rows_count: 0
    )
  end

  private

  # Explicit sprint mapping keeps behavior obvious and schema-coupled on purpose.
  # Future schema changes should update this single method.
  def sponsor_attachment_name_for_sprint
    case @sprint_number
    when "2"
      :sponsor_csv_sprint_2
    when "3"
      :sponsor_csv_sprint_3
    when "4"
      :sponsor_csv_sprint_4
    end
  end

  # Parser is executed against the opened attachment IO so large files do not
  # need to be copied around in memory.
  def parse_attachment(attachment)
    attachment.open do |file|
      @parser_class.new(file: file).parse
    end
  end

  # Dependency injection entry point used by tests to avoid network calls.
  # Production path uses the app's default Ollama-backed LlmService.
  def build_llm_service
    return @llm_service_builder.call if @llm_service_builder.respond_to?(:call)

    LlmService.new(include_scale_summary: true)
  end

  # All failures intentionally return the same summary shape consumed by UI.
  # This keeps rendering code simple and avoids branch-heavy view conditionals.
  def failure_result(error_code:, message:, rows_count:)
    {
      ok: false,
      summary_text: FALLBACK_SUMMARY_TEXT,
      rows_count: rows_count,
      message: message,
      error_code: error_code
    }
  end

  # Safe logging helper: avoids nil errors when semester doubles are used in tests.
  def safe_semester_id
    @semester.respond_to?(:id) ? @semester.id : "unknown"
  end

  # Service remains runnable in standalone contexts where Rails logger is absent.
  def default_logger
    return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

    Logger.new($stdout)
  end
end
