require "rails_helper"

RSpec.describe Agents::AgentLoop do
  let(:registry) { Agents::ToolRegistry.new }
  let(:llm_client) { double("LlmClient") }
  let(:agent_loop) { described_class.new(llm_client: llm_client, tool_registry: registry) }

  let(:profile) do
    {
      model: "test-model",
      max_tokens: 100,
      temperature: 0.3,
      max_iterations: 5,
      system_prompt: "You are a test agent.",
      tools: [ "greet" ]
    }
  end

  before do
    registry.register(
      name: "greet",
      description: "Greet someone",
      parameters: { type: "object", properties: { name: { type: "string" } }, required: [ "name" ] },
      handler: ->(name:) { { greeting: "Hello, #{name}!" } }
    )
  end

  describe "#run" do
    context "when LLM responds without tool calls" do
      it "completes immediately" do
        allow(llm_client).to receive(:chat).and_return({
          role: "assistant",
          content: "I can help you with that!"
        })

        result = agent_loop.run(profile: profile, user_message: "Hello")

        expect(result.status).to eq("completed")
        expect(result.final_message).to eq("I can help you with that!")
        expect(result.tool_calls).to be_empty
        expect(result.iterations).to eq(1)
      end
    end

    context "when LLM makes tool calls then completes" do
      it "executes tools and returns result" do
        call_count = 0
        allow(llm_client).to receive(:chat) do
          call_count += 1
          if call_count == 1
            {
              role: "assistant",
              content: nil,
              tool_calls: [
                {
                  id: "call_1",
                  function: { name: "greet", arguments: { "name" => "World" } }
                }
              ]
            }
          else
            { role: "assistant", content: "Done greeting!" }
          end
        end

        result = agent_loop.run(profile: profile, user_message: "Greet the world")

        expect(result.status).to eq("completed")
        expect(result.final_message).to eq("Done greeting!")
        expect(result.tool_calls.length).to eq(1)
        expect(result.tool_calls.first[:tool]).to eq("greet")
        expect(result.tool_calls.first[:result]).to eq(greeting: "Hello, World!")
        expect(result.iterations).to eq(2)
      end
    end

    context "when max iterations reached" do
      it "returns max_iterations status" do
        profile_limited = profile.merge(max_iterations: 2)

        allow(llm_client).to receive(:chat).and_return({
          role: "assistant",
          content: nil,
          tool_calls: [
            { id: "call_x", function: { name: "greet", arguments: { "name" => "Again" } } }
          ]
        })

        result = agent_loop.run(profile: profile_limited, user_message: "Keep going")

        expect(result.status).to eq("max_iterations")
        expect(result.iterations).to eq(2)
      end
    end

    context "when LLM call fails" do
      it "returns error status" do
        allow(llm_client).to receive(:chat).and_raise(RuntimeError, "API down")

        result = agent_loop.run(profile: profile, user_message: "Hello")

        expect(result.status).to eq("error")
        expect(result.error).to eq("API down")
      end
    end
  end
end
