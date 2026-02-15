require "rails_helper"

RSpec.describe "Api::Auth", type: :request do
  describe "POST /api/auth/init" do
    let(:mock_client) { instance_double(Gmail::Client) }
    let(:mock_profile) do
      double("Profile", email_address: "test@gmail.com", history_id: 12345)
    end
    let(:mock_labels_response) do
      double("Labels", labels: [])
    end
    let(:mock_created_label) do
      double("Label", id: "Label_new123", name: "test")
    end

    before do
      allow(Gmail::Client).to receive(:new).and_return(mock_client)
      allow(mock_client).to receive(:get_profile).and_return(mock_profile)
      allow(mock_client).to receive(:list_labels).and_return(mock_labels_response)
      allow(mock_client).to receive(:create_label).and_return(mock_created_label)
    end

    it "creates a user and provisions labels" do
      post "/api/auth/init", params: { display_name: "Test User" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["email"]).to eq("test@gmail.com")
      expect(body["onboarded"]).to eq(true)
      expect(body["user_id"]).to be_present

      user = User.find_by(email: "test@gmail.com")
      expect(user).to be_present
      expect(user.display_name).to eq("Test User")
      expect(user.onboarded_at).to be_present
      expect(user.user_labels.count).to eq(UserLabel::STANDARD_NAMES.count)
      expect(user.sync_state).to be_present
      expect(user.sync_state.last_history_id).to eq("12345")
    end

    it "imports communication_styles and contacts settings" do
      post "/api/auth/init"

      expect(response).to have_http_status(:ok)
      user = User.find_by(email: "test@gmail.com")
      expect(user.user_settings.find_by(setting_key: "communication_styles")).to be_present
      expect(user.user_settings.find_by(setting_key: "contacts")).to be_present
    end

    it "is idempotent for existing users" do
      create(:user, email: "test@gmail.com", display_name: "Old Name")

      post "/api/auth/init", params: { display_name: "New Name" }

      expect(response).to have_http_status(:ok)
      expect(User.where(email: "test@gmail.com").count).to eq(1)
      expect(User.find_by(email: "test@gmail.com").display_name).to eq("New Name")
    end

    it "returns 400 when OAuth credentials fail" do
      allow(Gmail::Client).to receive(:new).and_raise(StandardError, "credentials not found")

      post "/api/auth/init"

      expect(response).to have_http_status(:bad_request)
      body = JSON.parse(response.body)
      expect(body["detail"]).to include("credentials")
    end

    it "returns 500 when email cannot be retrieved" do
      allow(mock_profile).to receive(:email_address).and_return(nil)

      post "/api/auth/init"

      expect(response).to have_http_status(:internal_server_error)
      body = JSON.parse(response.body)
      expect(body["detail"]).to include("Cannot retrieve email")
    end

    it "migrates v1 labels when label_ids.yml exists" do
      # Create a temporary label_ids.yml
      label_ids_path = Rails.root.join("config", "label_ids.yml")
      File.write(label_ids_path, { "needs_response" => "Label_legacy_123" }.to_yaml)

      post "/api/auth/init", params: { migrate_v1: true }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["migrated_v1"]).to eq(true)

      user = User.find_by(email: "test@gmail.com")
      label = user.user_labels.find_by(label_key: "needs_response")
      expect(label.gmail_label_id).to eq("Label_legacy_123")
    ensure
      File.delete(label_ids_path) if File.exist?(label_ids_path)
    end

    it "skips v1 migration when migrate_v1 is false" do
      post "/api/auth/init", params: { migrate_v1: false }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["migrated_v1"]).to eq(false)
    end
  end
end
