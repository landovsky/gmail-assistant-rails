require "rails_helper"

RSpec.describe Agents::ToolRegistry do
  let(:registry) { described_class.new }

  before do
    registry.register(
      name: "greet",
      description: "Greet someone",
      parameters: {
        type: "object",
        properties: { name: { type: "string" } },
        required: [ "name" ]
      },
      handler: ->(name:) { { greeting: "Hello, #{name}!" } }
    )
  end

  describe "#register and #get" do
    it "registers and retrieves a tool" do
      tool = registry.get("greet")
      expect(tool.name).to eq("greet")
      expect(tool.description).to eq("Greet someone")
    end

    it "returns nil for unknown tool" do
      expect(registry.get("unknown")).to be_nil
    end
  end

  describe "#execute" do
    it "executes a registered tool" do
      result = registry.execute("greet", { name: "World" })
      expect(result).to eq(greeting: "Hello, World!")
    end

    it "returns error hash for unknown tool" do
      result = registry.execute("unknown", {})
      expect(result).to have_key(:error)
      expect(result[:error]).to include("Unknown tool")
    end

    it "catches handler errors and returns error hash" do
      registry.register(
        name: "boom",
        description: "Always fails",
        parameters: { type: "object", properties: {} },
        handler: ->(**_args) { raise "Kaboom!" }
      )

      result = registry.execute("boom", {})
      expect(result[:error]).to eq("Kaboom!")
    end
  end

  describe "#specs" do
    it "returns OpenAI function-calling format" do
      specs = registry.specs
      expect(specs.length).to eq(1)
      expect(specs.first[:type]).to eq("function")
      expect(specs.first[:function][:name]).to eq("greet")
    end

    it "filters by tool names" do
      registry.register(
        name: "farewell",
        description: "Say goodbye",
        parameters: { type: "object", properties: {} },
        handler: ->(**_args) { { message: "Bye!" } }
      )

      specs = registry.specs([ "greet" ])
      expect(specs.length).to eq(1)
      expect(specs.first[:function][:name]).to eq("greet")
    end
  end

  describe "#registered_names" do
    it "returns all registered tool names" do
      expect(registry.registered_names).to eq([ "greet" ])
    end
  end
end
