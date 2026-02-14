class UserSetting < ApplicationRecord
  self.primary_key = [:user_id, :setting_key]

  # Associations
  belongs_to :user

  # Validations
  validates :setting_key, presence: true
  validates :setting_value, presence: true
end
