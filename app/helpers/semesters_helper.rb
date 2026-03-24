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

end
