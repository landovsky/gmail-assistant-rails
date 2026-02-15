FactoryBot.define do
  factory :user_setting do
    user
    setting_key { "communication_styles" }
    setting_value { { business: { rules: [] } }.to_json }
  end
end
