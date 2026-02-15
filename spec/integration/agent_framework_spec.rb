require "rails_helper"

RSpec.describe "Agent Framework", type: :request do
  describe "TC-7.1: Routing to agent profile" do
    it "routes matching email to agent profile based on forwarded_from rule" do
      rules = [
        {
          "match" => { "forwarded_from" => "info@pharmacy.com" },
          "route" => "agent",
          "profile" => "pharmacy"
        }
      ]

      router = Agents::Router.new(rules)

      # Email from forwarded source matching the rule
      result = router.route(
        sender_email: "forwarding@gmail.com",
        subject: "Fwd: Order confirmation",
        headers: { "X-Forwarded-From" => "info@pharmacy.com" },
        body: "Forwarded message from pharmacy"
      )

      expect(result["route"]).to eq("agent")
      expect(result["profile"]).to eq("pharmacy")

      # Non-matching email goes to pipeline
      pipeline_result = router.route(
        sender_email: "colleague@company.com",
        subject: "Meeting tomorrow",
        headers: {},
        body: "Let's meet at 10am"
      )

      expect(pipeline_result["route"]).to eq("pipeline")
      expect(pipeline_result["profile"]).to be_nil
    end
  end

  describe "TC-7.2: Agent loop completes with tool calls" do
    it "executes tool calls and returns completed status with tool call log" do
      # Set up tool registry with a test tool
      registry = Agents::ToolRegistry.new
      registry.register(
        name: "search_drugs",
        description: "Search drug database",
        parameters: { type: "object", properties: { query: { type: "string" } } },
        handler: ->(query:) { { name: "Ibuprofen", dosage: "400mg", status: "available" } }
      )

      # Mock LLM client: first call returns tool call, second returns final message
      llm_client = mock_llm_client(responses: [
        llm_agent_tool_call_response(
          tool_name: "search_drugs",
          arguments: { query: "ibuprofen" },
          call_id: "call_1"
        ),
        llm_agent_final_response(content: "Ibuprofen 400mg is available.")
      ])

      profile = {
        model: "test-model",
        max_tokens: 4096,
        temperature: 0.3,
        max_iterations: 10,
        system_prompt: "You are a pharmacy assistant.",
        tools: ["search_drugs"]
      }

      loop = Agents::AgentLoop.new(llm_client: llm_client, tool_registry: registry)
      result = loop.run(profile: profile, user_message: "Check if ibuprofen is available")

      expect(result.status).to eq("completed")
      expect(result.final_message).to eq("Ibuprofen 400mg is available.")
      expect(result.tool_calls.length).to eq(1)
      expect(result.tool_calls.first[:tool]).to eq("search_drugs")
      expect(result.tool_calls.first[:arguments]).to eq({ "query" => "ibuprofen" })
      expect(result.tool_calls.first[:result]).to include(name: "Ibuprofen")
      expect(result.iterations).to eq(2)
    end
  end

  describe "TC-7.3: Agent loop hits max iterations" do
    it "stops after max_iterations and records max_iterations status" do
      registry = Agents::ToolRegistry.new
      registry.register(
        name: "search_drugs",
        description: "Search drug database",
        parameters: { type: "object", properties: { query: { type: "string" } } },
        handler: ->(query:) { { name: query, status: "found" } }
      )

      # LLM always returns tool calls, never a final message
      llm_client = mock_llm_client(responses: [
        llm_agent_tool_call_response(
          tool_name: "search_drugs",
          arguments: { query: "aspirin" },
          call_id: "call_1"
        ),
        llm_agent_tool_call_response(
          tool_name: "search_drugs",
          arguments: { query: "paracetamol" },
          call_id: "call_2"
        )
      ])

      profile = {
        model: "test-model",
        max_tokens: 4096,
        temperature: 0.3,
        max_iterations: 2,
        system_prompt: "You are a pharmacy assistant.",
        tools: ["search_drugs"]
      }

      loop = Agents::AgentLoop.new(llm_client: llm_client, tool_registry: registry)
      result = loop.run(profile: profile, user_message: "Search all drugs")

      expect(result.status).to eq("max_iterations")
      expect(result.iterations).to eq(2)
      expect(result.tool_calls.length).to eq(2)
      # Final message should be nil since LLM only returned tool calls (content: nil)
      expect(result.final_message).to be_nil
    end
  end

  describe "TC-7.4: Agent with unknown profile fails gracefully" do
    it "handles error when tool registry raises for unknown tool" do
      registry = Agents::ToolRegistry.new
      # No tools registered

      # LLM tries to call a non-existent tool
      llm_client = mock_llm_client(responses: [
        llm_agent_tool_call_response(
          tool_name: "nonexistent_tool",
          arguments: { query: "test" },
          call_id: "call_1"
        ),
        llm_agent_final_response(content: "I encountered an error with the tool.")
      ])

      profile = {
        model: "test-model",
        max_tokens: 4096,
        temperature: 0.3,
        max_iterations: 5,
        system_prompt: "You are a test assistant.",
        tools: []
      }

      loop = Agents::AgentLoop.new(llm_client: llm_client, tool_registry: registry)
      result = loop.run(profile: profile, user_message: "Do something")

      # The tool registry returns an error hash for unknown tools (rescue in execute),
      # so the loop continues and completes
      expect(result.status).to eq("completed")
      expect(result.tool_calls.length).to eq(1)
      expect(result.tool_calls.first[:result]).to have_key(:error)
      expect(result.final_message).to eq("I encountered an error with the tool.")
    end
  end
end
