require "test_helper"

class AnalysisRunTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "default queued_at is set on create when not supplied" do
    run = AnalysisRun.create!(rubric_version: "2026-05-04")
    assert_not_nil run.queued_at
  end

  test "validates kind and status" do
    run = AnalysisRun.new(kind: "bogus", status: "weird", rubric_version: "2026-05-04")
    assert_not run.valid?
    assert_includes run.errors[:kind], "is not included in the list"
    assert_includes run.errors[:status], "is not included in the list"
  end

  test "ai? true for ai and combined kinds" do
    assert AnalysisRun.new(kind: "ai", rubric_version: "v").ai?
    assert AnalysisRun.new(kind: "combined", rubric_version: "v").ai?
    assert_not AnalysisRun.new(kind: "deterministic", rubric_version: "v").ai?
  end

  test "counted_for_quota scope returns only AI runs that are not canceled" do
    AnalysisRun.create!(user: @user, kind: "deterministic", rubric_version: "v", status: "succeeded")
    canceled = AnalysisRun.create!(user: @user, kind: "ai", rubric_version: "v", status: "canceled")
    counted_ai = AnalysisRun.create!(user: @user, kind: "ai", rubric_version: "v", status: "succeeded")
    counted_combined = AnalysisRun.create!(user: @user, kind: "combined", rubric_version: "v", status: "queued")

    ids = AnalysisRun.counted_for_quota.where(user: @user).pluck(:id)
    assert_includes ids, counted_ai.id
    assert_includes ids, counted_combined.id
    assert_not_includes ids, canceled.id
  end

  test "queued_since scope filters by queued_at threshold" do
    fresh = AnalysisRun.create!(user: @user, kind: "ai", rubric_version: "v", queued_at: 1.hour.ago)
    stale = AnalysisRun.create!(user: @user, kind: "ai", rubric_version: "v", queued_at: 3.days.ago)

    ids = AnalysisRun.queued_since(24.hours.ago).pluck(:id)
    assert_includes ids, fresh.id
    assert_not_includes ids, stale.id
  end

  test "mark_started! and mark_succeeded! record latency and rate-limit snapshot" do
    run = AnalysisRun.create!(user: @user, kind: "ai", rubric_version: "v")
    started = Time.current
    run.mark_started!(now: started)
    assert_equal "running", run.status
    assert_in_delta started.to_f, run.started_at.to_f, 1

    snapshot = { "primary" => { "used" => 5, "limit" => 100 } }
    run.mark_succeeded!(now: started + 0.5, codex_rate_limit_snapshot: snapshot)
    assert_equal "succeeded", run.status
    assert_equal snapshot, run.codex_rate_limit_snapshot
    assert_equal 500, run.latency_ms
  end

  test "mark_failed! records latency, error code, and message" do
    run = AnalysisRun.create!(user: @user, kind: "ai", rubric_version: "v")
    run.mark_started!(now: Time.current - 0.25)
    run.mark_failed!(code: "transport_error", message: "boom")
    assert_equal "failed", run.status
    assert_equal "transport_error", run.error_code
    assert_equal "boom", run.error_message
    assert_operator run.latency_ms, :>=, 0
  end
end
