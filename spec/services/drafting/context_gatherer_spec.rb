require "rails_helper"

RSpec.describe Drafting::ContextGatherer do
  subject(:gatherer) { described_class.new(llm_gateway: llm_gateway, gmail_client: gmail_client) }

  let(:llm_gateway) { instance_double(Llm::Gateway) }
  let(:gmail_client) { double("GmailClient") }

  let(:gather_params) do
    {
      sender_email: "john@example.com",
      subject: "Test",
      body: "Hello",
      gmail_thread_id: "thread_1"
    }
  end

  describe "#gather" do
    context "without gmail client" do
      let(:gmail_client) { nil }

      it "returns empty string" do
        result = described_class.new(llm_gateway: llm_gateway, gmail_client: nil).gather(**gather_params)
        expect(result).to eq("")
      end
    end

    context "fail-safe behavior" do
      it "returns empty string when LLM returns nil" do
        allow(llm_gateway).to receive(:context_query).and_return(nil)

        result = gatherer.gather(**gather_params)
        expect(result).to eq("")
      end

      it "returns empty string when LLM returns invalid JSON" do
        allow(llm_gateway).to receive(:context_query).and_return("not json at all")

        result = gatherer.gather(**gather_params)
        expect(result).to eq("")
      end

      it "returns empty string on search error" do
        allow(llm_gateway).to receive(:context_query).and_return('["from:john@example.com"]')
        allow(gmail_client).to receive(:search_threads).and_raise(StandardError.new("API error"))

        result = gatherer.gather(**gather_params)
        expect(result).to eq("")
      end

      it "returns empty string on any unexpected error" do
        allow(llm_gateway).to receive(:context_query).and_raise(StandardError.new("boom"))

        result = gatherer.gather(**gather_params)
        expect(result).to eq("")
      end
    end

    context "successful gathering" do
      before do
        allow(llm_gateway).to receive(:context_query).and_return('["from:john@example.com"]')
        allow(gmail_client).to receive(:search_threads).and_return([
          { thread_id: "thread_2" },
          { thread_id: "thread_3" }
        ])
        allow(gmail_client).to receive(:get_thread_data).with("thread_2").and_return({
          sender: "John <john@example.com>",
          subject: "Previous email",
          body: "Previous content"
        })
        allow(gmail_client).to receive(:get_thread_data).with("thread_3").and_return({
          sender: "John <john@example.com>",
          subject: "Another email",
          body: "Another content"
        })
      end

      it "formats related context block" do
        result = gatherer.gather(**gather_params)
        expect(result).to include("--- Related emails from your mailbox ---")
        expect(result).to include("--- End related emails ---")
        expect(result).to include("Previous email")
        expect(result).to include("Another email")
      end

      it "excludes the current thread" do
        allow(gmail_client).to receive(:search_threads).and_return([
          { thread_id: "thread_1" },
          { thread_id: "thread_2" }
        ])

        result = gatherer.gather(**gather_params)
        expect(result).to include("Previous email")
        expect(result).not_to include("thread_1")
      end
    end
  end
end
