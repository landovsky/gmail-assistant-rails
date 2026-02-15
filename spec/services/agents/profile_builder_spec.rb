require "rails_helper"

RSpec.describe Agents::ProfileBuilder do
  describe ".build_all" do
    it "returns empty hash when no profiles configured" do
      allow(AppConfig).to receive(:agent).and_return({ "profiles" => {} })
      expect(described_class.build_all).to eq({})
    end

    it "builds profiles from config" do
      prompt_file = Rails.root.join("tmp", "test_prompt.txt")
      File.write(prompt_file, "You are a test agent.")

      allow(AppConfig).to receive(:agent).and_return({
        "profiles" => {
          "test_profile" => {
            "model" => "gemini/gemini-2.5-pro",
            "max_tokens" => 2048,
            "temperature" => 0.5,
            "max_iterations" => 5,
            "system_prompt_file" => "tmp/test_prompt.txt",
            "tools" => %w[search_drugs create_draft]
          }
        }
      })

      profiles = described_class.build_all

      expect(profiles).to have_key("test_profile")
      profile = profiles["test_profile"]
      expect(profile[:name]).to eq("test_profile")
      expect(profile[:model]).to eq("gemini/gemini-2.5-pro")
      expect(profile[:max_tokens]).to eq(2048)
      expect(profile[:temperature]).to eq(0.5)
      expect(profile[:max_iterations]).to eq(5)
      expect(profile[:system_prompt]).to eq("You are a test agent.")
      expect(profile[:tools]).to eq(%w[search_drugs create_draft])
    ensure
      File.delete(prompt_file) if File.exist?(prompt_file)
    end

    it "uses defaults when config values are missing" do
      allow(AppConfig).to receive(:agent).and_return({
        "profiles" => {
          "minimal" => {}
        }
      })

      profiles = described_class.build_all
      profile = profiles["minimal"]

      expect(profile[:model]).to eq("gemini/gemini-2.5-pro")
      expect(profile[:max_tokens]).to eq(4096)
      expect(profile[:temperature]).to eq(0.3)
      expect(profile[:max_iterations]).to eq(10)
      expect(profile[:system_prompt]).to be_nil
      expect(profile[:tools]).to eq([])
    end

    it "handles nil agent config" do
      allow(AppConfig).to receive(:agent).and_return(nil)
      expect(described_class.build_all).to eq({})
    end
  end
end
