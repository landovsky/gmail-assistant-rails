class CreateEmails < ActiveRecord::Migration[8.1]
  CLASSIFICATIONS = %w[needs_response action_required payment_request fyi waiting].freeze
  CONFIDENCES = %w[high medium low].freeze
  STATUSES = %w[pending drafted rework_requested sent skipped archived].freeze

  def change
    create_table :emails do |t|
      t.references :user, null: false, foreign_key: true
      t.text :gmail_thread_id, null: false
      t.text :gmail_message_id, null: false
      t.text :sender_email, null: false
      t.text :sender_name
      t.text :subject
      t.text :snippet
      t.datetime :received_at
      t.text :classification, null: false
      t.text :confidence, default: "medium"
      t.text :reasoning
      t.text :detected_language, default: "cs"
      t.text :resolved_style, default: "business"
      t.integer :message_count, default: 1
      t.text :status, default: "pending"
      t.text :draft_id
      t.integer :rework_count, default: 0
      t.text :last_rework_instruction
      t.text :vendor_name
      t.datetime :processed_at, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :drafted_at
      t.datetime :acted_at
      t.timestamps
    end

    add_index :emails, [:user_id, :classification]
    add_index :emails, [:user_id, :status]
    add_index :emails, :gmail_thread_id
    add_index :emails, [:user_id, :gmail_thread_id], unique: true
  end
end
