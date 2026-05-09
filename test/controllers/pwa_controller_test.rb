require "test_helper"

class PwaControllerTest < ActionDispatch::IntegrationTest
  test "manifest is reachable without authentication and identifies the app" do
    get pwa_manifest_path

    assert_response :success
    body = response.parsed_body
    assert_equal "Pod Tracker", body["name"]
    assert_equal "/?source=pwa", body["start_url"]
    assert_equal "standalone", body["display"]

    icons = body["icons"]
    assert icons.is_a?(Array) && icons.any?, "manifest should declare icons"
    assert icons.any? { |i| i["purpose"]&.include?("maskable") }, "manifest must declare a maskable icon for Android adaptive launchers"

    shortcuts = body["shortcuts"]
    assert shortcuts.is_a?(Array)
    urls = shortcuts.map { |s| s["url"] }
    %w[/decks?source=pwa-shortcut /pods?source=pwa-shortcut /sessions?source=pwa-shortcut].each do |expected|
      assert_includes urls, expected
    end
  end

  test "service worker is reachable without authentication and is versioned" do
    get pwa_service_worker_path

    assert_response :success
    assert_match %r{\bjavascript\b}, response.media_type
    assert_match(/CACHE_VERSION = "[^"]+"/, response.body)
    assert_match(/pod-tracker-shell-/, response.body)
    assert_match(/pod-tracker-pages-/, response.body)
    assert_match(/SKIP_WAITING/, response.body)
    assert_match(/CLEAR_PAGE_CACHE/, response.body)
    assert_match(/PAGES_CACHE_PREFIX = "pod-tracker-pages-"/, response.body)
  end

  test "layout links the manifest so installability is discoverable" do
    get root_path

    assert_response :success
    assert_match %r{<link rel="manifest"[^>]*href="/manifest\.json"}, response.body
    assert_match %r{<meta name="theme-color"[^>]*content="#09090b"}, response.body
    assert_match %r{<meta name="apple-mobile-web-app-title"[^>]*content="Pod Tracker"}, response.body
  end
end
