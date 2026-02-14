# frozen_string_literal: true

module Gmail
  # Parses Gmail API message objects to extract headers and body
  class MessageParser
    EXTRACTED_HEADERS = %w[
      From To Subject Date Message-ID Auto-Submitted Precedence List-Id
      List-Unsubscribe X-Auto-Response-Suppress Feedback-ID X-Autoreply
      X-Autorespond X-Forwarded-From Reply-To
    ].freeze

    def initialize(message)
      @message = message
    end

    def headers
      @headers ||= begin
        header_hash = {}
        return header_hash unless @message.payload&.headers

        @message.payload.headers.each do |header|
          header_hash[header.name] = header.value if EXTRACTED_HEADERS.include?(header.name)
        end
        header_hash
      end
    end

    def header(name)
      headers[name]
    end

    def from
      parse_email_address(header("From"))
    end

    def subject
      header("Subject")
    end

    def message_id
      header("Message-ID")
    end

    def body
      @body ||= extract_text_plain(@message.payload)
    end

    private

    def parse_email_address(from_header)
      return { email: "", name: "" } if from_header.blank?

      # Match: "Display Name" <email@domain.com> or email@domain.com
      if from_header =~ /"?([^"<]+)"?\s*<([^>]+)>/
        { name: $1.strip, email: $2.strip }
      elsif from_header =~ /<([^>]+)>/
        { name: "", email: $1.strip }
      else
        { name: "", email: from_header.strip }
      end
    end

    def extract_text_plain(payload)
      return "" unless payload

      # Check if this part is text/plain
      if payload.mime_type == "text/plain" && payload.body&.data
        return decode_body(payload.body.data)
      end

      # Recurse through parts
      if payload.parts&.any?
        payload.parts.each do |part|
          result = extract_text_plain(part)
          return result if result.present?
        end
      end

      ""
    end

    def decode_body(data)
      # Base64url decode
      decoded = Base64.urlsafe_decode64(data)
      # Force UTF-8 encoding, replacing invalid characters
      decoded.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    rescue StandardError => e
      Rails.logger.warn "Failed to decode message body: #{e.message}"
      ""
    end
  end
end
