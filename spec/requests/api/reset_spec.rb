require "rails_helper"

RSpec.describe "Api::Reset", type: :request do
  describe "POST /api/reset" do
    it "clears transient data and preserves users" do
      user = create(:user)
      create(:job, user: user)
      create(:email, user: user)
      create(:email_event, user: user)
      create(:sync_state, user: user)

      post "/api/reset"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["deleted"]["jobs"]).to eq(1)
      expect(body["deleted"]["emails"]).to eq(1)
      expect(body["deleted"]["email_events"]).to eq(1)
      expect(body["deleted"]["sync_state"]).to eq(1)
      expect(body["total"]).to eq(4)

      expect(User.count).to eq(1)
    end
  end
end
