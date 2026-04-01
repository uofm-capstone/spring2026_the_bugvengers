require "minitest/autorun"
require "logger"
require "active_support/core_ext/object/blank"

require_relative "../../app/services/csv_survey_parser_service"

# DB-independent parser checks for environments where Rails test DB auth is unavailable.
class CSVSurveyParserServiceStandaloneTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def service_from_csv(csv_string)
    CSVSurveyParserService.new(csv_string: csv_string, logger: Logger.new(nil))
  end

  def test_parses_client_feedback_csv
    csv_path = File.join(ROOT, "client_feedback.csv")
    csv_string = File.read(csv_path)

    result = service_from_csv(csv_string).parse

    assert_empty result[:errors]
    refute_empty result[:dataset]
    refute_empty result[:respondents]

    first_team = result[:dataset].first
    assert_equal "The Bugvengers (Tool-assisted Grading)", first_team[:team]
    assert_includes first_team[:responses], "nope :)"
  end

  # Parser should fail gracefully on malformed source data.
  def test_handles_malformed_csv_without_crashing
    malformed_csv = "Q1,Q3,Q7\n\"broken,Sprint 2,Feedback"

    result = service_from_csv(malformed_csv).parse

    assert_empty result[:dataset]
    refute_empty result[:errors]
  end

  # Missing Q7 should return a structured error because Q7 is required feedback.
  def test_reports_missing_q7_column
    csv_string = <<~CSV
      Q1,Q3,Q6
      Team,Sprint,Question
      ImportId-QID1,ImportId-QID3,ImportId-QID6_TEXT
      Team A,Sprint 1,Some text
    CSV

    result = service_from_csv(csv_string).parse

    assert_empty result[:dataset]
    assert_includes result[:errors].join(" "), "Q7"
  end

  # Missing team still yields valid output using the Unknown Team fallback.
  def test_uses_unknown_team_fallback
    csv_string = <<~CSV
      Q1,Q3,Q7
      Team,Sprint,Feedback
      ImportId-QID1,ImportId-QID3,ImportId-QID7_TEXT
      ,Sprint 1,Need faster updates
    CSV

    result = service_from_csv(csv_string).parse

    assert_equal 1, result[:dataset].length
    assert_equal "Unknown Team", result[:dataset][0][:team]
    assert_equal ["Need faster updates"], result[:dataset][0][:responses]
  end
end
