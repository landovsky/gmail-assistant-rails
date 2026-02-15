class CreateLlmCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_calls do |t|
      t.references :user, foreign_key: true
      t.text :gmail_thread_id
      t.text :call_type, null: false
      t.text :model, null: false
      t.text :system_prompt
      t.text :user_message
      t.text :response_text
      t.integer :prompt_tokens, default: 0
      t.integer :completion_tokens, default: 0
      t.integer :total_tokens, default: 0
      t.integer :latency_ms, default: 0
      t.text :error
      t.datetime :created_at, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :llm_calls, :gmail_thread_id
    add_index :llm_calls, :call_type
    add_index :llm_calls, :created_at
  end
end
