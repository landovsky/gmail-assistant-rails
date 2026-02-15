require "rails_helper"

RSpec.describe "Api::Watch", type: :request do
  describe "POST /api/watch" do
    it "registers watch for a specific user" do
      user = create(:user)
      post "/api/watch", params: { user_id: user.id }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["user_id"]).to eq(user.id)
      expect(body["watch_registered"]).to eq(true)
    end

    it "registers watch for all users" do
      create(:user)
      create(:user)

      post "/api/watch"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["results"].length).to eq(2)
    end

    it "returns 404 for unknown user" do
      post "/api/watch", params: { user_id: 999 }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/watch/status" do
    it "returns sync state for all users" do
      user = create(:user, email: "test@example.com")
      create(:sync_state, user: user, last_history_id: "42")

      get "/api/watch/status"
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["last_history_id"]).to eq("42")
      expect(body.first["email"]).to eq("test@example.com")
    end
  end
end
