# Idempotent seed for the baked-in accounts:
#
# - Admin (Stephen): email is fixed; password is read from IDEAL_MAGIC_ADMIN_PASSWORD.
#   The password is intentionally NOT committed. The seed skips creating the admin
#   account if the env var is unset and the user does not already exist.
# - Demo: a public demonstration account. Credentials are demo@demo.com / demo1234
#   unless IDEAL_MAGIC_DEMO_PASSWORD is set. Anyone with the URL can sign in.
# - Beta: a shared beta-tester account. Credentials are beta@beta.com / beta1234
#   unless IDEAL_MAGIC_BETA_PASSWORD is set. Beta testers sign in and can connect
#   their own Codex account through the normal flow.
#
# Re-running this seed updates passwords and resets profile fields. It does not
# delete existing decks or audit history; use `bin/rails demo:reset` to factory-
# reset the demo user.

admin_email = "stephenvsawyer@gmail.com"
demo_email = "demo@demo.com"
demo_default_password = "demo1234"
beta_email = "beta@beta.com"
beta_default_password = "beta1234"

admin_password = ENV["IDEAL_MAGIC_ADMIN_PASSWORD"].to_s
admin_existing = User.find_by(email_address: admin_email)

if admin_password.present?
  admin = admin_existing || User.new(email_address: admin_email)
  admin.assign_attributes(
    password: admin_password,
    display_name: "Stephen Sawyer",
    timezone: "UTC",
    preferred_units: "imperial",
    email_verified_at: admin.email_verified_at || Time.current
  )
  admin.save!
  Rails.logger.info("[seed] Admin user #{admin_email} #{admin.previously_new_record? ? "created" : "updated"}.")
elsif admin_existing.nil?
  Rails.logger.info("[seed] Skipping admin user: IDEAL_MAGIC_ADMIN_PASSWORD not set.")
end

demo = User.find_or_initialize_by(email_address: demo_email)
demo.assign_attributes(
  password: ENV.fetch("IDEAL_MAGIC_DEMO_PASSWORD", demo_default_password),
  display_name: "Demo Player",
  timezone: "UTC",
  preferred_units: "imperial",
  email_verified_at: demo.email_verified_at || Time.current
)
demo.save!
Rails.logger.info("[seed] Demo user #{demo_email} #{demo.previously_new_record? ? "created" : "updated"}.")

beta = User.find_or_initialize_by(email_address: beta_email)
beta.assign_attributes(
  password: ENV.fetch("IDEAL_MAGIC_BETA_PASSWORD", beta_default_password),
  display_name: "Beta Tester",
  timezone: "UTC",
  preferred_units: "imperial",
  email_verified_at: beta.email_verified_at || Time.current
)
beta.save!
Rails.logger.info("[seed] Beta user #{beta_email} #{beta.previously_new_record? ? "created" : "updated"}.")
