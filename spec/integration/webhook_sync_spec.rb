require "rails_helper"
require "ostruct"

RSpec.describe "Webhook & Sync", type: :request do
  include GmailApiHelpers

  describe "TC-2.1: Valid Pub/Sub notification triggers sync" do
    it "enqueues sync job and processes history records into downstream jobs" do
      user = create(:user, email: "test@example.com")
      create(:sync_state, user: user, last_history_id: "11111")

      # POST webhook - should create a sync job
      payload = gmail_pubsub_payload(email: "test@example.com", history_id: 22222)
      post "/webhook/gmail", params: payload, as: :json

      expect(response).to have_http_status(:ok)

      sync_job = Job.find_by(user: user, job_type: "sync")
      expect(sync_job).to be_present
      expect(sync_job.parsed_payload["history_id"]).to eq(22222)

      # Now simulate what the worker would do: run Sync::Engine
      gmail_client = instance_double("GmailClient")

      history_response = OpenStruct.new(
        history: [
          OpenStruct.new(
            messages_added: [
              OpenStruct.new(message: OpenStruct.new(id: "msg1", thread_id: "t1", label_ids: ["INBOX"]))
            ],
            labels_added: nil,
            messages_deleted: nil
          )
        ],
        history_id: "33333",
        next_page_token: nil
      )

      allow(gmail_client).to receive(:list_history).and_return(history_response)

      # Routing now fetches full message for match rules
      from_header = OpenStruct.new(name: "From", value: "sender@example.com")
      subject_header = OpenStruct.new(name: "Subject", value: "Test")
      payload = OpenStruct.new(
        headers: [from_header, subject_header],
        mime_type: "text/plain",
        body: OpenStruct.new(data: nil),
        parts: nil
      )
      full_msg = OpenStruct.new(payload: payload, snippet: "")
      allow(gmail_client).to receive(:get_message).with("msg1").and_return(full_msg)

      allow(AppConfig).to receive(:routing).and_return({
        "rules" => [{ "name" => "default", "match" => { "all" => true }, "route" => "pipeline" }]
      })

      engine = Sync::Engine.new(user: user, gmail_client: gmail_client)
      engine.perform(history_id: "22222")

      # Downstream classify job should be created
      classify_jobs = Job.where(user: user, job_type: "classify")
      expect(classify_jobs.count).to eq(1)
      expect(JSON.parse(classify_jobs.first.payload)["thread_id"]).to eq("t1")

      # Sync state should be updated
      expect(user.sync_state.reload.last_history_id).to eq("33333")
    end
  end

  describe "TC-2.2: Webhook with unknown email is ignored gracefully" do
    it "returns 200 and does not enqueue jobs for unknown emails" do
      payload = gmail_pubsub_payload(email: "unknown@example.com", history_id: 12345)

      post "/webhook/gmail", params: payload, as: :json

      expect(response).to have_http_status(:ok)
      expect(Job.count).to eq(0)
    end
  end

  describe "TC-2.3: Malformed webhook payload returns 400" do
    it "rejects invalid JSON or missing message.data" do
      # Missing message.data entirely
      post "/webhook/gmail", params: { message: {} }, as: :json
      expect(response).to have_http_status(:bad_request)

      # Missing message key
      post "/webhook/gmail", params: { foo: "bar" }, as: :json
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "TC-2.4: Full sync triggered when no sync state exists" do
    it "performs full inbox scan and creates classify jobs" do
      user = create(:user, email: "test@example.com")
      # No sync_state created

      gmail_client = instance_double("GmailClient")

      messages_response = OpenStruct.new(
        messages: [
          OpenStruct.new(id: "msg1", thread_id: "t1"),
          OpenStruct.new(id: "msg2", thread_id: "t2")
        ]
      )

      allow(gmail_client).to receive(:list_messages).and_return(messages_response)
      allow(gmail_client).to receive(:get_message).with("msg1", format: "metadata")
        .and_return(OpenStruct.new(id: "msg1", thread_id: "t1", label_ids: ["INBOX"]))
      allow(gmail_client).to receive(:get_message).with("msg2", format: "metadata")
        .and_return(OpenStruct.new(id: "msg2", thread_id: "t2", label_ids: ["INBOX"]))
      allow(gmail_client).to receive(:get_profile)
        .and_return(OpenStruct.new(email_address: "test@example.com", history_id: "99999"))

      engine = Sync::Engine.new(user: user, gmail_client: gmail_client)
      engine.perform

      # Classify jobs created for each thread
      classify_jobs = Job.where(user: user, job_type: "classify")
      expect(classify_jobs.count).to eq(2)

      # Sync state created with current historyId
      expect(user.sync_state).to be_present
      expect(user.sync_state.last_history_id).to eq("99999")
    end
  end

  describe "TC-2.5: Full sync triggered when historyId is stale" do
    it "falls back to full sync when history API returns stale historyId error" do
      user = create(:user, email: "test@example.com")
      create(:sync_state, user: user, last_history_id: "100")

      gmail_client = instance_double("GmailClient")

      # History API raises stale historyId error
      allow(gmail_client).to receive(:list_history)
        .and_raise(Google::Apis::ClientError.new("Invalid historyId"))

      # Full sync fallback
      messages_response = OpenStruct.new(
        messages: [OpenStruct.new(id: "msg1", thread_id: "t1")]
      )
      allow(gmail_client).to receive(:list_messages).and_return(messages_response)
      allow(gmail_client).to receive(:get_message).with("msg1", format: "metadata")
        .and_return(OpenStruct.new(id: "msg1", thread_id: "t1", label_ids: ["INBOX"]))
      allow(gmail_client).to receive(:get_profile)
        .and_return(OpenStruct.new(email_address: "test@example.com", history_id: "55555"))

      engine = Sync::Engine.new(user: user, gmail_client: gmail_client)
      engine.perform(history_id: "100")

      # Full sync executed - classify job created
      expect(Job.where(user: user, job_type: "classify").count).to eq(1)

      # Sync state updated with new historyId
      expect(user.sync_state.reload.last_history_id).to eq("55555")
    end
  end

  describe "TC-2.6: Deduplication within a single sync" do
    it "enqueues only one classify job per thread despite multiple history entries" do
      user = create(:user, email: "test@example.com")
      create(:sync_state, user: user, last_history_id: "11111")

      gmail_client = instance_double("GmailClient")

      # 3 messages added for the same thread
      history_response = OpenStruct.new(
        history: [
          OpenStruct.new(
            messages_added: [
              OpenStruct.new(message: OpenStruct.new(id: "msg1", thread_id: "t1", label_ids: ["INBOX"])),
              OpenStruct.new(message: OpenStruct.new(id: "msg2", thread_id: "t1", label_ids: ["INBOX"])),
              OpenStruct.new(message: OpenStruct.new(id: "msg3", thread_id: "t1", label_ids: ["INBOX"]))
            ],
            labels_added: nil,
            messages_deleted: nil
          )
        ],
        history_id: "22222",
        next_page_token: nil
      )

      allow(gmail_client).to receive(:list_history).and_return(history_response)

      # Routing now fetches full message for match rules
      from_header = OpenStruct.new(name: "From", value: "sender@example.com")
      subject_header = OpenStruct.new(name: "Subject", value: "Test")
      payload = OpenStruct.new(
        headers: [from_header, subject_header],
        mime_type: "text/plain",
        body: OpenStruct.new(data: nil),
        parts: nil
      )
      full_msg = OpenStruct.new(payload: payload, snippet: "")
      allow(gmail_client).to receive(:get_message).with("msg1").and_return(full_msg)
      allow(gmail_client).to receive(:get_message).with("msg2").and_return(full_msg)
      allow(gmail_client).to receive(:get_message).with("msg3").and_return(full_msg)

      allow(AppConfig).to receive(:routing).and_return({
        "rules" => [{ "name" => "default", "match" => { "all" => true }, "route" => "pipeline" }]
      })

      engine = Sync::Engine.new(user: user, gmail_client: gmail_client)
      engine.perform(history_id: "11111")

      # Only 1 classify job despite 3 messages in same thread
      classify_jobs = Job.where(user: user, job_type: "classify")
      expect(classify_jobs.count).to eq(1)
      expect(JSON.parse(classify_jobs.first.payload)["thread_id"]).to eq("t1")
    end
  end
end
