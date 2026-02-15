FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    display_name { "Test User" }
    is_active { true }

    trait :onboarded do
      onboarded_at { Time.current }
    end
  end
end
