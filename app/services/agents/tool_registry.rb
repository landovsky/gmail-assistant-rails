module Agents
  class ToolRegistry
    ToolDefinition = Data.define(:name, :description, :parameters, :handler)

    def initialize
      @tools = {}
    end

    def register(name:, description:, parameters:, handler:)
      @tools[name] = ToolDefinition.new(
        name: name,
        description: description,
        parameters: parameters,
        handler: handler
      )
    end

    def get(name)
      @tools[name]
    end

    def execute(name, arguments = {})
      tool = @tools[name]
      raise "Unknown tool: #{name}" unless tool

      tool.handler.call(**arguments.symbolize_keys)
    rescue StandardError => e
      { error: e.message }
    end

    def specs(tool_names = nil)
      tools = if tool_names
                @tools.slice(*tool_names).values
              else
                @tools.values
              end

      tools.map do |tool|
        {
          type: "function",
          function: {
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters
          }
        }
      end
    end

    def registered_names
      @tools.keys
    end
  end
end
