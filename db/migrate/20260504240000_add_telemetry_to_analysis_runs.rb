class AddTelemetryToAnalysisRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :analysis_runs, :codex_rate_limit_snapshot, :jsonb, null: false, default: {}
    add_column :analysis_runs, :latency_ms, :integer
    add_index :analysis_runs, :latency_ms
  end
end
