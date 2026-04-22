module SemestersHelper
  def semester_name(semester)
    "#{semester.semester.capitalize} #{semester.year}"
  end

  def semester_dropdown_menu(semester)
    content_tag :div, class: 'dropdown' do
      concat(semester_dropdown_toggle(semester))
      concat(semester_dropdown_items(semester))
    end
  end

  def semester_dropdown_toggle(semester)
    link_to '#', class: 'dropdown-toggle', role: 'button', id: 'dropdownMenuLink',
            data: { bs_toggle: 'dropdown'}, aria: { haspopup: 'true', expanded: 'false' } do
      content_tag(:i, '', class: 'fas ellipsis-v')
    end
  end

  def semester_dropdown_items(semester)
    content_tag :div, class: 'dropdown-menu', aria: { labelledby: 'dropdownMenu' } do
      concat(semester_delete_link(semester))
    end
  end

  def semester_delete_link(semester)
    link_to 'Delete', semester_path(semester), method: :delete,
            data: { confirm: "Are you sure you want to delete #{semester.semester} #{semester.year}?" },
            class: 'dropdown-item'
  end

  def team_risk_reason_preview(summary)
    Array(summary[:at_risk_reason_preview]).join(" | ")
  end

  def sprint_pill_state_class(sprint_metric)
    sprint_metric[:at_risk] ? "is-risk" : "is-healthy"
  end

  def format_card_counts(card_counts)
    (card_counts || {}).map { |status, count| "#{status}=#{count}" }.join(" | ")
  end

  def format_students_without_commits(usernames)
    list = Array(usernames)
    list.present? ? list.join(", ") : "None"
  end

  def github_score_state_class(score)
    value = score.to_f
    return "is-strong" if value >= 85
    return "is-solid" if value >= 70
    return "is-watch" if value >= 55

    "is-risk"
  end

  def compact_score(value)
    format("%.1f", value.to_f)
  end

  def github_chip_tooltip(chip)
    case chip.to_s.upcase
    when "GH"
      "GitHub Composite: combined indicator from commit activity, pull request flow, and review participation for the sprint window."
    when "CBP"
      "Coding Best Practices: based on commit activity and code churn (lines changed) during the sprint window."
    when "PR"
      "Pull Request workflow: rewards opened/merged PRs and faster merge velocity; penalizes lingering open PRs."
    when "RVW"
      "Review activity: based on reviews submitted, approvals, and changes-requested signals during the sprint."
    else
      "GitHub grading component."
    end
  end

  def format_missing_github_flags(flags)
    Array(flags).map { |flag| flag.to_s.tr("_", " ") }.map(&:capitalize).join(", ")
  end

  def formatted_last_commit_display(metric)
    payload = metric[:last_commit] || {}
    flags = Array(payload[:missing_data_flags]).map(&:to_s)
    data_available = payload[:data_available]
    timestamp = payload[:at].presence || metric[:last_commit_at].presence

    return "No GitHub username" if flags.include?("no_github_username")
    return format_last_commit_timestamp(timestamp) if timestamp.present?

    unavailable_flags = %w[repo_missing token_unavailable github_query_failed github_query_timeout github_student_data_unavailable]
    return "GitHub data unavailable" if data_available == false || (flags & unavailable_flags).any?

    "No commits in sprint"
  end

  def format_last_commit_timestamp(timestamp)
    time = if timestamp.respond_to?(:in_time_zone)
      timestamp
    else
      Time.zone.parse(timestamp.to_s)
    end

    return timestamp.to_s if time.blank?

    time.in_time_zone("America/Chicago").strftime("%b %-d, %Y %-l:%M %p CT")
  rescue ArgumentError, TypeError
    timestamp.to_s
  end

  def team_last_commit_summary(team:, sprint:, status_metrics:)
    student_metrics = team.students.map do |student|
      status_metrics.dig(team.id, student.id, sprint) || {}
    end

    latest_commit = student_metrics
      .filter_map { |metric| metric.dig(:last_commit, :at).presence || metric[:last_commit_at].presence }
      .filter_map { |value| parse_last_commit_time(value) }
      .max

    return "Latest: #{format_last_commit_timestamp(latest_commit)}" if latest_commit.present?
    return "GitHub data unavailable" if team_last_commit_data_unavailable?(student_metrics)

    "No commits in sprint"
  end

  def team_last_commit_data_unavailable?(student_metrics)
    unavailable_flags = %w[
      repo_missing
      token_unavailable
      github_query_failed
      github_query_timeout
      github_student_data_unavailable
    ]

    Array(student_metrics).any? do |metric|
      payload = metric[:last_commit] || {}
      flags = Array(payload[:missing_data_flags]).map(&:to_s)
      payload[:data_available] == false || (flags & unavailable_flags).any?
    end
  end

  def parse_last_commit_time(value)
    return value if value.respond_to?(:in_time_zone)

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

end
