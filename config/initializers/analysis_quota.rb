# Defaults for the per-user and global analysis quota policy. The values are
# overridable per-environment if a future operator surface needs different
# ceilings; for v1 they are conservative defaults that keep AI evaluation
# bounded while still letting individual users iterate on a deck.
Rails.application.config.x.analysis_quota = ActiveSupport::OrderedOptions.new.merge!(
  per_user_per_day: ENV.fetch("IDEAL_MAGIC_ANALYSIS_PER_USER_PER_DAY", 25).to_i,
  global_per_day: ENV.fetch("IDEAL_MAGIC_ANALYSIS_GLOBAL_PER_DAY", 500).to_i,
  window: 24.hours,
  expected_runtime_seconds: ENV.fetch("IDEAL_MAGIC_ANALYSIS_EXPECTED_RUNTIME_SECONDS", 25).to_i
)
