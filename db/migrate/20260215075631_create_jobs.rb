class CreateJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :jobs do |t|
      t.text :job_type, null: false
      t.references :user, null: false, foreign_key: true
      t.text :payload, default: "{}"
      t.text :status, default: "pending"
      t.integer :attempts, default: 0
      t.integer :max_attempts, default: 3
      t.text :error_message
      t.datetime :created_at, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :started_at
      t.datetime :completed_at
    end

    add_index :jobs, [:status, :created_at]
    add_index :jobs, [:user_id, :job_type]
  end
end
