FactoryBot.define do
  factory :user_label do
    user
    label_key { "needs_response" }
    gmail_label_id { "Label_abc123" }
    gmail_label_name { "AI/Needs Response" }
  end
end
