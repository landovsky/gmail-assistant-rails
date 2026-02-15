class CreateUserLabels < ActiveRecord::Migration[8.1]
  def change
    create_table :user_labels, id: false do |t|
      t.references :user, null: false, foreign_key: true
      t.text :label_key, null: false
      t.text :gmail_label_id, null: false
      t.text :gmail_label_name, null: false
    end
    add_index :user_labels, [:user_id, :label_key], unique: true
  end
end
