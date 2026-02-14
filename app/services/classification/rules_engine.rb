# frozen_string_literal: true

module Classification
  # Deterministic automation detection via sender patterns and RFC headers
  #
  # The rule tier performs only automation detection — no content-based pattern matching.
  # All classification of email intent (payment, action, response, FYI) is delegated to the LLM.
  #
  # Returns an `is_automated` flag used as a safety net after LLM classification.
  class RulesEngine
    # Common automation sender patterns
    AUTOMATED_SENDER_PATTERNS = %w[
      noreply
      no-reply
      mailer-daemon
      postmaster
      notifications
      bounce
    ].freeze

    # RFC 3834 and common automation headers
    AUTOMATION_HEADERS = {
      "Auto-Submitted" => ->(value) { value && value != "no" },
      "Precedence" => ->(value) { value && %w[bulk list auto_reply junk].include?(value.downcase) },
      "List-Id" => ->(value) { value.present? },
      "List-Unsubscribe" => ->(value) { value.present? },
      "X-Auto-Response-Suppress" => ->(value) { value.present? },
      "Feedback-ID" => ->(value) { value.present? },
      "X-Autoreply" => ->(value) { value.present? },
      "X-Autorespond" => ->(value) { value.present? }
    }.freeze

    # Check if email is automated
    #
    # @param sender_email [String] Sender's email address
    # @param headers [Hash] Email headers
    # @return [Boolean] true if automation detected
    def self.automated?(sender_email:, headers:)
      new(sender_email: sender_email, headers: headers).automated?
    end

    def initialize(sender_email:, headers:)
      @sender_email = sender_email.to_s.downcase
      @headers = headers || {}
    end

    def automated?
      automated_sender? || automated_headers?
    end

    private

    def automated_sender?
      AUTOMATED_SENDER_PATTERNS.any? { |pattern| @sender_email.include?(pattern) }
    end

    def automated_headers?
      AUTOMATION_HEADERS.any? do |header_name, validator|
        header_value = @headers[header_name]
        validator.call(header_value)
      end
    end
  end
end
