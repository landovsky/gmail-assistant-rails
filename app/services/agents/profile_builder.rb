module Agents
  class ProfileBuilder
    class << self
      def build_all
        profiles_config = AppConfig.agent&.dig("profiles") || {}
        profiles_config.each_with_object({}) do |(name, config), hash|
          hash[name] = build_profile(name, config)
        end
      end

      def build_profile(name, config)
        system_prompt = load_system_prompt(config["system_prompt_file"])

        {
          name: name,
          model: config["model"] || "gemini/gemini-2.5-pro",
          max_tokens: config["max_tokens"] || 4096,
          temperature: config["temperature"] || 0.3,
          max_iterations: config["max_iterations"] || 10,
          system_prompt: system_prompt,
          tools: config["tools"] || []
        }
      end

      private

      def load_system_prompt(file_path)
        return nil unless file_path.present?

        full_path = Rails.root.join(file_path)
        return nil unless File.exist?(full_path)

        File.read(full_path)
      end
    end
  end
end
