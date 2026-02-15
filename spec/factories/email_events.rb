FactoryBot.define do
  factory :email_event do
    user
    sequence(:gmail_thread_id) { |n| "thread_#{n}" }
    event_type { "classified" }
    detail { "Classification: needs_response" }
  end
end
