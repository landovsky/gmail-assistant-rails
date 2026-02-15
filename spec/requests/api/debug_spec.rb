require "rails_helper"

RSpec.describe "Api::Debug", type: :request do
  let(:user) { create(:user) }

  describe "GET /api/emails/:email_id/debug" do
    it "returns full debug data" do
      email = create(:email, user: user, gmail_thread_id: "thread_dbg")
      create(:email_event, user: user, gmail_thread_id: "thread_dbg", event_type: "classified")
      create(:llm_call, user: user, gmail_thread_id: "thread_dbg")
      create(:agent_run, user: user, gmail_thread_id: "thread_dbg")

      get "/api/emails/#{email.id}/debug"
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body["email"]["id"]).to eq(email.id)
      expect(body["events"].length).to eq(1)
      expect(body["llm_calls"].length).to eq(1)
      expect(body["agent_runs"].length).to eq(1)
      expect(body["timeline"].length).to eq(3)
      expect(body["summary"]["event_count"]).to eq(1)
    end

    it "returns 404 for unknown email" do
      get "/api/emails/999/debug"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/debug/emails" do
    it "returns emails with debug counts" do
      email = create(:email, user: user, gmail_thread_id: "thread_list")
      create(:email_event, user: user, gmail_thread_id: "thread_list", event_type: "classified")

      get "/api/debug/emails"
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body["count"]).to eq(1)
      expect(body["emails"].first["event_count"]).to eq(1)
    end

    it "filters by status" do
      create(:email, user: user, status: "pending")
      create(:email, user: user, status: "drafted")

      get "/api/debug/emails", params: { status: "drafted" }
      body = JSON.parse(response.body)
      expect(body["count"]).to eq(1)
    end

    it "searches with q parameter" do
      create(:email, user: user, subject: "Important meeting")
      create(:email, user: user, subject: "Random stuff")

      get "/api/debug/emails", params: { q: "Important" }
      body = JSON.parse(response.body)
      expect(body["count"]).to eq(1)
    end

    it "respects limit parameter" do
      3.times { create(:email, user: user) }

      get "/api/debug/emails", params: { limit: 2 }
      body = JSON.parse(response.body)
      expect(body["emails"].length).to eq(2)
      expect(body["limit"]).to eq(2)
    end
  end

  describe "POST /api/emails/:email_id/reclassify" do
    it "enqueues a classify job with force" do
      email = create(:email, user: user)

      expect { post "/api/emails/#{email.id}/reclassify" }
        .to change(Job, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("queued")
      expect(body["email_id"]).to eq(email.id)

      job = Job.last
      expect(job.job_type).to eq("classify")
      expect(JSON.parse(job.payload)["force"]).to eq(true)
    end

    it "returns 404 for unknown email" do
      post "/api/emails/999/reclassify"
      expect(response).to have_http_status(:not_found)
    end
  end
end
