# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Llm
  # HTTP client for OpenAI-compatible LLM API endpoints
  class Client
    MAX_RETRIES = 3
    BASE_DELAY = 1 # seconds
    TIMEOUT_SECONDS = 120

    RETRYABLE_ERRORS = [
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      Errno::ETIMEDOUT,
      Errno::EPIPE,
      SocketError,
      OpenSSL::SSL::SSLError,
      Net::OpenTimeout,
      Net::ReadTimeout
    ].freeze

    attr_reader :api_key, :base_url

    def initialize(api_key:, base_url:)
      @api_key = api_key
      @base_url = base_url.end_with?("/") ? base_url.chop : base_url
    end

    # Make a completion request to the LLM API
    # @param model [String] Model name/ID
    # @param messages [Array<Hash>] Array of message objects with :role and :content
    # @param temperature [Float] Sampling temperature (0.0-2.0)
    # @param max_tokens [Integer] Maximum tokens to generate
    # @param tools [Array<Hash>] Optional array of tool specifications for function calling
    # @return [Hash] Response body with :choices, :usage, etc.
    def complete(model:, messages:, temperature: 0.7, max_tokens: nil, tools: nil)
      with_retry do
        request_body = {
          model: model,
          messages: messages,
          temperature: temperature
        }
        request_body[:max_tokens] = max_tokens if max_tokens
        request_body[:tools] = tools if tools && tools.any?

        response = post("/v1/chat/completions", request_body)
        parse_response(response)
      end
    end

    private

    def post(path, body)
      uri = URI("#{base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = TIMEOUT_SECONDS
      http.read_timeout = TIMEOUT_SECONDS

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{api_key}"
      request.body = body.to_json

      http.request(request)
    rescue *RETRYABLE_ERRORS => e
      raise NetworkError, "Network error: #{e.class} - #{e.message}"
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      raise TimeoutError, "Request timeout: #{e.message}"
    end

    def parse_response(response)
      case response.code.to_i
      when 200..299
        JSON.parse(response.body, symbolize_names: true)
      when 429
        raise RateLimitError.new(
          "Rate limit exceeded",
          status_code: response.code.to_i,
          response_body: response.body
        )
      when 400..499
        raise ClientError.new(
          "Client error: #{response.code} - #{response.body}",
          status_code: response.code.to_i,
          response_body: response.body
        )
      when 500..599
        raise ServerError.new(
          "Server error: #{response.code} - #{response.body}",
          status_code: response.code.to_i,
          response_body: response.body
        )
      else
        raise Error, "Unexpected response: #{response.code} - #{response.body}"
      end
    rescue JSON::ParserError => e
      raise Error, "Invalid JSON response: #{e.message}"
    end

    def with_retry
      attempts = 0
      begin
        attempts += 1
        yield
      rescue RateLimitError, ServerError, NetworkError, TimeoutError => e
        if attempts < MAX_RETRIES
          delay = BASE_DELAY * (2**(attempts - 1))
          Rails.logger.warn "LLM API error (attempt #{attempts}/#{MAX_RETRIES}): #{e.class} - #{e.message}. Retrying in #{delay}s..."
          sleep delay
          retry
        else
          Rails.logger.error "LLM API error after #{MAX_RETRIES} attempts: #{e.class} - #{e.message}"
          raise
        end
      rescue ClientError => e
        # Don't retry 4xx errors except 429 (already handled above)
        Rails.logger.error "LLM API client error: #{e.status_code} - #{e.message}"
        raise
      end
    end
  end
end
