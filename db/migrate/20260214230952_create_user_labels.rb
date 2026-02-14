class CreateUserLabels < ActiveRecord::Migration[8.1]
  def change
    create_table :user_labels, primary_key: [:user_id, :label_key] do |t|
      t.references :user, null: false, foreign_key: true, type: :integer
      t.text :label_key, null: false
      t.text :gmail_label_id, null: false
      t.text :gmail_label_name, null: false
    end
  end
end
