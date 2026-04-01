module ClientScoreHelper
      include ClientSurveyPatternsHelper
      #
      # Look at the client_servay_pattern_helper
      #

      def calculate_score(matching_row, performance_columns)
        # Convert each q2_* client evaluation response to numeric score.
        performance_scores = performance_columns.map do |col|
          response = matching_row[col]
          performance_to_score(response)
        end

        # Filter out the scores that are zero
        positive_scores = performance_scores.reject { |score| score.zero? }

        # If there are no positive scores (all were zero), return zero or some default value
        return 0.0 if positive_scores.empty?

        # Calculate the average from the positive scores only
        performance_average = positive_scores.sum.to_f / positive_scores.size
        performance_average.round(1)
      end

      def get_client_score(semester, team, sprint)
        # Restricts fuzzy team matching to reasonably close strings only.
        similarity_threshold = 0.1  # Adjust this for team matching as needed

        semester.client_csv.open do |tempfile|
          begin
            # Reuse centralized parsing rules (Qualtrics rows, metadata skipping, normalization).
            parsed = CSVSurveyParserService.new(file: tempfile).parse
            # Hard parse failure: no rows available, return user-facing error string.
            return "Error! Unable to read sponsor data." if parsed[:errors].present? && parsed[:rows].blank?

            table = parsed[:rows]
            # Valid parse but no usable rows for scoring.
            return "No Score" if table.blank?

            # Performance columns remain q2_* fields used by existing scoring logic.
            performance_columns = table.first&.keys&.select { |header| header.to_s.match?(PERFORMANCE_PATTERN) } || []
            sprint_column = table.first&.keys&.find { |header| header.to_s.match?(SPRINT_PATTERN) }
            team_column = :q1_team

            best_match = nil
            smallest_distance = Float::INFINITY

            table.each do |row|
              # First, match sprints exactly to avoid sprint confusion
              next unless row[sprint_column].to_s.strip.downcase == sprint.strip.downcase

              # Calculate Levenshtein distance for team names
              team_distance = Levenshtein.distance(row[team_column].to_s.strip.downcase, team.strip.downcase).to_f / [row[team_column].to_s.length, team.length].max

              # Lower distance means a closer team name match.
              if team_distance < smallest_distance && team_distance < similarity_threshold
                smallest_distance = team_distance
                best_match = row
              end
            end

            unless best_match
              Rails.logger.debug "No Matching Row Found for Sprint: #{sprint}"
              return "No Score"
            end

            Rails.logger.debug "Best Matching Row Found for Sprint: #{sprint}: #{best_match}"
            performance_average = calculate_score(best_match, performance_columns)
            performance_average

          rescue => exception
            Rails.logger.error("Error processing CSV: #{exception.message}")
            "Error! Unable to read sponsor data."
          end
        end
      end
end
