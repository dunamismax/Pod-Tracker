require "test_helper"

class SeededUsersTest < ActiveSupport::TestCase
  ADMIN_EMAIL = "stephenvsawyer@gmail.com".freeze
  DEMO_EMAIL = "demo@demo.com".freeze

  setup do
    User.where(email_address: [ ADMIN_EMAIL, DEMO_EMAIL ]).destroy_all
    @prior_admin_password = ENV["IDEAL_MAGIC_ADMIN_PASSWORD"]
    @prior_demo_password = ENV["IDEAL_MAGIC_DEMO_PASSWORD"]
  end

  teardown do
    ENV["IDEAL_MAGIC_ADMIN_PASSWORD"] = @prior_admin_password
    ENV["IDEAL_MAGIC_DEMO_PASSWORD"] = @prior_demo_password
  end

  test "seed creates a verified demo user with the default password when env var is unset" do
    ENV.delete("IDEAL_MAGIC_DEMO_PASSWORD")
    ENV.delete("IDEAL_MAGIC_ADMIN_PASSWORD")

    load_user_seed

    demo = User.find_by(email_address: DEMO_EMAIL)
    assert demo, "demo user should be created"
    assert demo.email_verified?
    assert_equal "imperial", demo.preferred_units
    assert demo.authenticate("demo1234"), "demo user should authenticate with default password"
    refute User.exists?(email_address: ADMIN_EMAIL), "admin user should be skipped without env var"
  end

  test "seed creates the admin user when IDEAL_MAGIC_ADMIN_PASSWORD is set" do
    ENV["IDEAL_MAGIC_ADMIN_PASSWORD"] = "supersecretdemo"
    ENV.delete("IDEAL_MAGIC_DEMO_PASSWORD")

    load_user_seed

    admin = User.find_by(email_address: ADMIN_EMAIL)
    assert admin, "admin user should be created"
    assert admin.email_verified?
    assert admin.authenticate("supersecretdemo")
    assert_equal "Stephen Sawyer", admin.display_name
  end

  test "seed updates an existing user's password when re-run with a new env value" do
    ENV["IDEAL_MAGIC_DEMO_PASSWORD"] = "first-password"
    load_user_seed
    demo = User.find_by!(email_address: DEMO_EMAIL)
    first_digest = demo.password_digest

    ENV["IDEAL_MAGIC_DEMO_PASSWORD"] = "second-password"
    load_user_seed
    demo.reload
    refute_equal first_digest, demo.password_digest
    assert demo.authenticate("second-password")
  end

  test "seed does not overwrite an existing email_verified_at" do
    ENV["IDEAL_MAGIC_DEMO_PASSWORD"] = "demo1234"
    load_user_seed
    demo = User.find_by!(email_address: DEMO_EMAIL)
    original_verified_at = demo.email_verified_at
    assert original_verified_at

    travel 5.minutes do
      load_user_seed
    end
    demo.reload
    assert_equal original_verified_at.to_i, demo.email_verified_at.to_i
  end

  private

  def load_user_seed
    load Rails.root.join("db/seeds/users.rb")
  end
end
