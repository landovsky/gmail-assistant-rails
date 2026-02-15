class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.text :email, null: false
      t.text :display_name
      t.boolean :is_active, default: true
      t.datetime :onboarded_at
      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
