require "test_helper"

class TeamRegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get new_team_registration_path
    assert_response :success
  end

  test "should create team" do
    semester = Semester.first || Semester.create!(name: "Test Semester")

    assert_difference('Team.count', 1) do
      post team_registration_path, params: {
        team: {
          name: "Test Team",
          description: "Test Team description",
          semester_id: semester.id
        }
      }
    end
    assert_redirected_to root_path
  end
end
