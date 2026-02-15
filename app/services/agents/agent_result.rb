module Agents
  AgentResult = Data.define(:status, :final_message, :tool_calls, :iterations, :error) do
    def initialize(status:, final_message: nil, tool_calls: [], iterations: 0, error: nil)
      super
    end
  end
end
