# Defaults for the per-user and global analysis quota policy. Set either cap
# to 0 to disable it. The current production deployment runs with both caps
# disabled because access is limited to the seeded accounts and trusted
# friends; the only meaningful AI ceiling is the upstream Codex rate limit
# on the linked ChatGPT account, which QuotaPolicy still surfaces.
Rails.application.config.x.analysis_quota = ActiveSupport::OrderedOptions.new.merge!(
  per_user_per_day: ENV.fetch("POD_TRACKER_ANALYSIS_PER_USER_PER_DAY", 0).to_i,
  global_per_day: ENV.fetch("POD_TRACKER_ANALYSIS_GLOBAL_PER_DAY", 0).to_i,
  window: 24.hours,
  expected_runtime_seconds: ENV.fetch("POD_TRACKER_ANALYSIS_EXPECTED_RUNTIME_SECONDS", 25).to_i
)
