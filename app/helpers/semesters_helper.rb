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
      "GitHub Composite: weighted score from KAN (35%), CBP (30%), PR (20%), and RVW (15%)."
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

end
