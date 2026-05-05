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

  test "the sitemap renders the public marketing URLs as XML" do
    get sitemap_path
    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_match %r{<urlset}, response.body
    assert_match Regexp.new(Regexp.escape(brackets_url)), response.body
    assert_match Regexp.new(Regexp.escape(game_changers_url)), response.body
    assert_match Regexp.new(Regexp.escape(pregame_template_url)), response.body
  end
end
