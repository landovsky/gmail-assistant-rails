require "rails_helper"

RSpec.describe Classification::ClassificationEngine do
  subject(:engine) do
    described_class.new(
      rule_engine: rule_engine,
      llm_classifier: llm_classifier,
      contacts_config: contacts_config
    )
  end

  let(:rule_engine) { instance_double(Classification::RuleEngine) }
  let(:llm_classifier) { instance_double(Classification::LlmClassifier) }
  let(:contacts_config) do
    {
      "style_overrides" => { "vip@example.com" => "casual" },
      "domain_overrides" => { "*.gov.cz" => "business" }
    }
  end

  let(:email_params) do
    {
      sender_name: "John",
      sender_email: "john@example.com",
      subject: "Test",
      body: "Hello",
      message_count: 1,
      headers: {}
    }
  end

  let(:llm_result) do
    {
      "category" => "needs_response",
      "confidence" => "high",
      "reasoning" => "Direct question",
      "detected_language" => "en",
      "resolved_style" => "casual"
    }
  end

  before do
    allow(rule_engine).to receive(:evaluate).and_return({ is_automated: false })
    allow(llm_classifier).to receive(:classify).and_return(llm_result)
  end

  describe "#classify" do
    it "returns LLM classification when rule engine says not automated" do
      result = engine.classify(**email_params)
      expect(result["category"]).to eq("needs_response")
    end

    context "safety net override" do
      it "overrides needs_response to fyi for automated emails" do
        allow(rule_engine).to receive(:evaluate).and_return({ is_automated: true })

        result = engine.classify(**email_params)
        expect(result["category"]).to eq("fyi")
        expect(result["reasoning"]).to include("Overridden")
      end

      it "does not override non-needs_response categories" do
        allow(rule_engine).to receive(:evaluate).and_return({ is_automated: true })
        allow(llm_classifier).to receive(:classify).and_return(llm_result.merge("category" => "fyi"))

        result = engine.classify(**email_params)
        expect(result["category"]).to eq("fyi")
      end
    end

    context "style resolution" do
      it "uses exact email match first" do
        result = engine.classify(**email_params.merge(sender_email: "vip@example.com"))
        expect(result["resolved_style"]).to eq("casual")
      end

      it "uses domain pattern match second" do
        result = engine.classify(**email_params.merge(sender_email: "user@praha.gov.cz"))
        expect(result["resolved_style"]).to eq("business")
      end

      it "uses LLM-determined style when no contact override matches" do
        result = engine.classify(**email_params)
        expect(result["resolved_style"]).to eq("casual")
      end

      it "falls back to business when LLM style is blank" do
        allow(llm_classifier).to receive(:classify).and_return(llm_result.merge("resolved_style" => ""))

        result = engine.classify(**email_params)
        expect(result["resolved_style"]).to eq("business")
      end
    end
  end
end
