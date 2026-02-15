require "rails_helper"

RSpec.describe "Api::Auth", type: :request do
  describe "POST /api/auth/init" do
    it "returns mock auth response" do
      post "/api/auth/init"
      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body["user_id"]).to eq(1)
      expect(body["onboarded"]).to eq(true)
    end
  end
end
