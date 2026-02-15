require "rails_helper"

RSpec.describe Drafting::DraftGenerator do
  subject(:generator) { described_class.new(llm_gateway: llm_gateway, styles_config: styles_config) }

  let(:llm_gateway) { instance_double(Llm::Gateway) }
  let(:styles_config) do
    {
      "styles" => {
        "business" => {
          "rules" => ["Be professional", "Use formal address"],
          "sign_off" => "Best regards",
          "language" => "auto",
          "examples" => []
        },
        "casual" => {
          "rules" => ["Be friendly"],
          "sign_off" => "Cheers",
          "language" => "auto",
          "examples" => [
            { "context" => "Friend email", "input" => "Hey!", "draft" => "Hey there!" }
          ]
        }
      }
    }
  end

  let(:draft_params) do
    {
      sender_name: "John Doe",
      sender_email: "john@example.com",
      subject: "Test Subject",
      thread_body: "Hey, can you help?",
      resolved_style: "business"
    }
  end

  describe "#generate" do
    context "happy path" do
      it "returns draft wrapped with scissors marker" do
        allow(llm_gateway).to receive(:draft).and_return("Thank you for your email. I'd be happy to help.")

        result = generator.generate(**draft_params)

        expect(result).to start_with("\n\n\u2702\uFE0F\n\n")
        expect(result).to include("Thank you for your email")
      end

      it "builds system prompt with style rules" do
        allow(llm_gateway).to receive(:draft) do |_msg, system_prompt:|
          expect(system_prompt).to include("professional")
          expect(system_prompt).to include("Best regards")
          "Draft text"
        end

        generator.generate(**draft_params)
      end

      it "includes user instructions when provided" do
        allow(llm_gateway).to receive(:draft) do |msg, **_|
          expect(msg).to include("Make it shorter")
          expect(msg).to include("--- User instructions ---")
          "Short draft"
        end

        generator.generate(**draft_params.merge(user_instructions: "Make it shorter"))
      end

      it "includes related context when provided" do
        allow(llm_gateway).to receive(:draft) do |msg, **_|
          expect(msg).to include("Related emails")
          "Draft with context"
        end

        generator.generate(**draft_params.merge(related_context: "--- Related emails from your mailbox ---\n1. test"))
      end

      it "includes examples in system prompt for casual style" do
        allow(llm_gateway).to receive(:draft) do |_msg, system_prompt:|
          expect(system_prompt).to include("Friend email")
          expect(system_prompt).to include("Hey there!")
          "Casual draft"
        end

        generator.generate(**draft_params.merge(resolved_style: "casual"))
      end
    end

    context "LLM error" do
      it "returns error message when LLM returns nil" do
        allow(llm_gateway).to receive(:draft).and_return(nil)

        result = generator.generate(**draft_params)
        expect(result).to include("[ERROR: Draft generation failed")
      end

      it "returns error message when LLM raises" do
        allow(llm_gateway).to receive(:draft).and_raise(StandardError.new("API timeout"))

        result = generator.generate(**draft_params)
        expect(result).to include("[ERROR: Draft generation failed")
        expect(result).to include("API timeout")
      end
    end

    context "body truncation" do
      it "truncates thread body to 3000 characters" do
        long_body = "x" * 5000
        allow(llm_gateway).to receive(:draft) do |msg, **_|
          # The message includes the body truncated; verify it doesn't contain the full 5000 chars
          expect(msg).not_to include("x" * 3001)
          "Draft"
        end

        generator.generate(**draft_params.merge(thread_body: long_body))
      end
    end
  end
end
