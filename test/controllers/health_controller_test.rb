require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  test "readiness returns ready when the database answers" do
    get readiness_check_path

    assert_response :success
    assert_equal({ "status" => "ready" }, response.parsed_body)
  end
end
