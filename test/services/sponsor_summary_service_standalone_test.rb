require "minitest/autorun"
require "stringio"
require "logger"

require_relative "../../app/services/sponsor_summary_service"

# DB-independent tests for SponsorSummaryService orchestration behavior.
#
# These tests intentionally avoid Rails models so they can run in restricted
# environments where DB credentials or bundler rails executables are unavailable.
class SponsorSummaryServiceStandaloneTest < Minitest::Test
  class FakeAttachment
    def initialize(csv_text:, attached: true)
      @csv_text = csv_text
      @attached = attached
    end

    def attached?
      @attached
    end

    def open
      io = StringIO.new(@csv_text)
      yield io
    end
  end

  class FakeSemester
    attr_reader :sponsor_csv_sprint_2, :sponsor_csv_sprint_3, :sponsor_csv_sprint_4

    def initialize(attachment)
      @sponsor_csv_sprint_2 = attachment
      @sponsor_csv_sprint_3 = attachment
      @sponsor_csv_sprint_4 = attachment
    end
  end

  class FakeLlmService
    def initialize(ok:, response_text:)
      @ok = ok
      @response_text = response_text
    end

    def analyze(input:, prompt:)
      # Validate that caller provides respondents and prompt, mirroring real usage.
      raise "missing respondents" if input[:respondents].nil?
      raise "missing prompt" if prompt.to_s.strip.empty?

      if @ok
        { ok: true, data: @response_text }
      else
        { ok: false, error: { code: "llm_unreachable" } }
      end
    end

    def format_three_sentence_summary(text)
      {
        bullet_text: "Overall sentiment: Positive\n- Positives: #{text}\n- Negatives: None explicitly reported."
      }
    end
  end

  def test_generate_success_returns_formatted_summary
    parser_class = Class.new do
      def initialize(file:)
        @file = file
      end

      def parse
        {
          rows: [{ q7: "Great communication" }],
          respondents: [{ responses: [{ question: "Q7", answer: "Great communication", type: :text }] }],
          errors: []
        }
      end
    end

    semester = FakeSemester.new(FakeAttachment.new(csv_text: "Q7\nGreat communication"))
    llm_builder = -> { FakeLlmService.new(ok: true, response_text: "Client repeatedly praised communication") }

    result = SponsorSummaryService.new(
      semester: semester,
      sprint_number: 2,
      parser_class: parser_class,
      llm_service_builder: llm_builder,
      logger: Logger.new(nil)
    ).generate

    assert_equal true, result[:ok]
    assert_equal 1, result[:rows_count]
    assert_includes result[:summary_text], "Overall sentiment: Positive"
  end

  def test_generate_returns_fallback_when_parser_errors
    parser_class = Class.new do
      def initialize(file:)
        @file = file
      end

      def parse
        {
          rows: [],
          respondents: [],
          errors: ["Missing Q7"]
        }
      end
    end

    semester = FakeSemester.new(FakeAttachment.new(csv_text: "bad csv"))
    llm_builder = -> { FakeLlmService.new(ok: true, response_text: "unused") }

    result = SponsorSummaryService.new(
      semester: semester,
      sprint_number: 2,
      parser_class: parser_class,
      llm_service_builder: llm_builder,
      logger: Logger.new(nil)
    ).generate

    assert_equal false, result[:ok]
    assert_equal "parse_error", result[:error_code]
    assert_includes result[:summary_text], "Overall sentiment: Mixed"
  end

  def test_generate_returns_fallback_when_llm_fails
    parser_class = Class.new do
      def initialize(file:)
        @file = file
      end

      def parse
        {
          rows: [{ q7: "Need faster updates" }],
          respondents: [{ responses: [{ question: "Q7", answer: "Need faster updates", type: :text }] }],
          errors: []
        }
      end
    end

    semester = FakeSemester.new(FakeAttachment.new(csv_text: "Q7\nNeed faster updates"))
    llm_builder = -> { FakeLlmService.new(ok: false, response_text: "") }

    result = SponsorSummaryService.new(
      semester: semester,
      sprint_number: 2,
      parser_class: parser_class,
      llm_service_builder: llm_builder,
      logger: Logger.new(nil)
    ).generate

    assert_equal false, result[:ok]
    assert_equal "llm_error", result[:error_code]
    assert_includes result[:summary_text], "Summary unavailable"
  end
end
