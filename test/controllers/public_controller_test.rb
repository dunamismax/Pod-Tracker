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

  test "the public layout emits the site-wide JSON-LD graph" do
    get root_path
    assert_response :success
    assert_select "script[type='application/ld+json']", minimum: 1
    assert_match %r{"@type":\s*"Organization"}, response.body
    assert_match %r{"@type":\s*"WebSite"}, response.body
  end

  test "the brackets page emits Article and BreadcrumbList structured data" do
    get brackets_path
    assert_response :success
    assert_match %r{"@type":\s*"Article"}, response.body
    assert_match %r{"@type":\s*"BreadcrumbList"}, response.body
  end

  test "every public page declares a canonical link" do
    [ root_path, brackets_path, game_changers_path, pregame_template_path,
      about_path, privacy_path, terms_path ].each do |path|
      get path
      assert_response :success, "expected #{path} to render"
      assert_select "link[rel='canonical']", count: 1
    end
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
