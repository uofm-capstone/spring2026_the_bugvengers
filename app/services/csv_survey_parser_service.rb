# frozen_string_literal: true

require "csv"

class CSVSurveyParserService
  # Qualtrics/system fields we do not use for LLM feedback grouping.
  IGNORE_HEADERS = %w[
    startdate enddate status progress finished ipaddress
    duration_in_seconds responseid recipientfirstname recipientlastname recipientemail
    externalreference locationlatitude locationlongitude distributionchannel userlanguage
  ].freeze

  TEAM_HINT = /which\s+project\s+team/i
  SPRINT_HINT = /which\s+sprint/i
  FEEDBACK_HEADER = /\Aq7\z/i
  RESPONSE_HEADERS = [ /\Aq2_\d+\z/i, /\Aq4\z/i, /\Aq5\z/i, /\Aq6\z/i, /\Aq7\z/i ].freeze

  def initialize(file: nil, csv_string: nil, logger: Rails.logger)
    @file = file
    @csv_string = csv_string
    @logger = logger
  end

  # Returns grouped team responses for LLM consumption.
  def call
    parse[:dataset]
  end

  # Returns parsing details for internal callers that need row-level data.
  # This includes:
  # - grouped dataset for LLM handoff
  # - normalized rows for existing UI helpers
  # - question text map for q2_* display labels
  # - warnings/errors for safe diagnostics
  def parse
    warnings = []
    errors = []

    raw_rows = parse_rows(errors)
    return empty_result(warnings: warnings, errors: errors) if raw_rows.empty?

    # Qualtrics export convention:
    # row 1 = machine headers, row 2 = human-readable question text,
    # row 3 = ImportId metadata, row 4+ = actual responses.
    headers = raw_rows[0].map { |h| h.to_s.strip }
    question_row = raw_rows[1] || []
    data_rows = raw_rows.drop(3)

    if headers.empty?
      errors << "Missing header row"
      return empty_result(warnings: warnings, errors: errors)
    end

    team_index = detect_team_index(headers, question_row)
    sprint_index = detect_sprint_index(headers, question_row)
    q7_index = detect_index(headers, FEEDBACK_HEADER)

    if q7_index.nil?
      errors << "Missing required feedback column Q7"
      @logger.error("CSVSurveyParserService: Missing required feedback column Q7")
      return empty_result(warnings: warnings, errors: errors)
    end

    full_questions = build_full_questions(headers, question_row)
    grouped = Hash.new { |h, k| h[k] = [] }
    rows = []
    respondents = []

    submitted_at_index = detect_normalized_index(headers, "recordeddate") || detect_normalized_index(headers, "startdate")
    response_id_index = detect_normalized_index(headers, "responseid")

    data_rows.each_with_index do |row, index|
      next if skip_row?(row)

      begin
        cleaned = clean_row_values(row)
        q7_value = cleaned[q7_index]
        # Q7 is the primary open-ended field required by the parsing plan.
        next if q7_value.nil?

        team_name = team_index.nil? ? nil : cleaned[team_index]
        team_name = "Unknown Team" if team_name.nil? || team_name.empty?
        sprint = sprint_index.nil? ? nil : cleaned[sprint_index]

        normalized_row = build_normalized_row(headers, cleaned, team_index, sprint_index)
        normalized_row[:q3] = sprint if sprint

        question_responses = build_question_responses(headers, question_row, cleaned)
        respondent_id = response_id_index.nil? ? nil : cleaned[response_id_index]
        submitted_at = submitted_at_index.nil? ? nil : cleaned[submitted_at_index]

        respondents << {
          respondent_id: respondent_id,
          responses: question_responses,
          metadata: {
            submitted_at: submitted_at,
            sprint: sprint,
            team: team_name
          }
        }

        rows << {
          team: team_name,
          sprint: sprint,
          q7: q7_value,
          responses: question_responses,
          raw: normalized_row
        }

        # Final LLM grouping payload uses team => [q7 responses].
        grouped[team_name] << q7_value
      rescue StandardError => e
        warnings << "Row #{index + 4} skipped: #{e.message}"
        @logger.warn("CSVSurveyParserService: row #{index + 4} skipped (#{e.class}): #{e.message}")
      end
    end

    dataset = grouped.map do |team, responses|
      { team: team, responses: responses }
    end

    {
      dataset: dataset,
      # Keep legacy-compatible keys used by existing helpers/views.
      rows: rows.map { |r| r[:raw].merge(q1_team: r[:team], q3: r[:sprint], q7: r[:q7]) },
      full_questions: full_questions,
      respondents: respondents,
      warnings: warnings,
      errors: errors
    }
  rescue StandardError => e
    @logger.error("CSVSurveyParserService failed: #{e.class} - #{e.message}")
    empty_result(warnings: warnings, errors: errors + [e.message])
  end

  private

  def parse_rows(errors)
    csv_source = load_source
    return [] if csv_source.nil? || csv_source.strip.empty?

    # Defensive encoding conversion prevents hard crashes on mixed encodings.
    encoded = csv_source.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    CSV.parse(encoded, headers: false)
  rescue CSV::MalformedCSVError => e
    errors << "Malformed CSV: #{e.message}"
    @logger.error("CSVSurveyParserService malformed CSV: #{e.message}")
    []
  rescue StandardError => e
    errors << "Unable to parse CSV: #{e.message}"
    @logger.error("CSVSurveyParserService parse error: #{e.class} - #{e.message}")
    []
  end

  def load_source
    return @csv_string if @csv_string.present?
    return nil if @file.nil?

    if @file.respond_to?(:read)
      content = @file.read
      @file.rewind if @file.respond_to?(:rewind)
      return content
    end

    return File.read(@file) if @file.is_a?(String)

    nil
  end

  def clean_row_values(row)
    row.map do |value|
      cleaned = value.to_s.strip
      cleaned.empty? ? nil : cleaned
    end
  end

  def build_normalized_row(headers, values, team_index, _sprint_index)
    normalized_headers = deduplicated_normalized_headers(headers)
    row_hash = {}

    normalized_headers.each_with_index do |key, index|
      next if ignored_header?(key)

      row_hash[key.to_sym] = values[index]
    end

    if team_index
      row_hash[:q1_team] = values[team_index]
    end

    row_hash
  end

  def deduplicated_normalized_headers(headers)
    seen = Hash.new(0)

    headers.map.with_index do |header, index|
      base = normalize_header(header)
      base = "col_#{index + 1}" if base.empty?

      # Duplicate headers can exist in Qualtrics (e.g., repeated Q1); suffix to preserve all values.
      seen[base] += 1
      seen[base] == 1 ? base : "#{base}_#{seen[base]}"
    end
  end

  def normalize_header(header)
    header.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
  end

  def ignored_header?(header)
    IGNORE_HEADERS.include?(header.to_s)
  end

  def build_question_responses(headers, question_row, values)
    responses = []

    headers.each_with_index do |header, index|
      next unless RESPONSE_HEADERS.any? { |pattern| header.to_s.match?(pattern) }

      answer = values[index]
      next if answer.nil?

      responses << {
        question: question_row[index].to_s.strip.presence || header,
        answer: answer,
        type: infer_response_type(header, answer)
      }
    end

    responses
  end

  def infer_response_type(header, answer)
    return :scale if header.to_s.match?(/\Aq2_\d+\z/i)

    normalized = answer.to_s.downcase
    return :scale if normalized.include?("expectation")
    return :multiple_choice if normalized.include?(";")

    :text
  end

  def build_full_questions(headers, question_row)
    headers.each_with_index.with_object({}) do |(header, index), acc|
      next unless header.to_s.match?(/\Aq2_\d+\z/i)

      # q2_* prompt text is shown in the team view.
      acc[header] = question_row[index].to_s.strip
    end
  end

  def detect_team_index(headers, question_row)
    question_index = question_row.index { |value| value.to_s.match?(TEAM_HINT) }
    return question_index unless question_index.nil?

    detect_index(headers, /\Aq1\z/i)
  end

  def detect_sprint_index(headers, question_row)
    question_index = question_row.index { |value| value.to_s.match?(SPRINT_HINT) }
    return question_index unless question_index.nil?

    detect_index(headers, /\Aq3\z/i)
  end

  def detect_index(headers, regex)
    headers.find_index { |header| header.to_s.match?(regex) }
  end

  def detect_normalized_index(headers, normalized_name)
    headers.find_index { |header| normalize_header(header) == normalized_name }
  end

  def skip_row?(row)
    return true if row.nil? || row.all? { |value| value.to_s.strip.empty? }

    # Extra guard: some exports may include embedded metadata rows.
    row.any? { |value| value.to_s.include?("\"ImportId\"") }
  end

  def empty_result(warnings:, errors:)
    { dataset: [], rows: [], full_questions: {}, respondents: [], warnings: warnings, errors: errors }
  end
end
