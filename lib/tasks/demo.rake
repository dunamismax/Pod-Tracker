namespace :demo do
  demo_email = "demo@demo.com"

  desc "Reset the demo@demo.com account: wipe owned data and restore profile defaults."
  task reset: :environment do
    user = User.find_by(email_address: demo_email)
    abort "Demo user #{demo_email} not found. Run bin/rails db:seed first." unless user

    summary = {}
    User.transaction do
      summary[:decks] = user.decks.count
      user.decks.destroy_all

      summary[:analysis_runs] = user.analysis_runs.count
      user.analysis_runs.destroy_all

      summary[:pod_evaluations] = user.pod_evaluations.count
      user.pod_evaluations.destroy_all

      summary[:codex_login_attempts] = user.codex_login_attempts.count
      user.codex_login_attempts.destroy_all

      summary[:codex_account] = user.codex_account ? 1 : 0
      user.codex_account&.destroy

      summary[:provider_links] = user.provider_links.count
      user.provider_links.destroy_all

      summary[:audit_events] = user.audit_events.count
      user.audit_events.destroy_all

      user.update!(
        display_name: "Demo Player",
        timezone: "UTC",
        preferred_units: "imperial",
        email_verified_at: Time.current
      )

      AuditEvent.create!(
        user: user,
        auditable: user,
        event_name: "demo.reset",
        occurred_at: Time.current,
        metadata: summary.transform_values(&:to_i)
      )
    end

    puts "Reset demo user #{demo_email} (id=#{user.id}). Removed: #{summary.inspect}"
  end

  desc "Show what bin/rails demo:reset would remove without changing anything."
  task status: :environment do
    user = User.find_by(email_address: demo_email)
    abort "Demo user #{demo_email} not found. Run bin/rails db:seed first." unless user

    puts "Demo user #{demo_email} (id=#{user.id})"
    puts "  decks:                #{user.decks.count}"
    puts "  analysis_runs:        #{user.analysis_runs.count}"
    puts "  pod_evaluations:      #{user.pod_evaluations.count}"
    puts "  codex_login_attempts: #{user.codex_login_attempts.count}"
    puts "  codex_account:        #{user.codex_account ? "linked" : "none"}"
    puts "  provider_links:       #{user.provider_links.count}"
    puts "  audit_events:         #{user.audit_events.count}"
  end
end
