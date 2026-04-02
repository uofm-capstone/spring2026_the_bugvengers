require "test_helper"

class SemestersHelperTest < ActionView::TestCase
  test "team_risk_reason_preview joins reasons" do
    summary = { at_risk_reason_preview: ["Missing done", "No commits"] }

    assert_equal "Missing done | No commits", team_risk_reason_preview(summary)
  end

  test "sprint_pill_state_class returns risk class" do
    assert_equal "is-risk", sprint_pill_state_class({ at_risk: true })
    assert_equal "is-healthy", sprint_pill_state_class({ at_risk: false })
  end

  test "format_card_counts prints status and count pairs" do
    counts = { "Backlog" => 2, "Done" => 4 }

    assert_equal "Backlog=2 | Done=4", format_card_counts(counts)
  end

  test "format_students_without_commits handles empty and populated values" do
    assert_equal "None", format_students_without_commits([])
    assert_equal "alice, bob", format_students_without_commits(["alice", "bob"])
  end
end
