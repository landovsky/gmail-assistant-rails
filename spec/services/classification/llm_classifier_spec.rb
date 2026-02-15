require "rails_helper"

RSpec.describe Classification::LlmClassifier do
  subject(:classifier) { described_class.new(llm_gateway: llm_gateway, styles_config: styles_config) }

  let(:llm_gateway) { instance_double(Llm::Gateway) }
  let(:styles_config) do
    {
      "styles" => {
        "business" => { "rules" => ["Be professional"], "sign_off" => "Regards", "language" => "auto" },
        "casual" => { "rules" => ["Be friendly"], "sign_off" => "Cheers", "language" => "auto" }
      }
    }
  end

  let(:email_params) do
    {
      sender_name: "John Doe",
      sender_email: "john@example.com",
      subject: "Meeting tomorrow",
      body: "Can we meet tomorrow at 3pm?",
      message_count: 1
    }
  end

  describe "#classify" do
    context "valid JSON response" do
      it "parses a valid classification response" do
        allow(llm_gateway).to receive(:classify).and_return(
          '{"category": "needs_response", "confidence": "high", "reasoning": "Direct question", "detected_language": "en", "resolved_style": "business"}'
        )

        result = classifier.classify(**email_params)
        expect(result["category"]).to eq("needs_response")
        expect(result["confidence"]).to eq("high")
        expect(result["reasoning"]).to eq("Direct question")
        expect(result["detected_language"]).to eq("en")
        expect(result["resolved_style"]).to eq("business")
      end

      it "handles all valid categories" do
        %w[needs_response action_required payment_request fyi waiting].each do |category|
          allow(llm_gateway).to receive(:classify).and_return(
            "{\"category\": \"#{category}\", \"confidence\": \"high\", \"reasoning\": \"test\", \"detected_language\": \"en\", \"resolved_style\": \"business\"}"
          )

          result = classifier.classify(**email_params)
          expect(result["category"]).to eq(category)
        end
      end
    end

    context "invalid JSON response" do
      it "falls back to needs_response on unparseable JSON" do
        allow(llm_gateway).to receive(:classify).and_return("This is not JSON at all")

        result = classifier.classify(**email_params)
        expect(result["category"]).to eq("needs_response")
        expect(result["confidence"]).to eq("low")
      end
    end

    context "unknown category" do
      it "falls back to needs_response for unknown categories" do
        allow(llm_gateway).to receive(:classify).and_return(
          '{"category": "unknown_thing", "confidence": "high", "reasoning": "test"}'
        )

        result = classifier.classify(**email_params)
        expect(result["category"]).to eq("needs_response")
      end
    end

    context "API error (nil response)" do
      it "returns default result when LLM returns nil" do
        allow(llm_gateway).to receive(:classify).and_return(nil)

        result = classifier.classify(**email_params)
        expect(result["category"]).to eq("needs_response")
        expect(result["confidence"]).to eq("low")
        expect(result["resolved_style"]).to eq("business")
      end
    end

    context "missing fields in response" do
      it "fills in defaults for missing fields" do
        allow(llm_gateway).to receive(:classify).and_return(
          '{"category": "fyi"}'
        )

        result = classifier.classify(**email_params)
        expect(result["category"]).to eq("fyi")
        expect(result["confidence"]).to eq("medium")
        expect(result["resolved_style"]).to eq("business")
      end
    end

    context "body truncation" do
      it "truncates body to 2000 characters" do
        long_body = "x" * 5000
        allow(llm_gateway).to receive(:classify) do |msg, **_|
          # Verify the body in the message is truncated
          expect(msg.length).to be < 5100
          '{"category": "fyi", "confidence": "high", "reasoning": "test", "detected_language": "en", "resolved_style": "business"}'
        end

        classifier.classify(**email_params.merge(body: long_body))
      end
    end

    context "uses snippet when no body" do
      it "uses snippet as fallback" do
        allow(llm_gateway).to receive(:classify) do |msg, **_|
          expect(msg).to include("snippet text")
          '{"category": "fyi", "confidence": "high", "reasoning": "test", "detected_language": "en", "resolved_style": "business"}'
        end

        classifier.classify(**email_params.merge(body: nil, snippet: "snippet text"))
      end
    end
  end
end
