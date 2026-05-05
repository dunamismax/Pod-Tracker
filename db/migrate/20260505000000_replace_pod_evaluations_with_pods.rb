class ReplacePodEvaluationsWithPods < ActiveRecord::Migration[8.1]
  def up
    drop_table :pod_evaluations, if_exists: true

    create_table :pods do |t|
      t.references :user, foreign_key: true, index: true
      t.string :name, null: false
      t.string :format, null: false, default: "commander"
      t.string :status, null: false, default: "draft"
      t.string :share_token
      t.datetime :shared_at
      t.datetime :share_revoked_at
      t.text :notes
      t.timestamps
    end

    add_index :pods, :share_token, unique: true, where: "share_token IS NOT NULL"
    add_index :pods, [ :user_id, :updated_at ]

    create_table :pod_slots do |t|
      t.references :pod, null: false, foreign_key: true, index: true
      t.references :deck, null: false, foreign_key: true, index: true
      t.integer :position, null: false
      t.string :label
      t.timestamps
    end

    add_index :pod_slots, [ :pod_id, :position ], unique: true

    create_table :pod_analysis_runs do |t|
      t.references :pod, null: false, foreign_key: true, index: true
      t.references :user, foreign_key: true, index: true
      t.string :status, null: false, default: "queued"
      t.string :rubric_version, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.jsonb :rule_zero_brief, null: false, default: {}
      t.jsonb :warnings, null: false, default: []
      t.jsonb :suggestions, null: false, default: []
      t.datetime :queued_at, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.string :error_code
      t.text :error_message
      t.timestamps
    end

    add_index :pod_analysis_runs, [ :pod_id, :created_at ]
    add_index :pod_analysis_runs, :status
  end

  def down
    drop_table :pod_analysis_runs, if_exists: true
    drop_table :pod_slots, if_exists: true
    drop_table :pods, if_exists: true

    create_table :pod_evaluations do |t|
      t.references :user, foreign_key: true, index: true
      t.string :name, null: false
      t.string :status, null: false, default: "draft"
      t.integer :deck_count, null: false, default: 0
      t.jsonb :deck_snapshot, null: false, default: []
      t.jsonb :score_snapshot, null: false, default: {}
      t.jsonb :mismatch_warnings, null: false, default: []
      t.string :rubric_version
      t.datetime :evaluated_at
      t.timestamps
    end

    add_index :pod_evaluations, :status
    add_index :pod_evaluations, :rubric_version
    add_index :pod_evaluations, [ :user_id, :updated_at ]
  end
end
