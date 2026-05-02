require "csv"

class StudentRosterImportService
  HEADER_CANDIDATES = {
    name: ["full name", "fullname", "name"],
    email: ["email", "e-mail", "e mail"],
    team: ["team", "group"],
    github_username: ["github username", "github_username", "github"],
    repo_url: ["repo url", "repository link", "repository", "repo"],
    project_board: ["github project board link", "project board", "project_board"],
    timesheet: ["timesheet link", "timesheet", "timesheet_url"],
    client_notes: ["client meeting notes link", "client meeting notes", "client_notes"]
  }.freeze

  def initialize(semester:, file:, logger: Rails.logger)
    @semester = semester
    @file = file
    @logger = logger
  end

  def import
    return failure("No CSV file provided.") if @file.blank?

    csv = CSV.read(@file.path, headers: true)
    headers = csv.headers.map { |h| h.to_s.strip }

    header_map = build_header_map(headers)
    if header_map[:name].nil? || header_map[:email].nil?
      return failure("Missing required columns: Full Name and Email")
    end

    previous_team_name = nil
    previous_repo_url = nil
    previous_project_board = nil
    previous_timesheet = nil
    previous_client_notes = nil

    row_errors = []
    created_count = 0
    updated_count = 0
    skipped_count = 0

    csv.each_with_index do |row, i|
      begin
        name             = row[header_map[:name]]&.strip
        email            = row[header_map[:email]]&.strip&.downcase
        raw_team_name    = row[header_map[:team]]&.strip
        raw_repo_url     = row[header_map[:repo_url]]&.strip
        raw_project_board= row[header_map[:project_board]]&.strip
        raw_timesheet    = row[header_map[:timesheet]]&.strip
        raw_client_notes = row[header_map[:client_notes]]&.strip
        github_username  = row[header_map[:github_username]]&.strip

        if raw_team_name.present? && raw_team_name != previous_team_name
          previous_repo_url = nil
          previous_project_board = nil
          previous_timesheet = nil
          previous_client_notes = nil
        end

        team_name     = raw_team_name.presence     || previous_team_name
        repo_url      = raw_repo_url.presence      || previous_repo_url
        project_board = raw_project_board.presence || previous_project_board
        timesheet     = raw_timesheet.presence     || previous_timesheet
        client_notes  = raw_client_notes.presence  || previous_client_notes

        previous_team_name     = raw_team_name     if raw_team_name.present?
        previous_repo_url      = raw_repo_url      if raw_repo_url.present?
        previous_project_board = raw_project_board if raw_project_board.present?
        previous_timesheet     = raw_timesheet     if raw_timesheet.present?
        previous_client_notes  = raw_client_notes  if raw_client_notes.present?

        next if name.blank? && email.blank?

        if name.blank?
          row_errors << "Row #{i + 2}: Missing Full Name"
          skipped_count += 1
          next
        end

        if email.blank? || !(email =~ URI::MailTo::EMAIL_REGEXP)
          row_errors << "Row #{i + 2}: Missing or invalid Email (#{email})"
          skipped_count += 1
          next
        end

        url_fields = {
          "Repo URL" => repo_url,
          "Project Board URL" => project_board,
          "Timesheet URL" => timesheet,
          "Client Notes URL" => client_notes
        }
        url_fields.each do |label, url|
          if url.present? && !(url =~ /\Ahttps?:\/\/[\S]+\z/)
            row_errors << "Row #{i + 2}: #{label} is invalid: #{url}"
            skipped_count += 1
            next
          end
        end

        team = @semester.teams.find_or_create_by!(name: team_name) if team_name.present?
        if team
          team.repo_url           ||= repo_url
          team.project_board_url  ||= project_board
          team.timesheet_url      ||= timesheet
          team.client_notes_url   ||= client_notes
          team.save! if team.changed?
        end

        existing_student = @semester.students.find_by(email: email)
        if existing_student
          existing_student.assign_attributes(
            name: name,
            full_name: name,
            github_username: github_username,
            project_board_url: project_board,
            timesheet_url: timesheet,
            client_notes_url: client_notes
          )

          if existing_student.changed?
            existing_student.save!
            updated_count += 1
          else
            skipped_count += 1
          end

          student = existing_student
        else
          student = @semester.students.create!(
            name: name,
            full_name: name,
            email: email,
            github_username: github_username,
            project_board_url: project_board,
            timesheet_url: timesheet,
            client_notes_url: client_notes
          )
          created_count += 1
        end

        if team && !team.students.exists?(student.id)
          team.students << student
        end
      rescue => row_error
        @logger.error("Row #{i + 2} failed: #{row_error.message}")
        row_errors << "Row #{i + 2}: #{row_error.message}"
        skipped_count += 1
        next
      end
    end

    summary = "#{created_count} created, #{updated_count} updated, #{skipped_count} skipped."

    if row_errors.any?
      return failure("Import completed with errors. #{summary} Details: #{row_errors.join(' | ')}")
    end

    success("Import completed successfully. #{summary}")
  rescue => e
    @logger.error("CSV import failed: #{e.class} - #{e.message}")
    failure("Import failed: #{e.message}")
  end

  private

  def build_header_map(headers)
    header_map = {}
    HEADER_CANDIDATES.each do |key, candidates|
      found = headers.find { |h| candidates.include?(h.downcase) }
      header_map[key] = found
    end
    header_map
  end

  def success(message)
    { ok: true, message: message }
  end

  def failure(message)
    { ok: false, message: message }
  end
end
