require "test_helper"

class TeamsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
  end

  test "should get index" do
    get teams_url
    assert_response :success
  end

  test "should get show" do
    team = teams(:one)
    get team_url(team)
    assert_response :success
  end

  test "should get new" do
    get new_team_url
    assert_response :success
  end

  test "should get create" do
    semester = semesters(:one)
    # Select the semester and store it in the session.
    post select_semester_url(semester)
    assert_response :redirect
    # Verify that creating a team increases the total count by one.
    assert_difference("Team.count", 1) do
      post teams_url, params: {
        team: {
          name: "Test Team",
          description: "Team created during testing"
        }
      }
    end
    assert_redirected_to teams_path
  end

  test "should get edit" do
    team = teams(:one)
    get edit_team_url(team)
    assert_response :success
  end

  test "should get update" do
    team = teams(:one)
    patch team_url(team), params: {
      team: {
        name: "Updated Test Team",
        description: "Updated during testing"
      }
    }
    assert_redirected_to teams_path
    team.reload
    assert_equal "Updated Test Team", team.name
    assert_equal "Updated during testing", team.description
  end

  test "should get destroy" do
    team = teams(:one)

    assert_difference("Team.count", -1) do
      delete team_url(team)
    end

    assert_redirected_to teams_path
    assert_nil Team.find_by(id: team.id)
  end
end
