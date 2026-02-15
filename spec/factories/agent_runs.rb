FactoryBot.define do
  factory :agent_run do
    user
    sequence(:gmail_thread_id) { |n| "thread_#{n}" }
    profile { "pharmacy" }
    status { "completed" }
    iterations { 2 }
  end
end
