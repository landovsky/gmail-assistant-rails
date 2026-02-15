require "rails_helper"

RSpec.describe "Api::Health", type: :request do
  describe "GET /api/health" do
    it "returns ok status" do
      get "/api/health"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq("status" => "ok")
    end
  end
end
