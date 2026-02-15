require "rails_helper"

RSpec.describe "Api::Briefing", type: :request do
  describe "GET /api/briefing/:user_email" do
    let!(:user) { create(:user, email: "test@example.com") }

    it "returns categorized summary" do
      create(:email, user: user, classification: "needs_response", status: "pending")
      create(:email, user: user, classification: "needs_response", status: "sent")
      create(:email, user: user, classification: "fyi", status: "pending")
      create(:email, user: user, classification: "action_required", status: "pending")

      get "/api/briefing/test@example.com"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)

      expect(body["user"]).to eq("test@example.com")
      expect(body["summary"]["needs_response"]["total"]).to eq(2)
      expect(body["summary"]["needs_response"]["active"]).to eq(1)
      expect(body["summary"]["fyi"]["total"]).to eq(1)
      expect(body["pending_drafts"]).to eq(1)
      expect(body["action_items"].length).to eq(2)
    end

    it "returns 404 for unknown user" do
      get "/api/briefing/unknown@example.com"
      expect(response).to have_http_status(:not_found)
    end
  end
end
