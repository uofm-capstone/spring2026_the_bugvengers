require "minitest/autorun"
require "logger"

require_relative "../../app/services/google_sheets_timesheet_fetcher_service"

# DB-independent tests for the Google Sheets fetch layer.
#
# These tests intentionally avoid real network/API calls by injecting a fake
# Sheets client object. This keeps behavior verification fast and deterministic.
class GoogleSheetsTimesheetFetcherServiceStandaloneTest < Minitest::Test
  FakeProperties = Struct.new(:title)
  FakeSheet = Struct.new(:properties)
  FakeMetadata = Struct.new(:sheets)
  FakeValuesResponse = Struct.new(:values)

  # Subclass disables runtime gem-loading checks so we can test core behavior
  # even on machines that have not run bundle install yet.
  class TestFetcher < GoogleSheetsTimesheetFetcherService
    private

    def load_google_dependencies
      @dependency_error = nil
    end
  end

  class FakeSheetsService
    attr_reader :requests

    def initialize(tab_values:)
      @tab_values = tab_values
      @requests = []
    end

    def get_spreadsheet(_spreadsheet_id, fields:)
      @requests << { action: :metadata, fields: fields }
      sheets = @tab_values.keys.map do |tab_name|
        FakeSheet.new(FakeProperties.new(tab_name))
      end
      FakeMetadata.new(sheets)
    end

    def get_spreadsheet_values(_spreadsheet_id, range)
      @requests << { action: :values, range: range }
      # A1 range format is expected as: 'Tab Name'!A:ZZ
      tab_name = range.split("!").first.to_s.gsub("'", "")
      FakeValuesResponse.new(@tab_values.fetch(tab_name, []))
    end
  end

  def build_service(**overrides)
    defaults = {
      spreadsheet_id: "spreadsheet-123",
      logger: Logger.new(nil),
      credentials_json: "{\"type\":\"service_account\"}",
      sheets_service: FakeSheetsService.new(
        tab_values: {
          "Sprint 1" => [["Name", "4/1/2026"], ["Alice", "1.5"]],
          "PC 1" => [["Name", "4/2/2026"], ["Bob", "2.0"]]
        }
      )
    }

    TestFetcher.new(**defaults.merge(overrides))
  end

  def test_returns_error_when_spreadsheet_id_missing
    service = build_service(spreadsheet_id: "")

    result = service.call

    assert_equal false, result[:ok]
    assert_includes result[:errors], "Missing spreadsheet_id"
  end

  def test_fetches_all_tabs_when_allowlist_not_provided
    service = build_service

    result = service.call

    assert_equal true, result[:ok]
    assert_equal 2, result[:tabs].size
    assert_equal ["Sprint 1", "PC 1"], result[:tabs].map { |tab| tab[:tab_name] }
  end

  def test_filters_tabs_and_warns_on_missing_requested_tab
    service = build_service(tab_names: ["Sprint 1", "Sprint 99"])

    result = service.call

    assert_equal true, result[:ok]
    assert_equal ["Sprint 1"], result[:tabs].map { |tab| tab[:tab_name] }
    assert_includes result[:warnings], "Requested tab not found: Sprint 99"
  end

  def test_returns_credentials_error_when_missing_credential_inputs
    service = TestFetcher.new(
      spreadsheet_id: "spreadsheet-123",
      logger: Logger.new(nil),
      credentials_json: "",
      credentials_path: "",
      sheets_service: FakeSheetsService.new(tab_values: { "Sprint 1" => [] })
    )

    result = service.call

    assert_equal false, result[:ok]
    assert_equal 1, result[:errors].size
    assert_match(/Missing Google service account credentials/, result[:errors].first)
  end
end
