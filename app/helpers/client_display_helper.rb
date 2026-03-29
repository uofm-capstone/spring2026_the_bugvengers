module ClientDisplayHelper

    def get_git_info(semester)
      # Read CSV data from the file
      semester.git_csv.open do |tempGit|
        # Read CSV data from the attachment
        csv = CSV.parse(tempGit, headers: true)

        # Initialize dictionaries to hold start and end dates for each sprint
        start_dates = {}
        end_dates = {}

        # Initialize dictionaries for repo owners, repo names, and GitHub access tokens indexed by team names
        repo_owners = {}
        repo_names = {}
        access_tokens = {}
        team_names = []
        sprint_numbers = []

        # Iterate over each row in the CSV data
        csv.each do |row|
          sprint_number = row["Sprint Number"]
          start_date = row["Sprint Start Date"]
          end_date = row["Sprint End Date"]
          team_name = row["Team Name"]
          repo_owner = row["Repository Owner"]
          repo_name = row["Repository Name"]
          git_token = row["Github Access Token"]

          team_names << team_name if team_name
          sprint_numbers << sprint_number if sprint_number

          # Check if team name is present
          if team_name
            # Initialize dictionaries for the team if not already initialized
            repo_owners[team_name] ||= {}
            repo_names[team_name] ||= {}
            access_tokens[team_name] ||= {}

            # Add repository owner, repository name, and GitHub access token to the respective dictionaries
            repo_owners[team_name] = repo_owner if repo_owner
            repo_names[team_name] = repo_name if repo_name
            access_tokens[team_name] = git_token if git_token
          end

          # Check if sprint number, start date, and end date are present
          if sprint_number && start_date && end_date
            # Add start and end dates to the respective dictionaries
            start_dates["start_date_sprint_#{sprint_number.split(' ')[1]}"] = start_date
            end_dates["end_date_sprint_#{sprint_number.split(' ')[1]}"] = end_date

            start_dates["Sprint #{sprint_number.split(' ')[1]}"] = start_dates["start_date_sprint_#{sprint_number.split(' ')[1]}"]
            end_dates["Sprint #{sprint_number.split(' ')[1]}"] =  end_dates["end_date_sprint_#{sprint_number.split(' ')[1]}"]
          end
        end

        # Return the dictionaries of start and end dates along with dictionaries of repo owners, repo names, and git tokens
        return start_dates, end_dates, team_names, repo_owners, repo_names, access_tokens, sprint_numbers
      end
    end

    def process_client_data(semester, team, sprint)
      client_data = {}
      flags = []

      begin
        semester.client_csv.open do |tempClient|
          # Centralized parser returns both grouped LLM payload and helper-friendly normalized rows.
          parsed = CSVSurveyParserService.new(file: tempClient).parse
          flags.append("client csv error") if parsed[:errors].present?

          client_data_raw = parsed[:rows]
          # q2_* prompt labels are extracted from the second CSV row by the service.
          full_questions = parsed[:full_questions]

          @client_question_titles = client_data_raw[0]&.select { |key, _| key.to_s.start_with?('q') } || {}

          # Preserve prior behavior: select one best-matching team within the requested sprint.
          cliSurvey = best_matching_team_rows(client_rows: client_data_raw, team: team, sprint: sprint)
          cliSurvey.map! { |survey| survey.select { |key, _| key.to_s.start_with?('q') } }


          if cliSurvey.blank?
            flags.append("client blank")
          end

          client_data = {
            full_questions: full_questions,
            cliSurvey: cliSurvey
          }
        end
      rescue => e
        Rails.logger.debug("DEBUG: Exception processing client CSV: #{e}")
        flags.append("client csv error")
      end

      [client_data, flags]
    end

    # Shared matcher used by both team page rendering and semester status flags.
    # It narrows rows by sprint, then chooses the closest team name match.
    def best_matching_team_rows(client_rows:, team:, sprint:)
      sprint_rows = client_rows.select do |row|
        row[:q3].to_s.strip.casecmp?(sprint.to_s.strip)
      end
      return [] if sprint_rows.blank?

      best_matching_team = nil
      max_similarity = 0.0

      sprint_rows.each do |client_survey|
        next if client_survey[:q1_team].blank? || client_survey[:q1_team].start_with?('{')

        similarities = compare_strings(team.to_s, client_survey[:q1_team].to_s)
        avg_similarity = (similarities[:jaro_winkler].to_f + similarities[:levenshtein].to_f) / 2.0

        if avg_similarity > max_similarity
          max_similarity = avg_similarity
          best_matching_team = client_survey[:q1_team]
        end
      end

      return [] if best_matching_team.blank?

      sprint_rows.select { |survey| survey[:q1_team] == best_matching_team }
    end

    private


end
