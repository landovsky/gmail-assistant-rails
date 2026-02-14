class CreateLlmCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_calls do |t|
      t.references :user, null: true, foreign_key: true, index: true
      t.text :gmail_thread_id, index: true
      t.text :call_type, null: false, index: true
      t.text :model, null: false
      t.text :system_prompt
      t.text :user_message
      t.text :response_text
      t.integer :prompt_tokens, default: 0
      t.integer :completion_tokens, default: 0
      t.integer :total_tokens, default: 0
      t.integer :latency_ms, default: 0
      t.text :error

      t.timestamps
    end

    add_index :llm_calls, :created_at

    # Add CHECK constraint
    execute <<-SQL
      ALTER TABLE llm_calls ADD CONSTRAINT check_call_type
      CHECK (call_type IN ('classify', 'draft', 'rework', 'context', 'agent'))
    SQL
  end
end
