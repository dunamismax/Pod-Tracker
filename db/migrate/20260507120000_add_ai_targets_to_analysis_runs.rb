class AddAiTargetsToAnalysisRuns < ActiveRecord::Migration[8.1]
  def change
    add_reference :analysis_runs, :pod, foreign_key: true
    add_column :analysis_runs, :prompt_version, :string

    add_index :analysis_runs, :prompt_version
    add_index :analysis_runs, [ :pod_id, :created_at ]
  end
end
