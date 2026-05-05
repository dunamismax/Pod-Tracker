require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "redirects unauthenticated users away from the dashboard" do
    get app_dashboard_path

    assert_redirected_to new_session_path
  end

  test "shows the dashboard for authenticated users" do
    sign_in_as users(:one)

    get app_dashboard_path

    assert_response :success
    assert_select "h1", "Ideal Magic"
  end
end
