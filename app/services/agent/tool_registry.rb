# frozen_string_literal: true

module Agent
  # Tool registry for agent framework
  #
  # Manages available tools and provides:
  # - Registration with name, description, parameters, and handler
  # - Spec generation in OpenAI function-calling format
  # - Tool execution with error handling
  # - Filtering by tool name list for different agent profiles
  class ToolRegistry
    class << self
      # Get the singleton registry instance
      def instance
        @instance ||= new
      end

      # Register a tool (delegates to instance)
      def register(name, description:, parameters:, &handler)
        instance.register(name, description: description, parameters: parameters, &handler)
      end

      # Get tool specs (delegates to instance)
      def specs_for(tool_names)
        instance.specs_for(tool_names)
      end

      # Execute a tool (delegates to instance)
      def execute(tool_name, arguments)
        instance.execute(tool_name, arguments)
      end
    end

    def initialize
      @tools = {}
    end

    # Register a tool with the registry
    #
    # @param name [String] Unique tool identifier
    # @param description [String] Natural language description for LLM
    # @param parameters [Hash] JSON Schema object defining accepted arguments
    # @yield Handler block that receives keyword arguments and returns result
    def register(name, description:, parameters:, &handler)
      @tools[name.to_s] = {
        name: name.to_s,
        description: description,
        parameters: parameters,
        handler: handler
      }
    end

    # Get OpenAI function-calling specs for specified tools
    #
    # @param tool_names [Array<String>] List of tool names to include
    # @return [Array<Hash>] Array of tool specs in OpenAI format
    def specs_for(tool_names)
      tool_names.map do |name|
        tool = @tools[name.to_s]
        raise ArgumentError, "Tool not found: #{name}" unless tool

        {
          type: "function",
          function: {
            name: tool[:name],
            description: tool[:description],
            parameters: tool[:parameters]
          }
        }
      end
    end

    # Execute a tool by name with given arguments
    #
    # @param tool_name [String] Name of the tool to execute
    # @param arguments [Hash] Arguments to pass to the tool handler
    # @return [Hash] Result from the tool handler (or error hash)
    def execute(tool_name, arguments)
      tool = @tools[tool_name.to_s]
      unless tool
        return {error: "Tool not found: #{tool_name}"}
      end

      begin
        # Convert string keys to symbols for cleaner handler code
        symbolized_args = arguments.transform_keys(&:to_sym)
        tool[:handler].call(**symbolized_args)
      rescue ArgumentError => e
        {error: "Invalid arguments for #{tool_name}: #{e.message}"}
      rescue StandardError => e
        Rails.logger.error "Tool execution error for #{tool_name}: #{e.class} - #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        {error: "Tool execution failed: #{e.message}"}
      end
    end
  end
end
