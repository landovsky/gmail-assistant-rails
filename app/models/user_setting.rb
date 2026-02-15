class UserSetting < ApplicationRecord
  belongs_to :user

  validates :setting_key, presence: true
  validates :setting_value, presence: true

  def parsed_value
    JSON.parse(setting_value)
  rescue JSON::ParserError
    setting_value
  end

  def value=(val)
    self.setting_value = val.is_a?(String) ? val : val.to_json
  end
end
