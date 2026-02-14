# frozen_string_literal: true

module Llm
  # Base error class for LLM-related errors
  class Error < StandardError; end

  # Raised when the API returns a client error (4xx)
  class ClientError < Error
    attr_reader :status_code, :response_body

    def initialize(message, status_code: nil, response_body: nil)
      super(message)
      @status_code = status_code
      @response_body = response_body
    end
  end

  # Raised when the API returns a server error (5xx)
  class ServerError < Error
    attr_reader :status_code, :response_body

    def initialize(message, status_code: nil, response_body: nil)
      super(message)
      @status_code = status_code
      @response_body = response_body
    end
  end

  # Raised when the API returns a rate limit error (429)
  class RateLimitError < ClientError; end

  # Raised on network errors
  class NetworkError < Error; end

  # Raised on timeout errors
  class TimeoutError < Error; end
end
