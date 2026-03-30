# app/services/github_service.rb
require "octokit"

class GithubService
  CardInfo = Struct.new(:title, :status, :assignees, :fields, :type, :updated_at)
  CBPResult = Struct.new(:commit_count, :lines_added, :lines_removed, :lines_changed)
  BoardHealth = Struct.new(:cards, :status_options, :archived_column_exists, :stale_cards)

  def self.resolve_token(token: nil, team: nil, user: nil)
    candidates = [
      token,
      ENV["GITHUB_PAT"],
      team&.github_token,
      user&.github_token
    ]

    candidates.find { |value| value.present? }
  end

  def initialize(token: nil, team: nil, user: nil, logger: Rails.logger)
    @logger = logger
    resolved_token = self.class.resolve_token(token: token, team: team, user: user)

    if resolved_token.blank?
      @logger.warn("GithubService initialized without token")
      @client = nil
      return
    end

    @client = Octokit::Client.new(access_token: resolved_token)

    begin
      @client.user
    rescue Octokit::Unauthorized
      @logger.error("GithubService token is invalid or expired")
      @client = nil
    end
  end

  def available?
    @client.present?
  end

  # Fetch commits in date range
  def commits_in_range(repo, start_date, stop_date)
    return [] unless @client

    commits = []
    page = 1

    loop do
      batch = @client.commits(
        repo,
        per_page: 100,
        page: page,
        since: normalize_time(start_date),
        until: normalize_time(stop_date)
      )

      break if batch.empty?

      commits.concat(batch)
      page += 1
    end

    commits
  rescue Octokit::Unauthorized
    @logger.error("Unauthorized: cannot fetch commits for #{repo}")
    []
  end

  # Filter commits by username
  def commits_by_user(commits, username)
    return [] if username.blank?

    commits.select do |c|
      login = c.author&.login
      email_name = c.commit.author.name
      login == username || email_name == username
    end
  end

  def project_cards(project_url)
    board_health(project_url).cards
  end

  def board_health(project_url, stale_after_days: 14)
    return BoardHealth.new([], [], false, []) unless @client

    org, number = parse_project_url(project_url)
    return BoardHealth.new([], [], false, []) if org.blank? || number.blank?

    query = <<~GRAPHQL
      query($org: String!, $number: Int!) {
        organization(login: $org) {
          projectV2(number: $number) {
            title
            fields(first: 50) {
              nodes {
                __typename
                ... on ProjectV2SingleSelectField {
                  name
                  options {
                    name
                  }
                }
                ... on ProjectV2Field {
                  name
                }
              }
            }
            items(first: 100) {
              nodes {
                id
                updatedAt

                # Underlying content on the card: Issue, PR, or DraftIssue
                content {
                  __typename
                  ... on Issue {
                    title
                    url
                    assignees(first: 10) {
                      nodes {
                        login
                        name
                      }
                    }
                  }
                  ... on PullRequest {
                    title
                    url
                    assignees(first: 10) {
                      nodes {
                        login
                        name
                      }
                    }
                  }
                  ... on DraftIssue {
                    title
                  }
                }

                # Project-level fields (Status, custom fields, Assignees, etc.)
                fieldValues(first: 50) {
                  nodes {
                    __typename

                    ... on ProjectV2ItemFieldTextValue {
                      text
                      field { ... on ProjectV2FieldCommon { name } }
                    }

                    ... on ProjectV2ItemFieldSingleSelectValue {
                      name
                      field { ... on ProjectV2FieldCommon { name } }
                    }

                    ... on ProjectV2ItemFieldNumberValue {
                      number
                      field { ... on ProjectV2FieldCommon { name } }
                    }

                    ... on ProjectV2ItemFieldUserValue {
                      users(first: 10) {
                        nodes {
                          login
                          name
                        }
                      }
                      field { ... on ProjectV2FieldCommon { name } }
                    }
                  }
                }
              }
            }
          }
        }
      }
    GRAPHQL

    variables = { org: org, number: number }

    begin
      result = @client.post("graphql", { query: query, variables: variables }.to_json)
      project = result.dig(:data, :organization, :projectV2)

      if project.blank?
        user_query = query.gsub("organization(login: $org)", "user(login: $org)")
        user_result = @client.post("graphql", { query: user_query, variables: variables }.to_json)
        project = user_result.dig(:data, :user, :projectV2)
      end

      unless project
        @logger.warn("No project found or access denied for #{project_url}")
        return BoardHealth.new([], [], false, [])
      end

      items = project.dig(:items, :nodes) || []
      cards = items.map { |item| build_card(item) }

      status_options = project.dig(:fields, :nodes).to_a.filter_map do |field|
        next unless field[:__typename] == "ProjectV2SingleSelectField"
        next unless field[:name].to_s.casecmp("Status").zero?

        (field[:options] || []).map { |option| option[:name] }
      end.flatten.compact

      archived_column_exists = status_options.any? { |name| name.to_s.casecmp("archived").zero? }

      stale_cutoff = Time.current - stale_after_days.days
      stale_cards = stale_cards(cards, stale_cutoff: stale_cutoff)

      BoardHealth.new(cards, status_options, archived_column_exists, stale_cards)
    rescue StandardError => e
      @logger.error("GitHub project board query failed: #{e.class} - #{e.message}")
      BoardHealth.new([], [], false, [])
    end
  end

  def stale_cards(cards, stale_cutoff:, active_statuses: ["Backlog", "Todo", "To Do", "In Progress"])
    cards.select do |card|
      next false unless active_statuses.include?(card.status)
      next false if card.updated_at.blank?

      card.updated_at < stale_cutoff
    end
  end

  # FS&D: Number of cards per column
  def get_card_count_per_column(project_cards)
    column_counts = Hash.new(0)

    project_cards.each do |card|
      status = card.status || "Unspecified"
      column_counts[status] += 1
    end

    return column_counts
  end

  # FA: Number of cards assigned to each team member
  def get_card_count_per_assignee(project_cards, usernames = [])
    assignee_counts = Hash.new(0)
    usernames = Array(usernames).compact

    project_cards.each do |card|
      card.assignees.each do |assignee|
        if usernames.include?(assignee)
          assignee_counts[assignee] += 1
        end
      end
    end

    return assignee_counts
  end

  # TE: Sum of estimated hours per team member
  def get_total_hours_per_assignee(project_cards, usernames = [])
    assignee_counts = Hash.new(0)
    usernames = Array(usernames).compact

    project_cards.each do |card|
      card.assignees.each do |assignee|
        if usernames.include?(assignee)
          assignee_counts[assignee] += (card.fields["Time Estimate"] || 0)
        end
      end
    end

    return assignee_counts
  end

  def commit_metrics_by_user(repo, start_date, end_date)
    return {} unless @client

    commits = commits_in_range(repo, start_date, end_date)
    metrics = Hash.new { |hash, key| hash[key] = { commit_count: 0, lines_added: 0, lines_removed: 0 } }

    commits.each do |commit|
      username = commit.author&.login || commit.commit&.author&.name
      next if username.blank?

      details = @client.commit(repo, commit.sha)
      added = details.stats&.additions.to_i
      removed = details.stats&.deletions.to_i

      data = metrics[username]
      data[:commit_count] += 1
      data[:lines_added] += added
      data[:lines_removed] += removed
    rescue Octokit::NotFound
      next
    end

    metrics.transform_values do |value|
      CBPResult.new(
        value[:commit_count],
        value[:lines_added],
        value[:lines_removed],
        value[:lines_added] + value[:lines_removed]
      )
    end
  rescue StandardError => e
    @logger.error("Commit aggregate query failed for #{repo}: #{e.class} - #{e.message}")
    {}
  end

  # CBP: Count of commits and line changes
  def get_commit_info(repo, username, start_date, end_date)
    return CBPResult.new(0, 0, 0, 0) unless @client

    commits = commits_in_range(repo, start_date, end_date)
    user_commits = commits_by_user(commits, username)

    total_added = 0
    total_removed = 0

    user_commits.each do |c|
      detailed = @client.commit(repo, c.sha)

      # Safely handle commits without stats
      added    = detailed.stats&.additions.to_i
      removed  = detailed.stats&.deletions.to_i

      total_added   += added
      total_removed += removed
    end

    total_changed = total_added + total_removed

    CBPResult.new(
      user_commits.count,
      total_added,
      total_removed,
      total_changed
    )
  rescue Octokit::NotFound
    @logger.warn("Repository not found for commit query: #{repo}")
    CBPResult.new(0, 0, 0, 0)
  rescue StandardError => e
    @logger.error("Commit query failed for #{repo}: #{e.class} - #{e.message}")
    CBPResult.new(0, 0, 0, 0)
  end

  def parse_repo_url(repo_url)
    return nil if repo_url.blank?

    match = repo_url.match(%r{github\.com/([^/]+)/([^/]+)}i)
    return nil unless match

    "#{match[1]}/#{match[2].sub(/\.git\z/, "")}"
  end

  private

  def parse_project_url(project_url)
    return [nil, nil] if project_url.blank?

    normalized = project_url.to_s.strip

    org_match = normalized.match(%r{github\.com/orgs/([^/]+)/projects/(\d+)}i)
    return [org_match[1], org_match[2].to_i] if org_match

    user_match = normalized.match(%r{github\.com/users/([^/]+)/projects/(\d+)}i)
    return [user_match[1], user_match[2].to_i] if user_match

    [nil, nil]
  end

  def build_card(item)
    content = item[:content] || {}
    type = content[:__typename]
    item_title = content[:title] || "(no title)"

    fields = {}
    (item.dig(:fieldValues, :nodes) || []).each do |fv|
      field_name = fv.dig(:field, :name)
      next unless field_name

      case fv[:__typename]
      when "ProjectV2ItemFieldTextValue"
        fields[field_name] = fv[:text]
      when "ProjectV2ItemFieldSingleSelectValue"
        fields[field_name] = fv[:name]
      when "ProjectV2ItemFieldNumberValue"
        fields[field_name] = fv[:number]
      when "ProjectV2ItemFieldUserValue"
        users = (fv.dig(:users, :nodes) || []).map { |u| u[:login] || u[:name] }
        fields[field_name] = users
      end
    end

    status = fields["Status"]
    status = status.first if status.is_a?(Array)

    issue_assignees =
      if %w[Issue PullRequest].include?(type)
        (content.dig(:assignees, :nodes) || []).map { |u| u[:login] || u[:name] }
      else
        []
      end

    project_assignees = fields["Assignees"]
    assignees =
      if issue_assignees.any?
        issue_assignees
      elsif project_assignees.is_a?(Array)
        project_assignees
      elsif project_assignees
        Array(project_assignees)
      else
        []
      end

    CardInfo.new(item_title, status, assignees, fields, type, safe_parse_time(item[:updatedAt]))
  end

  def safe_parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def normalize_time(value)
    return value if value.respond_to?(:iso8601)

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    value
  end

end