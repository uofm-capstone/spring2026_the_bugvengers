require "minitest/autorun"
require "logger"
require "json"

require_relative "../../app/services/llm_service"

# DB-independent LLM service checks for environments where Rails test DB auth is unavailable.
class LlmServiceStandaloneTest < Minitest::Test
  FakeHttpResponse = Struct.new(:code, :body)

  def build_service(**overrides)
    defaults = {
      api_url: "http://34.10.73.251:11434",
      logger: Logger.new(nil)
    }

    LlmService.new(**defaults.merge(overrides))
  end

  def test_returns_configuration_error_when_api_url_missing
    service = build_service(api_url: nil)

    result = service.analyze(input: ["Client feedback"])

    assert_equal false, result[:ok]
    assert_equal "configuration_error", result.dig(:error, :code)
  end

  def test_analyzes_dataset_input_with_generate_endpoint
    service = build_service
    dataset_input = {
      dataset: [
        {
          team: "Team A",
          responses: ["Client was happy with progress", "Some delays in communication"]
        }
      ]
    }

    body = { response: "{\"summary\":\"mixed\"}" }.to_json
    fake_response = FakeHttpResponse.new(200, body)

    HTTParty.stub(:post, fake_response) do
      result = service.analyze(input: dataset_input)

      assert_equal true, result[:ok]
      assert_equal "mixed", result.dig(:data, "summary")
      assert_equal "json", result.dig(:meta, :parsed_as)
    end
  end

  def test_extracts_text_from_respondents_and_ignores_scale_by_default
    service = build_service
    respondents_input = {
      respondents: [
        {
          responses: [
            { question: "Q2", answer: "Met expectations", type: :scale },
            { question: "Q7", answer: "Great progress", type: :text }
          ],
          metadata: { team: "Bugvengers" }
        }
      ]
    }

    body = { response: "Text analysis result" }.to_json
    fake_response = FakeHttpResponse.new(200, body)

    HTTParty.stub(:post, fake_response) do
      result = service.analyze(input: respondents_input)

      assert_equal true, result[:ok]
      assert_equal "Text analysis result", result[:data]
      assert_equal "text", result.dig(:meta, :parsed_as)
    end
  end

  def test_includes_scale_summaries_when_enabled
    service = build_service(include_scale_summary: true)
    respondents_input = {
      respondents: [
        {
          responses: [
            { question: "Q2", answer: "Did not meet expectations", type: :scale }
          ],
          metadata: { team: "Bugvengers" }
        }
      ]
    }

    body = { response: "scale summary received" }.to_json
    fake_response = FakeHttpResponse.new(200, body)

    HTTParty.stub(:post, fake_response) do
      result = service.analyze(input: respondents_input)

      assert_equal true, result[:ok]
      assert_equal "scale summary received", result[:data]
    end
  end

  def test_returns_unreachable_error_when_connection_fails
    service = build_service

    failing_post = lambda do |_url, _options|
      raise Errno::ECONNREFUSED, "Connection refused"
    end

    HTTParty.stub(:post, failing_post) do
      result = service.analyze(input: ["Client feedback"])

      assert_equal false, result[:ok]
      assert_equal "llm_unreachable", result.dig(:error, :code)
      assert_equal "LLM unavailable", result.dig(:error, :message)
    end
  end

  def test_returns_invalid_response_error_for_non_json_http_body
    service = build_service
    fake_response = FakeHttpResponse.new(200, "not-json-response")

    HTTParty.stub(:post, fake_response) do
      result = service.analyze(input: ["Client feedback"])

      assert_equal false, result[:ok]
      assert_equal "invalid_llm_response", result.dig(:error, :code)
    end
  end

  def test_normalizes_string_key_dataset_input
    service = build_service
    dataset_input = {
      "dataset" => [
        {
          "team" => "Team String Keys",
          "responses" => ["  Solid progress  ", ""]
        }
      ]
    }

    body = { response: "ok" }.to_json
    fake_response = FakeHttpResponse.new(200, body)

    HTTParty.stub(:post, fake_response) do
      result = service.analyze(input: dataset_input)

      assert_equal true, result[:ok]
      assert_equal "ok", result[:data]
    end
  end

  def test_uses_respondents_when_dataset_empty
    service = build_service
    input = {
      dataset: [],
      respondents: [
        {
          responses: [
            { question: "Q7", answer: "Clear communication overall", type: :text }
          ],
          metadata: { team: "Fallback Team" }
        }
      ]
    }

    body = { response: "respondent path used" }.to_json
    fake_response = FakeHttpResponse.new(200, body)

    HTTParty.stub(:post, fake_response) do
      result = service.analyze(input: input)

      assert_equal true, result[:ok]
      assert_equal "respondent path used", result[:data]
    end
  end

  def test_returns_no_feedback_when_only_blank_text_inputs
    service = build_service

    result = service.analyze(input: ["", "   "])

    assert_equal false, result[:ok]
    assert_equal "no_feedback", result.dig(:error, :code)
  end

  def test_uses_direct_prompt_without_modifying_text
    service = build_service
    provided_prompt = "  Keep this spacing and wording exactly.  "
    captured_prompt = nil

    post_stub = lambda do |_url, options|
      payload = JSON.parse(options[:body])
      captured_prompt = payload["prompt"]
      FakeHttpResponse.new(200, { response: "ok" }.to_json)
    end

    HTTParty.stub(:post, post_stub) do
      result = service.analyze(input: ["Client feedback"], prompt: provided_prompt)

      assert_equal true, result[:ok]
      assert_equal provided_prompt, captured_prompt
    end
  end

  def test_builds_default_prompt_grouped_by_team
    service = build_service
    prompt = service.preview_prompt(
      input: {
        dataset: [
          {
            team: "Team A",
            responses: ["Strong communication", "Need clearer estimates"]
          }
        ]
      }
    )

    assert_includes prompt, "Analyze this client survey feedback."
    assert_includes prompt, "Team: Team A"
    assert_includes prompt, "- Strong communication"
    assert_includes prompt, "- Need clearer estimates"
  end
end
