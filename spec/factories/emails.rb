FactoryBot.define do
  factory :email do
    user
    sequence(:gmail_thread_id) { |n| "thread_#{n}" }
    sequence(:gmail_message_id) { |n| "msg_#{n}" }
    sender_email { "sender@example.com" }
    sender_name { "Sender" }
    subject { "Test Subject" }
    classification { "needs_response" }
    confidence { "high" }
    status { "pending" }
  end
end
