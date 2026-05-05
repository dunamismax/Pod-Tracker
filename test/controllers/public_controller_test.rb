require "test_helper"

class PublicControllerTest < ActionDispatch::IntegrationTest
  test "the public home page renders without authentication" do
    get root_path
    assert_response :success
    assert_select "h1", /Commander companion|Ideal Magic|bracket/i
  end

  test "the brackets page renders the long-form guide and the Game Changers list" do
    get brackets_path
    assert_response :success
    assert_select "h1", /Commander Brackets/i
    assert_select "h2", /Bracket 1|Exhibition/
    assert_select "h2", /Game Changers/
  end

  test "the Game Changers page renders without authentication" do
    get game_changers_path
    assert_response :success
    assert_select "h1", /Game Changers/i
  end

  test "the pregame template page renders without authentication" do
    get pregame_template_path
    assert_response :success
    assert_select "h1", /Pregame|Rule 0/i
  end

  test "the about, privacy, and terms pages render without authentication" do
    [ about_path, privacy_path, terms_path ].each do |path|
      get path
      assert_response :success, "expected #{path} to render"
    end
  end

  test "public pages do not redirect signed-in users away" do
    sign_in_as users(:one)
    get brackets_path
    assert_response :success
  end
end
