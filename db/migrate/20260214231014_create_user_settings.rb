class CreateUserSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :user_settings, primary_key: [:user_id, :setting_key] do |t|
      t.references :user, null: false, foreign_key: true, type: :integer
      t.text :setting_key, null: false
      t.text :setting_value, null: false
    end
  end
end
