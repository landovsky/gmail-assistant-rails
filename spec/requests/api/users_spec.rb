require "rails_helper"

RSpec.describe "Api::Users", type: :request do
  describe "GET /api/users" do
    it "returns active users" do
      user = create(:user, email: "test@example.com", display_name: "Test")
      create(:user, is_active: false)

      get "/api/users"
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["email"]).to eq("test@example.com")
      expect(body.first["display_name"]).to eq("Test")
    end
  end

  describe "POST /api/users" do
    it "creates a new user" do
      post "/api/users", params: { email: "new@example.com", display_name: "New User" }, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["email"]).to eq("new@example.com")
      expect(body["id"]).to be_present
    end

    it "returns 409 for duplicate email" do
      create(:user, email: "existing@example.com")
      post "/api/users", params: { email: "existing@example.com" }, as: :json

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)["detail"]).to include("already exists")
    end
  end

  describe "GET /api/users/:user_id/settings" do
    it "returns user settings" do
      user = create(:user)
      create(:user_setting, user: user, setting_key: "contacts", setting_value: { foo: "bar" }.to_json)

      get "/api/users/#{user.id}/settings"
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body["contacts"]).to eq("foo" => "bar")
    end

    it "returns empty object when no settings" do
      user = create(:user)
      get "/api/users/#{user.id}/settings"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "returns 404 for unknown user" do
      get "/api/users/999/settings"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT /api/users/:user_id/settings" do
    it "creates a new setting" do
      user = create(:user)
      put "/api/users/#{user.id}/settings",
          params: { key: "theme", value: "dark" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["ok"]).to eq(true)
      expect(user.user_settings.find_by(setting_key: "theme").setting_value).to eq("dark")
    end

    it "updates an existing setting" do
      user = create(:user)
      create(:user_setting, user: user, setting_key: "theme", setting_value: "light")

      put "/api/users/#{user.id}/settings",
          params: { key: "theme", value: "dark" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.user_settings.find_by(setting_key: "theme").setting_value).to eq("dark")
    end
  end

  describe "GET /api/users/:user_id/labels" do
    it "returns label mappings" do
      user = create(:user)
      create(:user_label, user: user, label_key: "needs_response", gmail_label_id: "Label_abc")

      get "/api/users/#{user.id}/labels"
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body["needs_response"]).to eq("Label_abc")
    end
  end

  describe "GET /api/users/:user_id/emails" do
    let(:user) { create(:user) }

    it "defaults to pending emails" do
      create(:email, user: user, status: "pending")
      create(:email, user: user, status: "drafted")

      get "/api/users/#{user.id}/emails"
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["status"]).to eq("pending")
    end

    it "filters by status" do
      create(:email, user: user, status: "drafted")
      create(:email, user: user, status: "pending")

      get "/api/users/#{user.id}/emails", params: { status: "drafted" }
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["status"]).to eq("drafted")
    end

    it "filters by classification" do
      create(:email, user: user, classification: "fyi", status: "pending")
      create(:email, user: user, classification: "needs_response", status: "pending")

      get "/api/users/#{user.id}/emails", params: { classification: "fyi" }
      body = JSON.parse(response.body)
      expect(body.length).to eq(1)
      expect(body.first["classification"]).to eq("fyi")
    end
  end
end
