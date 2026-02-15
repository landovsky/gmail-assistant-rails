class CreateEmailEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :email_events do |t|
      t.references :user, null: false, foreign_key: true
      t.text :gmail_thread_id, null: false
      t.text :event_type, null: false
      t.text :detail
      t.text :label_id
      t.text :draft_id
      t.datetime :created_at, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :email_events, [:user_id, :gmail_thread_id]
    add_index :email_events, :event_type
  end
end
