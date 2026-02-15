FactoryBot.define do
  factory :llm_call do
    user
    call_type { "classify" }
    model { "gemini/gemini-2.0-flash" }
    gmail_thread_id { "thread_1" }
    total_tokens { 100 }
    latency_ms { 250 }
  end
end
