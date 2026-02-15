FactoryBot.define do
  factory :job do
    user
    job_type { "classify" }
    payload { "{}" }
    status { "pending" }
  end
end
