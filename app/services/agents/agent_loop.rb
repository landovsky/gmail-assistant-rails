module Agents
  class AgentLoop
    def initialize(llm_client:, tool_registry:)
      @llm_client = llm_client
      @tool_registry = tool_registry
    end

    def run(profile:, user_message:)
      messages = build_initial_messages(profile, user_message)
      tool_specs = @tool_registry.specs(profile[:tools])
      all_tool_calls = []
      iterations = 0
      last_had_tool_calls = false

      (1..profile[:max_iterations]).each do |iteration|
        iterations = iteration

        response = call_llm(profile, messages, tool_specs)
        return AgentResult.new(status: "error", iterations: iterations, error: response[:error]) if response[:error]

        assistant_message = response[:message]
        messages << assistant_message

        tool_calls = assistant_message[:tool_calls] || []
        if tool_calls.empty?
          last_had_tool_calls = false
          break
        end

        last_had_tool_calls = true

        tool_calls.each do |tc|
          tool_name = tc.dig(:function, :name)
          arguments = parse_arguments(tc.dig(:function, :arguments))
          result = @tool_registry.execute(tool_name, arguments)

          all_tool_calls << {
            tool: tool_name,
            arguments: arguments,
            result: result,
            iteration: iteration
          }

          messages << {
            role: "tool",
            tool_call_id: tc[:id],
            content: result.to_json
          }
        end
      end

      final_message = extract_final_message(messages)
      status = (iterations >= profile[:max_iterations] && last_had_tool_calls) ? "max_iterations" : "completed"

      AgentResult.new(
        status: status,
        final_message: final_message,
        tool_calls: all_tool_calls,
        iterations: iterations
      )
    rescue StandardError => e
      AgentResult.new(status: "error", iterations: iterations || 0, error: e.message)
    end

    private

    def build_initial_messages(profile, user_message)
      messages = []
      messages << { role: "system", content: profile[:system_prompt] } if profile[:system_prompt]
      messages << { role: "user", content: user_message }
      messages
    end

    def call_llm(profile, messages, tool_specs)
      response = @llm_client.chat(
        model: profile[:model],
        messages: messages,
        tools: tool_specs,
        max_tokens: profile[:max_tokens],
        temperature: profile[:temperature]
      )

      { message: response }
    rescue StandardError => e
      { error: e.message }
    end

    def parse_arguments(args_string)
      return {} unless args_string

      if args_string.is_a?(Hash)
        args_string
      else
        JSON.parse(args_string)
      end
    rescue JSON::ParserError
      {}
    end

    def extract_final_message(messages)
      last_assistant = messages.reverse.find { |m| m[:role] == "assistant" }
      last_assistant&.dig(:content)
    end

    def has_tool_calls?(message)
      message.is_a?(Hash) && message[:tool_calls].present?
    end
  end
end
