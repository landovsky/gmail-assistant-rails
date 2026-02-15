require "rails_helper"

RSpec.describe "Webhook::Gmail", type: :request do
  let!(:user) { create(:user, email: "user@example.com") }

  def encode_data(data)
    Base64.encode64(data.to_json)
  end

  describe "POST /webhook/gmail" do
    context "with valid notification" do
      let(:params) do
        {
          message: {
            data: encode_data({ emailAddress: "user@example.com", historyId: 12345 }),
            messageId: "msg-1",
            publishTime: "2026-02-15T10:00:00Z"
          },
          subscription: "projects/test/subscriptions/gmail-push"
        }
      end

      it "enqueues a sync job and returns 200" do
        expect { post "/webhook/gmail", params: params, as: :json }
          .to change(Job, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["status"]).to eq("processed")

        job = Job.last
        expect(job.job_type).to eq("sync")
        expect(job.user_id).to eq(user.id)
        expect(JSON.parse(job.payload)["history_id"]).to eq(12345)
      end
    end

    context "with unknown email address" do
      let(:params) do
        {
          message: {
            data: encode_data({ emailAddress: "unknown@example.com", historyId: 999 })
          }
        }
      end

      it "returns 200 and ignores" do
        expect { post "/webhook/gmail", params: params, as: :json }
          .not_to change(Job, :count)

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["status"]).to eq("ignored")
      end
    end

    context "with malformed data" do
      it "returns 400 for missing message" do
        post "/webhook/gmail", params: {}, as: :json
        expect(response).to have_http_status(:bad_request)
      end

      it "returns 400 for invalid base64/json" do
        post "/webhook/gmail", params: { message: { data: "!!!invalid!!!" } }, as: :json
        expect(response).to have_http_status(:bad_request)
      end

      it "returns 400 for missing emailAddress" do
        post "/webhook/gmail", params: {
          message: { data: encode_data({ historyId: 123 }) }
        }, as: :json
        expect(response).to have_http_status(:bad_request)
      end
    end
  end
end
