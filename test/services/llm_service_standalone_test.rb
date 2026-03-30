require "minitest/autorun"
require "logger"

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
end
