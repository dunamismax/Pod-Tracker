require "test_helper"

module Codex
  class QuotaPolicyTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @user.codex_account&.destroy
      @user.analysis_runs.destroy_all
      AnalysisRun.where(user: users(:two)).destroy_all
      @clock_time = Time.utc(2026, 5, 5, 12, 0, 0)
      @clock = -> { @clock_time }
    end

    def policy(config: { per_user_per_day: 5, global_per_day: 10, window: 24.hours, expected_runtime_seconds: 30 })
      QuotaPolicy.new(@user, clock: @clock, config: config)
    end

    test "allows analysis when no runs in window and Codex is connected" do
      connect_codex!(rate_limit: { "primary" => { "used" => 1, "limit" => 100, "resetsAt" => "2026-05-05T13:00:00Z" } })

      decision = policy.check
      assert decision.allowed?
      assert_equal 0, decision.user_used
      assert_equal 5, decision.user_remaining
      assert_equal 0, decision.global_used
      assert_equal 30, decision.expected_runtime_seconds
      assert_equal :ok, decision.rate_limit_status
      assert_match(/Codex primary window/, decision.rate_limit_summary)
    end

    test "blocks when per-user quota is exhausted" do
      connect_codex!
      5.times do
        @user.analysis_runs.create!(kind: "ai", rubric_version: "v", queued_at: @clock_time - 30.minutes, status: "succeeded")
      end

      decision = policy.check
      assert decision.blocked?
      assert_includes decision.reasons, :user_quota_exhausted
      assert_equal 0, decision.user_remaining
    end

    test "ignores canceled runs and runs older than the window for quota counts" do
      connect_codex!
      3.times do
        @user.analysis_runs.create!(kind: "ai", rubric_version: "v", queued_at: @clock_time - 30.minutes, status: "canceled")
      end
      @user.analysis_runs.create!(kind: "ai", rubric_version: "v", queued_at: @clock_time - 2.days, status: "succeeded")

      decision = policy.check
      assert_equal 0, decision.user_used
      assert decision.allowed?
    end

    test "blocks when global quota is exhausted" do
      other = users(:two)
      connect_codex!
      10.times do
        other.analysis_runs.create!(kind: "ai", rubric_version: "v", queued_at: @clock_time - 30.minutes, status: "succeeded")
      end

      decision = policy.check
      assert decision.blocked?
      assert_includes decision.reasons, :global_quota_exhausted
      assert_equal 0, decision.global_remaining
    end

    test "blocks when no Codex account is connected" do
      decision = policy.check
      assert decision.blocked?
      assert_includes decision.reasons, :codex_account_disconnected
      assert_equal :unknown, decision.rate_limit_status
    end

    test "marks rate-limit blocked when Codex primary window is exhausted" do
      connect_codex!(rate_limit: { "primary" => { "used" => 100, "limit" => 100, "resetsAt" => "2026-05-05T15:00:00Z" } })

      decision = policy.check
      assert decision.blocked?
      assert_equal :blocked, decision.rate_limit_status
      assert_includes decision.reasons, :codex_rate_limit_blocked
    end

    test "marks tight when remaining ratio is between 10% and 25%" do
      connect_codex!(rate_limit: { "primary" => { "used" => 80, "limit" => 100 } })

      decision = policy.check
      assert decision.allowed?
      assert_equal :tight, decision.rate_limit_status
    end

    test "blocks when Codex credentials have expired" do
      connect_codex!(credentials_expire_at: @clock_time - 1.hour)
      decision = policy.check
      assert decision.blocked?
      assert_includes decision.reasons, :codex_credentials_expired
    end

    private

    def connect_codex!(rate_limit: {}, credentials_expire_at: nil)
      @user.create_codex_account!(
        auth_mode: "chatgpt_browser",
        status: "connected",
        encrypted_credential_payload: "tok",
        rate_limit_snapshot: rate_limit,
        credentials_expire_at: credentials_expire_at,
        connected_at: @clock_time - 1.day
      )
    end
  end
end
