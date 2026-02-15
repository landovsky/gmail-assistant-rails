FactoryBot.define do
  factory :sync_state do
    user
    last_history_id { "12345" }
    last_sync_at { Time.current }
  end
end
