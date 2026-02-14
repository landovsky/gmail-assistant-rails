class CreateEmailEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :email_events do |t|
      t.references :user, null: false, foreign_key: true
      t.text :gmail_thread_id, null: false
      t.text :event_type, null: false
      t.text :detail
      t.text :label_id
      t.text :draft_id

      t.timestamps
    end

    add_index :email_events, [:user_id, :gmail_thread_id]
    add_index :email_events, :event_type

    # Add CHECK constraint
    execute <<-SQL
      ALTER TABLE email_events ADD CONSTRAINT check_event_type
      CHECK (event_type IN ('classified', 'label_added', 'label_removed', 'draft_created', 'draft_trashed', 'draft_reworked', 'sent_detected', 'archived', 'rework_limit_reached', 'waiting_retriaged', 'error'))
    SQL
  end
end
