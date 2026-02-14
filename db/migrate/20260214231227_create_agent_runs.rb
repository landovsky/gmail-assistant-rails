class CreateAgentRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_runs do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.text :gmail_thread_id, null: false, index: true
      t.text :profile, null: false
      t.text :status, null: false, default: 'running', index: true
      t.text :tool_calls_log, default: '[]'
      t.text :final_message
      t.integer :iterations, default: 0
      t.text :error
      t.datetime :completed_at

      t.timestamps
    end

    # Add CHECK constraint
    execute <<-SQL
      ALTER TABLE agent_runs ADD CONSTRAINT check_status
      CHECK (status IN ('running', 'completed', 'error', 'max_iterations'))
    SQL
  end
end
