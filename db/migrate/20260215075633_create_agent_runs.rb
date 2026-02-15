class CreateAgentRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_runs do |t|
      t.references :user, null: false, foreign_key: true
      t.text :gmail_thread_id, null: false
      t.text :profile, null: false
      t.text :status, null: false, default: "running"
      t.text :tool_calls_log, default: "[]"
      t.text :final_message
      t.integer :iterations, default: 0
      t.text :error
      t.datetime :created_at, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :completed_at
    end

    add_index :agent_runs, :gmail_thread_id
    add_index :agent_runs, :status
  end
end
