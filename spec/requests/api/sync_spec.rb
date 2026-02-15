require "rails_helper"

RSpec.describe "Api::Sync", type: :request do
  describe "POST /api/sync" do
    let!(:user) { create(:user) }

    it "enqueues a sync job" do
      expect { post "/api/sync", params: { user_id: user.id } }
        .to change(Job, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["queued"]).to eq(true)
      expect(body["user_id"]).to eq(user.id)
      expect(body["full"]).to eq(false)
    end

    it "handles full sync by destroying sync state" do
      create(:sync_state, user: user)

      post "/api/sync", params: { user_id: user.id, full: true }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["full"]).to eq(true)
      expect(SyncState.where(user_id: user.id).count).to eq(0)
    end

    it "returns 404 for unknown user" do
      post "/api/sync", params: { user_id: 999 }
      expect(response).to have_http_status(:not_found)
    end
  end
end
