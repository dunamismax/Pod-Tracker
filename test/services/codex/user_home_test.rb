require "test_helper"

module Codex
  class UserHomeTest < ActiveSupport::TestCase
    setup do
      @tmp_root = Pathname.new(Dir.mktmpdir("codex-home-test-"))
      UserHome.root_path_override = @tmp_root
      @user = users(:one)
    end

    teardown do
      UserHome.reset_root_override!
      FileUtils.remove_entry(@tmp_root) if @tmp_root.exist?
    end

    test "path_for returns root joined with user id" do
      assert_equal @tmp_root.join(@user.id.to_s), UserHome.path_for(@user)
    end

    test "ensure! creates the directory with mode 0700" do
      path = UserHome.ensure!(@user)
      assert path.exist?
      mode = File.stat(path).mode & 0o777
      assert_equal 0o700, mode, "expected 0700, got #{mode.to_s(8)}"
    end

    test "ensure! writes file-backed credential storage config" do
      path = UserHome.ensure!(@user)
      config_path = path.join("config.toml")

      assert config_path.exist?
      assert_includes config_path.read, 'cli_auth_credentials_store = "file"'
      mode = File.stat(config_path).mode & 0o777
      assert_equal 0o600, mode, "expected 0600, got #{mode.to_s(8)}"
    end

    test "has_auth? reflects on-disk auth.json" do
      UserHome.ensure!(@user)
      refute UserHome.has_auth?(@user)
      File.write(UserHome.path_for(@user).join("auth.json"), "{}")
      assert UserHome.has_auth?(@user)
    end

    test "purge! removes the user directory entirely" do
      UserHome.ensure!(@user)
      File.write(UserHome.path_for(@user).join("auth.json"), "{}")
      UserHome.purge!(@user)
      refute UserHome.path_for(@user).exist?
    end

    test "root_path honors CODEX_HOME_ROOT env var" do
      UserHome.reset_root_override!
      assert_equal Pathname.new("/var/lib/ideal-magic/codex"),
                   UserHome.root_path(env: { "CODEX_HOME_ROOT" => "/var/lib/ideal-magic/codex" })
    ensure
      UserHome.root_path_override = @tmp_root
    end

    test "root_path falls back to a Rails-rooted dev path when no env is set" do
      UserHome.reset_root_override!
      path = UserHome.root_path(env: {})
      assert path.to_s.end_with?("tmp/codex_home"), "got #{path}"
    ensure
      UserHome.root_path_override = @tmp_root
    end

    test "path_for refuses an unpersisted user" do
      assert_raises(UserHome::Error) { UserHome.path_for(User.new) }
    end

    test "two users get distinct paths" do
      other = users(:two)
      refute_equal UserHome.path_for(@user), UserHome.path_for(other)
    end
  end
end
