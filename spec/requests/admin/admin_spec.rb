require "rails_helper"

RSpec.describe "Admin endpoints", type: :request do
  let(:user) { create(:user, email: "admin-test@example.com") }

  describe "GET /admin/users" do
    it "returns paginated users" do
      create_list(:user, 3)
      get "/admin/users"
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body["total"]).to eq(3)
      expect(body["records"].length).to eq(3)
    end

    it "supports search" do
      create(:user, email: "alice@example.com")
      create(:user, email: "bob@example.com")

      get "/admin/users", params: { q: "alice" }
      body = JSON.parse(response.body)
      expect(body["total"]).to eq(1)
    end

    it "supports pagination" do
      create_list(:user, 5)
      get "/admin/users", params: { limit: 2, offset: 1 }
      body = JSON.parse(response.body)
      expect(body["records"].length).to eq(2)
      expect(body["offset"]).to eq(1)
    end
  end

  describe "GET /admin/users/:id" do
    it "returns a single user" do
      get "/admin/users/#{user.id}"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["email"]).to eq("admin-test@example.com")
    end

    it "returns 404 for non-existent user" do
      get "/admin/users/999999"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /admin/emails" do
    it "returns emails with filtering" do
      create(:email, user: user, status: "pending")
      create(:email, user: user, status: "drafted")

      get "/admin/emails", params: { status: "drafted" }
      body = JSON.parse(response.body)
      expect(body["total"]).to eq(1)
    end
  end

  describe "GET /admin/emails/:id" do
    it "returns a single email" do
      email = create(:email, user: user)
      get "/admin/emails/#{email.id}"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(email.id)
    end
  end

  describe "GET /admin/email_events" do
    it "returns email events" do
      create(:email_event, user: user)
      get "/admin/email_events"
      body = JSON.parse(response.body)
      expect(body["total"]).to eq(1)
    end
  end

  describe "GET /admin/llm_calls" do
    it "returns llm calls" do
      create(:llm_call, user: user)
      get "/admin/llm_calls"
      body = JSON.parse(response.body)
      expect(body["total"]).to eq(1)
    end
  end

  describe "GET /admin/jobs" do
    it "returns jobs" do
      create(:job, user: user)
      get "/admin/jobs"
      body = JSON.parse(response.body)
      expect(body["total"]).to eq(1)
    end
  end

  describe "GET /admin/jobs/:id" do
    it "returns a single job" do
      job = create(:job, user: user)
      get "/admin/jobs/#{job.id}"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(job.id)
    end
  end

  describe "GET /admin/llm_calls/:id" do
    it "returns a single llm call" do
      llm_call = create(:llm_call, user: user)
      get "/admin/llm_calls/#{llm_call.id}"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(llm_call.id)
    end
  end

  describe "GET /admin/user_labels" do
    it "returns user labels" do
      create(:user_label, user: user)
      get "/admin/user_labels"
      body = JSON.parse(response.body)
      expect(body["total"]).to eq(1)
    end
  end

  describe "GET /admin/user_settings" do
    it "returns user settings" do
      create(:user_setting, user: user)
      get "/admin/user_settings"
      body = JSON.parse(response.body)
      expect(body["total"]).to eq(1)
    end
  end

  describe "GET /admin/sync_states" do
    it "returns sync states" do
      create(:sync_state, user: user)
      get "/admin/sync_states"
      body = JSON.parse(response.body)
      expect(body["total"]).to eq(1)
    end
  end
end
