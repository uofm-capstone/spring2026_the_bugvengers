require "test_helper"

class CsvSurveyParserServiceTest < ActiveSupport::TestCase
  test "parses client_feedback csv into grouped dataset" do
    file_path = Rails.root.join("client_feedback.csv")

    result = CsvSurveyParserService.new(file: file_path.to_s).parse

    assert result[:errors].empty?
    refute_empty result[:dataset]

    team_entry = result[:dataset].find { |row| row[:team].include?("Bugvengers") }
    refute_nil team_entry
    assert_includes team_entry[:responses], "nope :)"
  end

  test "returns empty dataset for malformed csv" do
    malformed_csv = "Q1,Q3,Q7\n\"broken,Sprint 2,Feedback"

    result = CsvSurveyParserService.new(csv_string: malformed_csv).parse

    assert_empty result[:dataset]
    refute_empty result[:errors]
  end

  test "returns empty dataset when q7 is missing" do
    csv_string = <<~CSV
      Q1,Q3,Q6
      Team,Sprint,Question
      {"ImportId":"QID1"},{"ImportId":"QID3"},{"ImportId":"QID6_TEXT"}
      Team A,Sprint 1,Some text
    CSV

    result = CsvSurveyParserService.new(csv_string: csv_string).parse

    assert_empty result[:dataset]
    assert_includes result[:errors].join(" "), "Q7"
  end

  test "falls back to Unknown Team when team is missing" do
    csv_string = <<~CSV
      Q1,Q3,Q7
      Team,Sprint,Feedback
      {"ImportId":"QID1"},{"ImportId":"QID3"},{"ImportId":"QID7_TEXT"}
      ,Sprint 1,Need faster updates
    CSV

    result = CsvSurveyParserService.new(csv_string: csv_string).parse

    assert_equal 1, result[:dataset].length
    assert_equal "Unknown Team", result[:dataset][0][:team]
    assert_equal ["Need faster updates"], result[:dataset][0][:responses]
  end

  test "skips rows with blank q7 feedback" do
    csv_string = <<~CSV
      Q1,Q3,Q7
      Team,Sprint,Feedback
      {"ImportId":"QID1"},{"ImportId":"QID3"},{"ImportId":"QID7_TEXT"}
      Team A,Sprint 2,
      Team A,Sprint 2,Great progress
    CSV

    result = CsvSurveyParserService.new(csv_string: csv_string).parse

    assert_equal 1, result[:dataset].length
    assert_equal ["Great progress"], result[:dataset][0][:responses]
  end
end
