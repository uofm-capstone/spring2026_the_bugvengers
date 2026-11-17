require "test_helper"

class AdminControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:one)
  end

  test "should get dashboard" do
    get admin_dashboard_url
    assert_response :success
  end
end