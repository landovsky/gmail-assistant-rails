# frozen_string_literal: true

module Agent
  # Agent execution loop with multi-turn LLM conversations
  #
  # Implements tool-use pattern:
  # 1. Send messages + tools to LLM
  # 2. Process tool calls in response
  # 3. Append results and continue
  # 4. Repeat until agent is done or max_iterations reached
  class Runner
    attr_reader :profile_name, :config, :messages, :tool_calls_log, :iterations

    def initialize(profile_name:, config:, initial_message:)
      @profile_name = profile_name
      @config = config
      @profile_config = config.dig("agent", "profiles", profile_name)

      raise ArgumentError, "Agent profile not found: #{profile_name}" unless @profile_config

      @max_iterations = @profile_config["max_iterations"] || 10
      @messages = build_initial_messages(initial_message)
      @tool_calls_log = []
      @iterations = 0
    end

    # Run the agent loop
    #
    # @return [Hash] {
    #   status: "completed"|"max_iterations"|"error",
    #   final_message: String,
    #   tool_calls: Array,
    #   iterations: Integer,
    #   error: String (optional)
    # }
    def run
      @max_iterations.times do |iteration_num|
        @iterations = iteration_num + 1

        begin
          response = call_llm
          assistant_message = extract_assistant_message(response)
          @messages << assistant_message

          # Check if agent is done (no tool calls)
          tool_calls = assistant_message[:tool_calls]
          if tool_calls.nil? || tool_calls.empty?
            return {
              status: "completed",
              final_message: assistant_message[:content] || "",
              tool_calls: @tool_calls_log,
              iterations: @iterations
            }
          end

          # Process tool calls
          process_tool_calls(tool_calls, iteration_num + 1)

        rescue StandardError => e
          Rails.logger.error "Agent loop error: #{e.class} - #{e.message}"
          Rails.logger.error e.backtrace.join("\n")

          return {
            status: "error",
            final_message: "",
            tool_calls: @tool_calls_log,
            iterations: @iterations,
            error: "#{e.class}: #{e.message}"
          }
        end
      end

      # Max iterations exhausted
      {
        status: "max_iterations",
        final_message: @messages.last[:content] || "",
        tool_calls: @tool_calls_log,
        iterations: @iterations
      }
    end

    private

    def build_initial_messages(initial_message)
      system_prompt = load_system_prompt

      [
        {role: "system", content: system_prompt},
        {role: "user", content: initial_message}
      ]
    end

    def load_system_prompt
      prompt_file = @profile_config["system_prompt_file"]
      raise ArgumentError, "system_prompt_file not configured for profile #{profile_name}" unless prompt_file

      prompt_path = Rails.root.join(prompt_file)
      unless File.exist?(prompt_path)
        raise ArgumentError, "System prompt file not found: #{prompt_path}"
      end

      File.read(prompt_path)
    end

    def call_llm
      model = @profile_config["model"] || "gemini/gemini-2.0-flash-exp"
      temperature = @profile_config["temperature"] || 0.3
      max_tokens = @profile_config["max_tokens"] || 4096

      tools = ToolRegistry.specs_for(@profile_config["tools"])

      # Build request - include tools in the message
      request_params = {
        model: model,
        messages: @messages,
        temperature: temperature,
        max_tokens: max_tokens,
        tools: tools
      }

      # Call LLM via gateway (uses custom OpenAI-compatible client)
      # The Llm::Client already handles tool specifications via the tools parameter
      client = Llm::Client.new(
        api_key: ENV.fetch("LLM_API_KEY"),
        base_url: ENV.fetch("LLM_API_BASE_URL")
      )

      # Need to make a custom request that includes tools
      response = client.complete(
        model: model,
        messages: @messages,
        temperature: temperature,
        max_tokens: max_tokens,
        tools: tools
      )

      # Log the LLM call
      log_llm_call(request_params, response)

      response
    end

    def extract_assistant_message(response)
      choice = response[:choices]&.first
      raise "No choices in LLM response" unless choice

      message = choice[:message]
      raise "No message in LLM response" unless message

      # Normalize the message format
      {
        role: "assistant",
        content: message[:content],
        tool_calls: message[:tool_calls]
      }
    end

    def process_tool_calls(tool_calls, iteration_num)
      tool_calls.each do |tool_call|
        tool_name = tool_call.dig(:function, :name)
        arguments_json = tool_call.dig(:function, :arguments) || "{}"
        tool_call_id = tool_call[:id]

        # Parse arguments (handle JSON parse failures gracefully)
        begin
          arguments = JSON.parse(arguments_json)
        rescue JSON::ParserError => e
          Rails.logger.warn "Failed to parse tool arguments: #{e.message}"
          arguments = {}
        end

        # Execute tool
        result = ToolRegistry.execute(tool_name, arguments)

        # Log the tool call
        @tool_calls_log << {
          tool: tool_name,
          arguments: arguments,
          result: result,
          iteration: iteration_num
        }

        # Append tool result to conversation
        @messages << {
          role: "tool",
          tool_call_id: tool_call_id,
          content: result.to_json
        }
      end
    end

    def log_llm_call(request, response)
      # Log to llm_calls table if model exists
      return unless defined?(LlmCall)

      LlmCall.create!(
        call_type: "agent",
        model: request[:model],
        request_messages: request[:messages].to_json,
        response_content: response.to_json,
        prompt_tokens: response.dig(:usage, :prompt_tokens) || 0,
        completion_tokens: response.dig(:usage, :completion_tokens) || 0,
        total_tokens: response.dig(:usage, :total_tokens) || 0
      )
    rescue StandardError => e
      Rails.logger.warn "Failed to log LLM call: #{e.message}"
    end
  end
end
