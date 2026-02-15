class CreateUserSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :user_settings, id: false do |t|
      t.references :user, null: false, foreign_key: true
      t.text :setting_key, null: false
      t.text :setting_value, null: false
    end
    add_index :user_settings, [:user_id, :setting_key], unique: true
  end
end
