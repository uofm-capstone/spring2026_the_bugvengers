require "minitest/autorun"
require "logger"

require_relative "../../app/services/google_sheets_timesheet_parser_service"

# Standalone parser tests focus on data-shaping behavior without DB setup.
class GoogleSheetsTimesheetParserServiceStandaloneTest < Minitest::Test
  def build_service(tabs:, tab_names: nil)
    GoogleSheetsTimesheetParserService.new(
      tabs: tabs,
      tab_names: tab_names,
      logger: Logger.new(nil)
    )
  end

  def test_parses_member_entries_from_sprint_tab
    tabs = [
      {
        tab_name: "Sprint 1",
        values: [
          ["Team Member", "Row Type", "4/1/2026", "4/2/2026", "Weekly Total"],
          ["Alice", "Hours Spent", "1.5", "2.0", "3.5"],
          ["", "Activity", "class time", "coding", ""],
          ["Bob", "Hours Spent", "0", "1", "1"],
          ["", "Activity", "", "bug fix", ""]
        ]
      }
    ]

    result = build_service(tabs: tabs).call

    assert_equal true, result[:ok]
    assert_equal 2, result[:records].size

    alice = result[:records].find { |record| record[:team_member] == "Alice" }
    assert_equal "Sprint 1", alice[:sprint_tab]
    assert_equal 3.5, alice[:weekly_total]
    assert_equal "2026-04-01", alice[:entries][0][:date]
    assert_equal 1.5, alice[:entries][0][:hours]
    assert_equal "class time", alice[:entries][0][:activity]
  end

  def test_auto_selects_likely_sprint_tabs_by_default
    tabs = [
      {
        tab_name: "Sprint 3 PC 1",
        values: [
          ["Name", "Type", "4/9/2026", "4/10/2026"],
          ["Jonathan", "Hours Spent", "1", "2"],
          ["", "Activity", "planning", "implementation"]
        ]
      },
      {
        tab_name: "Instructions",
        values: [
          ["This sheet is display-only"]
        ]
      }
    ]

    result = build_service(tabs: tabs).call

    assert_equal true, result[:ok]
    assert_equal ["Sprint 3 PC 1"], result[:tabs_processed]
    assert_equal 1, result[:records].size
  end

  def test_honors_explicit_tab_filter_and_warns_on_missing_tab
    tabs = [
      {
        tab_name: "Sprint 2",
        values: [
          ["Name", "Type", "4/9/2026", "4/10/2026"],
          ["Jonathan", "Hours Spent", "1", "2"],
          ["", "Activity", "planning", "implementation"]
        ]
      }
    ]

    result = build_service(tabs: tabs, tab_names: ["Sprint 2", "Sprint 99"]).call

    assert_equal true, result[:ok]
    assert_equal ["Sprint 2"], result[:tabs_processed]
    assert_includes result[:warnings], "Requested tab not found for parser: Sprint 99"
  end

  def test_adds_warning_for_non_numeric_hours_and_keeps_activity_entry
    tabs = [
      {
        tab_name: "Sprint 4",
        values: [
          ["Name", "Type", "4/11/2026"],
          ["Taylor", "Hours Spent", "N/A"],
          ["", "Activity", "research"]
        ]
      }
    ]

    result = build_service(tabs: tabs).call

    assert_equal true, result[:ok]
    assert_equal 1, result[:records].size
    assert_nil result[:records][0][:entries][0][:hours]
    assert_equal "research", result[:records][0][:entries][0][:activity]
    assert result[:warnings].any? { |warning| warning.include?("invalid hours 'N/A'") }
  end
end
