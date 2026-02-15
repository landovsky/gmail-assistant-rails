require "rails_helper"

RSpec.describe Sync::Engine do
  let(:user) { create(:user, :onboarded) }
  let(:gmail_client) { instance_double(Gmail::Client) }
  let(:engine) { described_class.new(user: user, gmail_client: gmail_client) }

  before do
    allow(AppConfig).to receive(:sync).and_return({
      "full_sync_days" => 10,
      "history_max_results" => 100,
      "pubsub_topic" => "projects/test/topics/gmail"
    })
    allow(AppConfig).to receive(:routing).and_return({
      "rules" => [{ "name" => "default", "match" => { "all" => true }, "route" => "pipeline" }]
    })
  end

  describe "#perform with incremental sync" do
    let!(:sync_state) { create(:sync_state, user: user, last_history_id: "1000") }

    # Helper to build a full message mock for routing
    def stub_full_message(msg_id, sender: "sender@example.com", subject: "Test")
      from_header = double(name: "From", value: "#{sender}")
      subject_header = double(name: "Subject", value: subject)
      payload = double(
        headers: [from_header, subject_header],
        mime_type: "text/plain",
        body: double(data: nil),
        parts: nil
      )
      full_msg = double(payload: payload, snippet: "")
      allow(gmail_client).to receive(:get_message).with(msg_id).and_return(full_msg)
    end

    it "processes messagesAdded and creates classify jobs" do
      message = double(
        id: "msg_1",
        thread_id: "thread_1",
        label_ids: ["INBOX"]
      )
      messages_added = [double(message: message)]
      history_record = double(
        messages_added: messages_added,
        labels_added: nil,
        messages_deleted: nil
      )
      response = double(
        history: [history_record],
        history_id: "1100",
        next_page_token: nil
      )

      allow(gmail_client).to receive(:list_history).and_return(response)
      stub_full_message("msg_1")

      expect { engine.perform }.to change(Job, :count).by(1)

      job = Job.last
      expect(job.job_type).to eq("classify")
      expect(job.user).to eq(user)
      payload = JSON.parse(job.payload)
      expect(payload["thread_id"]).to eq("thread_1")
      expect(payload["message_id"]).to eq("msg_1")
    end

    it "deduplicates jobs by job_type and thread_id" do
      msg1 = double(id: "msg_1", thread_id: "thread_1", label_ids: ["INBOX"])
      msg2 = double(id: "msg_2", thread_id: "thread_1", label_ids: ["INBOX"])
      messages_added = [double(message: msg1), double(message: msg2)]
      history_record = double(
        messages_added: messages_added,
        labels_added: nil,
        messages_deleted: nil
      )
      response = double(
        history: [history_record],
        history_id: "1100",
        next_page_token: nil
      )

      allow(gmail_client).to receive(:list_history).and_return(response)
      stub_full_message("msg_1")
      stub_full_message("msg_2")

      expect { engine.perform }.to change(Job, :count).by(1)
    end

    it "skips non-INBOX messages" do
      message = double(id: "msg_1", thread_id: "thread_1", label_ids: ["SENT"])
      messages_added = [double(message: message)]
      history_record = double(
        messages_added: messages_added,
        labels_added: nil,
        messages_deleted: nil
      )
      response = double(
        history: [history_record],
        history_id: "1100",
        next_page_token: nil
      )

      allow(gmail_client).to receive(:list_history).and_return(response)

      expect { engine.perform }.not_to change(Job, :count)
    end

    it "updates sync state after successful sync" do
      response = double(history: nil, history_id: "1100", next_page_token: nil)
      allow(gmail_client).to receive(:list_history).and_return(response)

      engine.perform

      sync_state.reload
      expect(sync_state.last_history_id).to eq("1100")
    end

    it "processes labelsAdded for done label" do
      label = create(:user_label, user: user, label_key: "done", gmail_label_id: "Label_done", gmail_label_name: "Done")
      message = double(id: "msg_1", thread_id: "thread_1")
      label_change = double(message: message, label_ids: ["Label_done"])
      history_record = double(
        messages_added: nil,
        labels_added: [label_change],
        messages_deleted: nil
      )
      response = double(history: [history_record], history_id: "1100", next_page_token: nil)
      allow(gmail_client).to receive(:list_history).and_return(response)

      expect { engine.perform }.to change(Job, :count).by(1)
      job = Job.last
      expect(job.job_type).to eq("cleanup")
      expect(JSON.parse(job.payload)["action"]).to eq("done")
    end

    it "processes labelsAdded for rework label" do
      create(:user_label, user: user, label_key: "rework", gmail_label_id: "Label_rework", gmail_label_name: "Rework")
      message = double(id: "msg_1", thread_id: "thread_1")
      label_change = double(message: message, label_ids: ["Label_rework"])
      history_record = double(
        messages_added: nil,
        labels_added: [label_change],
        messages_deleted: nil
      )
      response = double(history: [history_record], history_id: "1100", next_page_token: nil)
      allow(gmail_client).to receive(:list_history).and_return(response)

      expect { engine.perform }.to change(Job, :count).by(1)
      expect(Job.last.job_type).to eq("rework")
    end

    it "processes messagesDeleted and creates cleanup jobs" do
      message = double(id: "msg_1", thread_id: "thread_1")
      messages_deleted = [double(message: message)]
      history_record = double(
        messages_added: nil,
        labels_added: nil,
        messages_deleted: messages_deleted
      )
      response = double(history: [history_record], history_id: "1100", next_page_token: nil)
      allow(gmail_client).to receive(:list_history).and_return(response)

      expect { engine.perform }.to change(Job, :count).by(1)
      job = Job.last
      expect(job.job_type).to eq("cleanup")
      expect(JSON.parse(job.payload)["action"]).to eq("check_sent")
    end

    it "falls back to full sync on stale history ID" do
      error = Google::Apis::ClientError.new("historyId is no longer valid")
      allow(gmail_client).to receive(:list_history).and_raise(error)

      # Full sync needs these
      allow(gmail_client).to receive(:list_messages).and_return(double(messages: nil))
      allow(gmail_client).to receive(:get_profile).and_return(double(history_id: "2000"))

      engine.perform

      sync_state.reload
      expect(sync_state.last_history_id).to eq("2000")
    end
  end

  describe "#perform with full sync" do
    it "runs full sync when no sync state exists" do
      msg = double(id: "msg_1")
      message_detail = double(thread_id: "thread_1")
      allow(gmail_client).to receive(:list_messages).and_return(double(messages: [msg]))
      allow(gmail_client).to receive(:get_message).with("msg_1", format: "metadata").and_return(message_detail)
      allow(gmail_client).to receive(:get_profile).and_return(double(history_id: "5000"))

      expect { engine.perform }.to change(Job, :count).by(1)

      job = Job.last
      expect(job.job_type).to eq("classify")
      expect(user.sync_state.last_history_id).to eq("5000")
    end

    it "runs full sync when force_full is true" do
      create(:sync_state, user: user, last_history_id: "1000")

      allow(gmail_client).to receive(:list_messages).and_return(double(messages: nil))
      allow(gmail_client).to receive(:get_profile).and_return(double(history_id: "5000"))

      engine.perform(force_full: true)

      expect(user.sync_state.reload.last_history_id).to eq("5000")
    end

    it "skips threads already in database" do
      msg = double(id: "msg_1")
      message_detail = double(thread_id: "thread_1")
      allow(gmail_client).to receive(:list_messages).and_return(double(messages: [msg]))
      allow(gmail_client).to receive(:get_message).with("msg_1", format: "metadata").and_return(message_detail)
      allow(gmail_client).to receive(:get_profile).and_return(double(history_id: "5000"))

      create(:email, user: user, gmail_thread_id: "thread_1")

      expect { engine.perform }.not_to change(Job, :count)
    end

    it "skips threads with pending classify jobs" do
      msg = double(id: "msg_1")
      message_detail = double(thread_id: "thread_1")
      allow(gmail_client).to receive(:list_messages).and_return(double(messages: [msg]))
      allow(gmail_client).to receive(:get_message).with("msg_1", format: "metadata").and_return(message_detail)
      allow(gmail_client).to receive(:get_profile).and_return(double(history_id: "5000"))

      create(:job, user: user, job_type: "classify", payload: { thread_id: "thread_1" }.to_json)

      expect { engine.perform }.not_to change { Job.where(job_type: "classify").count }
    end

    it "deduplicates threads from multiple messages" do
      msg1 = double(id: "msg_1")
      msg2 = double(id: "msg_2")
      allow(gmail_client).to receive(:list_messages).and_return(double(messages: [msg1, msg2]))
      allow(gmail_client).to receive(:get_message).with("msg_1", format: "metadata").and_return(double(thread_id: "thread_1"))
      allow(gmail_client).to receive(:get_message).with("msg_2", format: "metadata").and_return(double(thread_id: "thread_1"))
      allow(gmail_client).to receive(:get_profile).and_return(double(history_id: "5000"))

      expect { engine.perform }.to change(Job, :count).by(1)
    end
  end
end
