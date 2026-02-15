require "rails_helper"

RSpec.describe "Agent Framework", type: :request do
  describe "TC-7.1: Routing to agent profile" do
    xit "routes matching email to agent_process job instead of classify" do
      # Preconditions: Routing rule matches forwarded_from: "info@pharmacy.com"
      #   -> agent profile "pharmacy".
      # Actions:
      # 1. New email arrives from forwarded source
      # 2. Sync engine processes it
      # Expected:
      # - Router returns route=agent, profile=pharmacy
      # - agent_process job enqueued (not classify)
      # - Payload includes profile: "pharmacy"
    end
  end

  describe "TC-7.2: Agent loop completes with tool calls" do
    xit "executes tool calls and records agent run with completed status" do
      # Preconditions: Agent profile configured with tools. LLM returns
      #   tool calls then completes.
      # Actions: Process agent_process job
      # Expected:
      # - Agent run record created with status running
      # - LLM called with tools in conversation
      # - Tools executed via registry
      # - Agent run updated: status=completed, tool_calls_log populated
      # - classified event logged with iteration/tool call summary
    end
  end

  describe "TC-7.3: Agent loop hits max iterations" do
    xit "stops after max_iterations and records max_iterations status" do
      # Preconditions: Agent profile with max_iterations=2. LLM keeps making
      #   tool calls.
      # Actions: Process agent_process job
      # Expected:
      # - Agent runs for exactly 2 iterations
      # - Agent run updated: status=max_iterations
      # - Last assistant message preserved as final_message
    end
  end

  describe "TC-7.4: Agent with unknown profile fails gracefully" do
    xit "logs error and completes job without crash for unknown profile" do
      # Preconditions: Job payload references profile "nonexistent".
      # Actions: Process agent_process job
      # Expected:
      # - Error logged about unknown profile
      # - Job completes (no crash)
    end
  end
end
