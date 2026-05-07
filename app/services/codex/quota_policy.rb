module Codex
  # Combines local app-policy analysis quotas (per-user and global daily caps)
  # with the latest Codex App Server rate-limit snapshot stored on a user's
  # CodexAccount, returning a single decision struct that controllers and
  # views can use to:
  #
  # - Decide whether to enqueue a new AI analysis for a user.
  # - Surface the remaining daily budget and Codex rate-limit state in the UI
  #   *before* a user kicks off an expensive evaluation.
  # - Render an honest expected-runtime estimate alongside the budget summary.
  #
  # The policy never decides arbitrary OpenAI API quota for the user. The
  # only "Codex" inputs are the rate-limit fields the App Server reports
  # through CodexAccount. App-level caps remain the authoritative gate.
  class QuotaPolicy
    Decision = Struct.new(
      :allowed,
      :reasons,
      :user_used,
      :user_limit,
      :user_remaining,
      :global_used,
      :global_limit,
      :global_remaining,
      :window_started_at,
      :expected_runtime_seconds,
      :rate_limit_status,
      :rate_limit_summary,
      :rate_limit_resets_at,
      :codex_connected,
      keyword_init: true
    ) do
      def allowed?
        allowed
      end

      def blocked?
        !allowed
      end
    end

    DEFAULT_RUNTIME_SECONDS = 25

    def initialize(user, clock: -> { Time.current }, config: nil)
      @user = user
      @clock = clock
      @config = config || Rails.application.config.x.analysis_quota
    end

    # Class-level convenience used by controllers and views: `Codex::QuotaPolicy.for(user).check`.
    def self.for(user, **kwargs)
      new(user, **kwargs)
    end

    def check
      now = @clock.call
      window_start = now - window

      user_used = user_run_count(window_start)
      global_used = global_run_count(window_start)

      user_limit = per_user_per_day
      global_limit = global_per_day
      user_remaining = remaining_for(user_limit, user_used)
      global_remaining = remaining_for(global_limit, global_used)

      account = @user.respond_to?(:codex_account) ? @user.codex_account : nil
      rate_limit_status, rate_limit_summary, rate_limit_resets_at = inspect_rate_limit(account)

      reasons = []
      reasons << :user_quota_exhausted if quota_enforced?(user_limit) && user_remaining <= 0
      reasons << :global_quota_exhausted if quota_enforced?(global_limit) && global_remaining <= 0
      reasons << :codex_account_disconnected unless account&.connected?
      reasons << :codex_rate_limit_blocked if rate_limit_status == :blocked
      reasons << :codex_credentials_expired if account&.connected? && credential_expired?(account, now)

      Decision.new(
        allowed: reasons.empty?,
        reasons: reasons,
        user_used: user_used,
        user_limit: user_limit,
        user_remaining: user_remaining,
        global_used: global_used,
        global_limit: global_limit,
        global_remaining: global_remaining,
        window_started_at: window_start,
        expected_runtime_seconds: expected_runtime_seconds,
        rate_limit_status: rate_limit_status,
        rate_limit_summary: rate_limit_summary,
        rate_limit_resets_at: rate_limit_resets_at,
        codex_connected: account&.connected? || false
      )
    end

    private

    # A non-positive cap means "unlimited" — the gate skips the check and the
    # UI surfaces "no daily cap" instead of a misleading remaining count.
    def per_user_per_day
      Integer(@config[:per_user_per_day] || 0)
    end

    def per_user_per_day_safe
      [ per_user_per_day, 0 ].max
    end

    def global_per_day
      Integer(@config[:global_per_day] || 0)
    end

    def quota_enforced?(limit)
      limit.is_a?(Integer) && limit.positive?
    end

    def remaining_for(limit, used)
      return nil unless quota_enforced?(limit)
      clamp_nonneg(limit - used)
    end

    def window
      duration = @config[:window]
      duration.is_a?(ActiveSupport::Duration) ? duration : 24.hours
    end

    def expected_runtime_seconds
      Integer(@config[:expected_runtime_seconds] || DEFAULT_RUNTIME_SECONDS)
    end

    def user_run_count(window_start)
      AnalysisRun.counted_for_quota.where(user_id: @user.id).queued_since(window_start).count
    end

    def global_run_count(window_start)
      AnalysisRun.counted_for_quota.queued_since(window_start).count
    end

    def clamp_nonneg(value)
      value.negative? ? 0 : value
    end

    def credential_expired?(account, now)
      account.credentials_expire_at.present? && account.credentials_expire_at <= now
    end

    # Inspect the rate-limit snapshot stored on CodexAccount. The App Server
    # surface is still being defined; we accept the documented `primary` /
    # `secondary` window shape and degrade gracefully when fields are missing.
    def inspect_rate_limit(account)
      return [ :unknown, "Codex account is not connected.", nil ] unless account&.connected?

      snapshot = account.rate_limit_snapshot.presence || {}
      return [ :unknown, "No Codex rate-limit data yet. Connect or refresh status to populate.", nil ] if snapshot.blank?

      windows = extract_windows(snapshot)
      return [ :unknown, "Codex rate limits are reported but in an unfamiliar shape.", nil ] if windows.empty?

      worst = windows.min_by { |w| w[:remaining_ratio] }
      status = if worst[:remaining_ratio] <= 0
        :blocked
      elsif worst[:remaining_ratio] < 0.1
        :critical
      elsif worst[:remaining_ratio] < 0.25
        :tight
      else
        :ok
      end

      [ status, format_window_summary(worst), worst[:resets_at] ]
    end

    # Walk the rate-limit snapshot and surface every {primary, secondary}
    # window we can find. The Codex App Server returns either a flat object
    # (legacy / test fixtures) or a dict keyed by limit id ("codex",
    # "premium", ...) with `usedPercent` rather than absolute `used` / `limit`.
    def extract_windows(snapshot)
      pools = collect_pools(snapshot)
      windows = []
      pools.each do |pool_label, pool|
        %w[primary secondary].each do |key|
          window = pool[key] || pool[key.to_sym]
          next unless window.is_a?(Hash)
          ratio = window_remaining_ratio(window)
          next unless ratio
          windows << {
            label: pool_label ? "#{pool_label} #{key}" : key,
            remaining_ratio: ratio,
            resets_at: parse_resets_at(window["resetsAt"] || window[:resets_at] || window[:resetsAt])
          }
        end
      end
      windows
    end

    def collect_pools(snapshot)
      return [] unless snapshot.is_a?(Hash)
      direct = snapshot.key?("primary") || snapshot.key?(:primary) || snapshot.key?("secondary") || snapshot.key?(:secondary)
      return [ [ nil, snapshot ] ] if direct

      snapshot.each_with_object([]) do |(key, value), acc|
        next unless value.is_a?(Hash)
        pool_label = (value["limitId"] || value[:limitId] || key).to_s
        acc << [ pool_label, value ]
      end
    end

    def window_remaining_ratio(window)
      if window.key?("usedPercent") || window.key?(:usedPercent)
        used_percent = numeric(window["usedPercent"] || window[:usedPercent])
        return nil unless used_percent
        [ (100.0 - used_percent) / 100.0, 0.0 ].max
      else
        used = numeric(window["used"] || window[:used])
        limit = numeric(window["limit"] || window[:limit])
        return nil unless used && limit && limit.positive?
        [ (limit - used) / limit.to_f, 0.0 ].max
      end
    end

    def numeric(value)
      return value if value.is_a?(Numeric)
      return nil if value.nil?
      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    def parse_resets_at(value)
      return nil if value.nil? || value == ""
      return Time.zone.at(value) if value.is_a?(Numeric)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def format_window_summary(window)
      pct_remaining = (window[:remaining_ratio] * 100).round
      base = "Codex #{window[:label]} window: #{pct_remaining}% remaining."
      return base unless window[:resets_at]
      "#{base} Resets #{window[:resets_at].utc.iso8601}."
    end
  end
end
