# frozen_string_literal: true

require "date"
require "logger"

# GoogleSheetsTimesheetParserService converts raw worksheet values into an
# analysis-ready structure. This parser is intentionally separate from API
# fetching so future teams can update parsing heuristics without touching
# authentication/network code.
#
# Expected input tab shape (from GoogleSheetsTimesheetFetcherService):
# {
#   tab_name: "Sprint 4 PC 1",
#   values: [
#     ["Team Member", "Row Type", "4/7/2026", "4/8/2026", "Weekly Total"],
#     ["Jonathan", "Hours Spent", "1.5", "2.0", "3.5"],
#     ["", "Activity", "class time", "coding", ""]
#   ]
# }
#
# Output shape:
# {
#   ok: true,
#   records: [
#     {
#       sprint_tab: "Sprint 4 PC 1",
#       team_member: "Jonathan",
#       entries: [
#         { date: "2026-04-07", hours: 1.5, activity: "class time" }
#       ],
#       weekly_total: 3.5
#     }
#   ],
#   warnings: [],
#   errors: []
# }
class GoogleSheetsTimesheetParserService
  # These patterns define default tab auto-detection behavior when callers do
  # not provide explicit tab names.
  LIKELY_SPRINT_TAB_PATTERN = /(\bsprint\b|\bpc\b)/i

  # These labels appear in summary/display columns that should not become daily
  # entries. We still read totals separately when useful.
  SUMMARY_COLUMN_PATTERN = /(total|weekly\s*total|sum|overall)/i

  # Timesheet row-label hints used to identify paired rows.
  HOURS_ROW_PATTERN = /(hours?\s*spent|hours?)/i
  ACTIVITY_ROW_PATTERN = /(activity|description|work\s*done|notes?)/i

  # Header scan limit keeps parsing fast while still tolerant of top-of-sheet
  # spacing and title rows.
  MAX_HEADER_SCAN_ROWS = 8

  def initialize(tabs:, tab_names: nil, logger: nil)
    @tabs = Array(tabs)
    @tab_names = Array(tab_names).map { |name| name.to_s.strip }.reject(&:empty?)
    @logger = logger || default_logger
  end

  # Parses selected tabs and returns normalized timesheet records.
  def call
    warnings = []
    errors = []

    selected_tabs = select_tabs(@tabs, warnings)
    return success_result(records: [], tabs_processed: [], warnings: warnings, errors: errors) if selected_tabs.empty?

    all_records = []

    selected_tabs.each do |tab|
      tab_name = tab[:tab_name].to_s.strip
      values = Array(tab[:values])

      if values.empty?
        warnings << "Tab #{tab_name} has no rows"
        next
      end

      begin
        records = parse_tab_rows(tab_name: tab_name, values: values, warnings: warnings)
        all_records.concat(records)
      rescue StandardError => e
        warnings << "Tab #{tab_name} could not be parsed: #{e.message}"
        @logger.warn("GoogleSheetsTimesheetParserService tab parse warning for #{tab_name}: #{e.class} - #{e.message}")
      end
    end

    success_result(
      records: all_records,
      tabs_processed: selected_tabs.map { |tab| tab[:tab_name] },
      warnings: warnings,
      errors: errors
    )
  rescue StandardError => e
    @logger.error("GoogleSheetsTimesheetParserService failed: #{e.class} - #{e.message}")
    {
      ok: false,
      records: [],
      tabs_processed: [],
      warnings: [],
      errors: [e.message]
    }
  end

  private

  # Explicit tab allowlist takes priority. If no allowlist is passed, we
  # auto-select likely sprint tabs (Sprint/PC). If no likely tab is found, we
  # parse all tabs and emit a warning so data is not silently skipped.
  def select_tabs(all_tabs, warnings)
    sanitized = all_tabs.map do |tab|
      {
        tab_name: tab[:tab_name].to_s.strip,
        values: Array(tab[:values])
      }
    end.reject { |tab| tab[:tab_name].empty? }

    return select_explicit_tabs(sanitized, warnings) unless @tab_names.empty?

    likely_tabs = sanitized.select { |tab| tab[:tab_name].match?(LIKELY_SPRINT_TAB_PATTERN) }
    return likely_tabs unless likely_tabs.empty?

    warnings << "No likely sprint tabs detected; parsing all tabs instead"
    sanitized
  end

  def select_explicit_tabs(sanitized_tabs, warnings)
    selected = sanitized_tabs.select { |tab| @tab_names.include?(tab[:tab_name]) }
    missing = @tab_names - selected.map { |tab| tab[:tab_name] }
    missing.each { |name| warnings << "Requested tab not found for parser: #{name}" }
    selected
  end

  # Parses one tab using a tolerant row-pair strategy:
  # - Detect date columns from the strongest header-like row.
  # - Find member rows with hours data.
  # - Optionally pair next row as activity row.
  def parse_tab_rows(tab_name:, values:, warnings:)
    normalized_rows = normalize_rows(values)
    header_info = detect_date_columns(normalized_rows)

    if header_info[:date_columns].empty?
      warnings << "Tab #{tab_name} has no date columns; skipped"
      return []
    end

    records = []
    index = header_info[:header_row_index] + 1

    while index < normalized_rows.length
      row = normalized_rows[index]
      member_name = extract_member_name(row)

      if member_name.nil?
        index += 1
        next
      end

      hours_row_index = find_hours_row_index(normalized_rows, index, header_info[:date_columns])
      if hours_row_index.nil?
        warnings << "Tab #{tab_name}, member #{member_name}: no hours row found"
        index += 1
        next
      end

      hours_row = normalized_rows[hours_row_index]
      activity_row_index = find_activity_row_index(normalized_rows, hours_row_index, header_info[:date_columns])
      activity_row = activity_row_index.nil? ? nil : normalized_rows[activity_row_index]

      entries, entry_warnings = build_entries(
        date_columns: header_info[:date_columns],
        hours_row: hours_row,
        activity_row: activity_row
      )

      entry_warnings.each do |warning|
        warnings << "Tab #{tab_name}, member #{member_name}: #{warning}"
      end

      if entries.empty?
        warnings << "Tab #{tab_name}, member #{member_name}: no usable day entries"
        index = [index + 1, hours_row_index + 1].max
        next
      end

      records << {
        sprint_tab: tab_name,
        team_member: member_name,
        entries: entries,
        weekly_total: extract_weekly_total(
          header_row: normalized_rows[header_info[:header_row_index]],
          hours_row: hours_row
        )
      }

      # Skip past the parsed block to avoid duplicate member records.
      index = [hours_row_index, activity_row_index || hours_row_index].max + 1
    end

    records
  end

  # Makes rows rectangular so column index lookups are stable even when some
  # source rows are shorter due to blank trailing cells.
  def normalize_rows(values)
    max_width = values.map { |row| Array(row).length }.max.to_i

    values.map do |row|
      cells = Array(row).map { |cell| cell.to_s.strip }
      cells + Array.new([max_width - cells.length, 0].max, "")
    end
  end

  # Finds the row with the strongest date-signal in the top section of the tab.
  # That row determines which columns are treated as daily work columns.
  def detect_date_columns(rows)
    best_row_index = 0
    best_date_columns = {}

    scan_limit = [rows.length, MAX_HEADER_SCAN_ROWS].min

    (0...scan_limit).each do |row_index|
      date_columns = {}
      rows[row_index].each_with_index do |cell, col_index|
        iso_date = parse_cell_to_iso_date(cell)
        date_columns[col_index] = iso_date if iso_date
      end

      next if date_columns.empty?

      if date_columns.length > best_date_columns.length
        best_date_columns = date_columns
        best_row_index = row_index
      end
    end

    {
      header_row_index: best_row_index,
      date_columns: best_date_columns
    }
  end

  # Accepts common date formats typically used in timesheets.
  def parse_cell_to_iso_date(cell)
    value = cell.to_s.strip
    return nil if value.empty?

    # Date parser should not treat summary labels or plain text as dates.
    return nil if value.match?(SUMMARY_COLUMN_PATTERN)
    return nil unless value.match?(/\d{1,2}[\/\-]\d{1,2}|[A-Za-z]{3,9}\s+\d{1,2}/)

    parse_date_value(value)&.iso8601
  rescue ArgumentError
    nil
  end

  # Date.parse can interpret slash-based values differently depending on
  # locale/parser heuristics. We prefer explicit month/day formats first because
  # capstone timesheets use US-style mm/dd/yyyy notation.
  def parse_date_value(value)
    [
      "%m/%d/%Y",
      "%m/%d/%y",
      "%m-%d-%Y",
      "%m-%d-%y",
      "%b %d %Y",
      "%B %d %Y",
      "%b %d, %Y",
      "%B %d, %Y"
    ].each do |format|
      return Date.strptime(value, format)
    rescue ArgumentError
      next
    end

    Date.parse(value)
  end

  # Member name is usually in the first column. We reject common non-name
  # labels so header rows do not accidentally become team members.
  def extract_member_name(row)
    candidate = row[0].to_s.strip
    return nil if candidate.empty?

    normalized = candidate.downcase
    return nil if normalized.match?(/\A(team\s*member|member|name|date|week|sprint|activity|hours?\s*spent)\z/)

    candidate
  end

  # Finds the row that most likely contains hour values for the current member.
  # We first check the current row, then one row ahead for merged/offset layouts.
  def find_hours_row_index(rows, start_index, date_columns)
    [start_index, start_index + 1].each do |row_index|
      next if row_index >= rows.length

      row = rows[row_index]
      label = row[1].to_s.downcase

      return row_index if label.match?(HOURS_ROW_PATTERN)
      return row_index if numeric_cell_count(row, date_columns.keys) >= 1
    end

    nil
  end

  # Activity row is usually directly below the hours row.
  # We treat it as activity if row label says activity/description OR if date
  # cells are mostly text-like values.
  def find_activity_row_index(rows, hours_row_index, date_columns)
    candidate_index = hours_row_index + 1
    return nil if candidate_index >= rows.length

    row = rows[candidate_index]
    label = row[1].to_s.downcase

    return candidate_index if label.match?(ACTIVITY_ROW_PATTERN)

    text_count = text_cell_count(row, date_columns.keys)
    numeric_count = numeric_cell_count(row, date_columns.keys)

    return candidate_index if text_count.positive? && numeric_count.zero?

    nil
  end

  # Builds normalized day entries from the date columns.
  # Non-numeric hours are tolerated with warnings so parsing can continue.
  def build_entries(date_columns:, hours_row:, activity_row:)
    entries = []
    warnings = []

    date_columns.each do |col_index, iso_date|
      raw_hours = hours_row[col_index].to_s.strip
      raw_activity = activity_row.nil? ? "" : activity_row[col_index].to_s.strip

      hours_value, hours_warning = parse_hours(raw_hours)
      warnings << "invalid hours '#{raw_hours}' on #{iso_date}" if hours_warning

      activity_value = raw_activity.empty? ? nil : raw_activity

      # Keep entries when either hours or activity exists so downstream analysis
      # can reason about partially-filled days instead of losing context.
      next if hours_value.nil? && activity_value.nil?

      entries << {
        date: iso_date,
        hours: hours_value,
        activity: activity_value
      }
    end

    [entries, warnings]
  end

  def parse_hours(raw_hours)
    return [nil, false] if raw_hours.empty?

    normalized = raw_hours.gsub(",", "")
    return [normalized.to_f, false] if normalized.match?(/\A-?\d+(\.\d+)?\z/)

    [nil, true]
  end

  # Weekly totals are often in summary columns; we keep this value at the member
  # record level for downstream checks but exclude summary columns from entries.
  def extract_weekly_total(header_row:, hours_row:)
    header_row.each_with_index do |header_value, col_index|
      next unless header_value.to_s.match?(SUMMARY_COLUMN_PATTERN)

      parsed, warning = parse_hours(hours_row[col_index].to_s.strip)
      return parsed unless warning
    end

    nil
  end

  def numeric_cell_count(row, col_indexes)
    col_indexes.count do |index|
      value = row[index].to_s.strip
      value.match?(/\A-?\d+(\.\d+)?\z/)
    end
  end

  def text_cell_count(row, col_indexes)
    col_indexes.count do |index|
      value = row[index].to_s.strip
      !value.empty? && !value.match?(/\A-?\d+(\.\d+)?\z/)
    end
  end

  def success_result(records:, tabs_processed:, warnings:, errors:)
    {
      ok: true,
      records: records,
      tabs_processed: tabs_processed,
      warnings: warnings,
      errors: errors
    }
  end

  def default_logger
    return Rails.logger if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

    Logger.new($stdout)
  end
end
