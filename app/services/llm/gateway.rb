# frozen_string_literal: true

module Llm
  # Model-agnostic LLM gateway for chat completions
  #
  # Usage:
  #   result = Llm::Gateway.complete(
  #     messages: [
  #       { role: "system", content: "You are a helpful assistant" },
  #       { role: "user", content: "Hello!" }
  #     ],
  #     model_tier: :fast
  #   )
  #
  #   content = result[:choices].first[:message][:content]
  class Gateway
    MODEL_TIERS = %i[fast quality].freeze

    class << self
      # Make a chat completion request
      # @param messages [Array<Hash>] Array of message objects with :role and :content
      # @param model_tier [Symbol] Either :fast or :quality
      # @param temperature [Float] Sampling temperature (0.0-2.0)
      # @param max_tokens [Integer] Maximum tokens to generate
      # @return [Hash] Response with :choices, :usage, etc.
      def complete(messages:, model_tier: :fast, temperature: 0.7, max_tokens: nil)
        validate_tier!(model_tier)
        validate_messages!(messages)

        model = model_for_tier(model_tier)
        client.complete(
          model: model,
          messages: messages,
          temperature: temperature,
          max_tokens: max_tokens
        )
      end

      private

      def client
        @client ||= Client.new(
          api_key: api_key,
          base_url: base_url
        )
      end

      def api_key
        ENV.fetch("LLM_API_KEY") do
          raise Error, "LLM_API_KEY environment variable not set"
        end
      end

      def base_url
        ENV.fetch("LLM_API_BASE_URL") do
          raise Error, "LLM_API_BASE_URL environment variable not set"
        end
      end

      def model_for_tier(tier)
        case tier
        when :fast
          ENV.fetch("LLM_FAST_MODEL") do
            raise Error, "LLM_FAST_MODEL environment variable not set"
          end
        when :quality
          ENV.fetch("LLM_QUALITY_MODEL") do
            raise Error, "LLM_QUALITY_MODEL environment variable not set"
          end
        else
          raise Error, "Invalid model tier: #{tier}"
        end
      end

      def validate_tier!(tier)
        unless MODEL_TIERS.include?(tier)
          raise ArgumentError, "Invalid model_tier: #{tier}. Must be one of: #{MODEL_TIERS.join(', ')}"
        end
      end

      def validate_messages!(messages)
        unless messages.is_a?(Array) && messages.any?
          raise ArgumentError, "messages must be a non-empty array"
        end

        messages.each_with_index do |msg, index|
          unless msg.is_a?(Hash) && msg[:role] && msg[:content]
            raise ArgumentError, "Message at index #{index} must have :role and :content"
          end
        end
      end
    end
  end
end
