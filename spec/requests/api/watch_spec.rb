require "rails_helper"

RSpec.describe "Api::Watch", type: :request do
  describe "POST /api/watch" do
    let(:mock_client) { instance_double(Gmail::Client) }
    let(:mock_manager) { instance_double(Gmail::WatchManager) }
    let(:mock_watch_response) do
      double("WatchResponse", history_id: 12345, expiration: 1700000000000)
    end

    before do
      allow(AppConfig).to receive(:sync).and_return({ "pubsub_topic" => "projects/test/topics/gmail" })
      allow(Gmail::Client).to receive(:new).and_return(mock_client)
      allow(Gmail::WatchManager).to receive(:new).and_return(mock_manager)
      allow(mock_manager).to receive(:register_watch).and_return(mock_watch_response)
    end

    it "registers watch for a specific user" do
      user = create(:user)
      post "/api/watch", params: { user_id: user.id }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["user_id"]).to eq(user.id)
      expect(body["watch_registered"]).to eq(true)
      expect(mock_manager).to have_received(:register_watch).with(user)
    end

    it "registers watch for all users" do
      create(:user)
      create(:user)

      post "/api/watch"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["results"].length).to eq(2)
      expect(mock_manager).to have_received(:register_watch).twice
    end

    it "returns 404 for unknown user" do
      post "/api/watch", params: { user_id: 999 }
      expect(response).to have_http_status(:not_found)
    end

    it "returns 400 when no pubsub topic configured" do
      allow(AppConfig).to receive(:sync).and_return({ "pubsub_topic" => "" })

      post "/api/watch"
      expect(response).to have_http_status(:bad_request)
      body = JSON.parse(response.body)
      expect(body["detail"]).to include("Pub/Sub topic")
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
