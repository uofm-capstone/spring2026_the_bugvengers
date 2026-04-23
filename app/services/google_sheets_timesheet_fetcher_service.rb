# frozen_string_literal: true

require "json"
require "logger"
require "stringio"

# GoogleSheetsTimesheetFetcherService fetches raw worksheet data from a Google
# Spreadsheet. It intentionally does not parse timesheet semantics; parsing is
# handled by a dedicated parser service in a later phase.
#
# Design goals:
# - Keep authentication and network access isolated from parsing logic.
# - Return stable Hash contracts for callers (ok/data/warnings/errors).
# - Avoid raising exceptions into controllers so upload/import flows stay stable.
# - Allow dependency injection in tests to avoid real network calls.
class GoogleSheetsTimesheetFetcherService
  SHEETS_SCOPE = "https://www.googleapis.com/auth/spreadsheets.readonly"

  def initialize(
    spreadsheet_id:,
    tab_names: nil,
    value_range: nil,
    logger: nil,
    sheets_service: nil,
    timeout_seconds: nil,
    credentials_json: nil,
    credentials_path: nil
  )
    @spreadsheet_id = spreadsheet_id.to_s.strip
    @tab_names = Array(tab_names).map { |name| name.to_s.strip }.reject(&:empty?)
    @value_range = value_range.to_s.strip
    @logger = logger || default_logger
    @sheets_service = sheets_service

    # Allow explicit overrides for tests while keeping ENV-based defaults.
    @timeout_seconds = (timeout_seconds || ENV.fetch("GOOGLE_SHEETS_TIMEOUT_SECONDS", "15")).to_i
    @credentials_json = first_non_blank(credentials_json, ENV["GOOGLE_SHEETS_SERVICE_ACCOUNT_JSON"])
    @credentials_path = first_non_blank(credentials_path, ENV["GOOGLE_SHEETS_SERVICE_ACCOUNT_JSON_PATH"])

    @dependency_error = nil
    load_google_dependencies
  end

  # Main API used by orchestration code.
  #
  # Return shape (success):
  # {
  #   ok: true,
  #   spreadsheet_id: "...",
  #   tabs: [
  #     { tab_name: "Sprint 1", range: "'Sprint 1'!A:ZZ", values: [[...], ...] }
  #   ],
  #   warnings: [],
  #   errors: []
  # }
  #
  # Return shape (failure):
  # {
  #   ok: false,
  #   spreadsheet_id: "...",
  #   tabs: [],
  #   warnings: [...],
  #   errors: ["..."]
  # }
  def call
    warnings = []
    errors = []

    if @spreadsheet_id.empty?
      errors << "Missing spreadsheet_id"
      return failure_result(warnings: warnings, errors: errors)
    end

    if @dependency_error
      errors << @dependency_error
      return failure_result(warnings: warnings, errors: errors)
    end

    unless credentials_present?
      errors << "Missing Google service account credentials. Set GOOGLE_SHEETS_SERVICE_ACCOUNT_JSON or GOOGLE_SHEETS_SERVICE_ACCOUNT_JSON_PATH."
      return failure_result(warnings: warnings, errors: errors)
    end

    service = build_sheets_service
    unless service
      errors << "Unable to initialize Google Sheets client"
      return failure_result(warnings: warnings, errors: errors)
    end

    metadata = fetch_spreadsheet_metadata(service, errors)
    return failure_result(warnings: warnings, errors: errors) if metadata.nil?

    available_titles = extract_tab_titles(metadata)
    selected_tabs = select_tab_titles(available_titles, warnings)

    if selected_tabs.empty?
      warnings << "No matching tabs were selected for fetch"
      return success_result(tabs: [], warnings: warnings, errors: errors)
    end

    fetched_tabs = selected_tabs.map do |tab_title|
      fetch_tab_values(service, tab_title, warnings)
    end.compact

    success_result(tabs: fetched_tabs, warnings: warnings, errors: errors)
  rescue StandardError => e
    @logger.error("GoogleSheetsTimesheetFetcherService failed: #{e.class} - #{e.message}")
    failure_result(warnings: warnings, errors: errors + [e.message])
  end

  private

  # Keeps gem loading local to this service so the app can still boot in
  # environments where gems are not installed yet (e.g., onboarding machines).
  def load_google_dependencies
    require "google/apis/sheets_v4"
    require "googleauth"
  rescue LoadError
    @dependency_error = "Google Sheets gems are not installed. Run bundle install to add google-apis-sheets_v4 and googleauth."
  end

  def credentials_present?
    @credentials_json.to_s.strip != "" || @credentials_path.to_s.strip != ""
  end

  # Builds an authorized Sheets API client. The optional injected
  # @sheets_service is used by tests to avoid real API calls.
  def build_sheets_service
    return @sheets_service if @sheets_service

    service = Google::Apis::SheetsV4::SheetsService.new
    service.client_options.open_timeout_sec = @timeout_seconds
    service.client_options.read_timeout_sec = @timeout_seconds
    service.authorization = build_authorization
    service
  rescue StandardError => e
    @logger.error("GoogleSheetsTimesheetFetcherService client setup error: #{e.class} - #{e.message}")
    nil
  end

  # Supports both JSON-string and JSON-file auth flows.
  # This keeps local dev and cloud deployment setup flexible.
  def build_authorization
    if @credentials_json.to_s.strip != ""
      io = StringIO.new(@credentials_json)
      return Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: io, scope: SHEETS_SCOPE)
    end

    file_json = File.read(@credentials_path)
    file_io = StringIO.new(file_json)
    Google::Auth::ServiceAccountCredentials.make_creds(json_key_io: file_io, scope: SHEETS_SCOPE)
  end

  # Simple helper so this service remains usable outside full Rails boot where
  # ActiveSupport's `presence` helper may not be loaded.
  def first_non_blank(*values)
    values.find { |value| value.to_s.strip != "" }
  end

  # Requests lightweight spreadsheet metadata to discover available tab names.
  def fetch_spreadsheet_metadata(service, errors)
    service.get_spreadsheet(@spreadsheet_id, fields: "sheets(properties(title))")
  rescue Google::Apis::AuthorizationError => e
    errors << "Google authorization failed: #{e.message}"
    nil
  rescue Google::Apis::ClientError => e
    errors << "Google Sheets client error: #{e.message}"
    nil
  rescue Google::Apis::ServerError => e
    errors << "Google Sheets server error: #{e.message}"
    nil
  rescue StandardError => e
    errors << "Metadata fetch failed: #{e.message}"
    nil
  end

  # Extracts sheet titles safely even when metadata is partially missing.
  def extract_tab_titles(metadata)
    Array(metadata&.sheets).map { |sheet| sheet&.properties&.title.to_s.strip }.reject(&:empty?)
  end

  # Selects tabs either by explicit allowlist or by all available titles.
  # Explicit names that do not exist are tracked as warnings.
  def select_tab_titles(available_titles, warnings)
    return available_titles if @tab_names.empty?

    selected = available_titles.select { |title| @tab_names.include?(title) }
    missing = @tab_names - selected
    missing.each { |name| warnings << "Requested tab not found: #{name}" }
    selected
  end

  # Fetches raw values for one tab.
  # Values are always returned as a 2D array to keep parser input consistent.
  def fetch_tab_values(service, tab_title, warnings)
    effective_range = @value_range.empty? ? ENV.fetch("GOOGLE_SHEETS_DEFAULT_RANGE", "A:ZZ") : @value_range
    a1_range = "'#{tab_title}'!#{effective_range}"
    response = service.get_spreadsheet_values(@spreadsheet_id, a1_range)

    {
      tab_name: tab_title,
      range: a1_range,
      values: Array(response&.values)
    }
  rescue Google::Apis::ClientError => e
    warnings << "Tab #{tab_title} could not be fetched: #{e.message}"
    nil
  rescue Google::Apis::ServerError => e
    warnings << "Tab #{tab_title} failed due to server issue: #{e.message}"
    nil
  rescue StandardError => e
    warnings << "Tab #{tab_title} fetch failed: #{e.message}"
    nil
  end

  def success_result(tabs:, warnings:, errors:)
    {
      ok: true,
      spreadsheet_id: @spreadsheet_id,
      tabs: tabs,
      warnings: warnings,
      errors: errors
    }
  end

  def failure_result(warnings:, errors:)
    {
      ok: false,
      spreadsheet_id: @spreadsheet_id,
      tabs: [],
      warnings: warnings,
      errors: errors
    }
  end

  def default_logger
    return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

    Logger.new($stdout)
  end
end
