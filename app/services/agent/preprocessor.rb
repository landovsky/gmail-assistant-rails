# frozen_string_literal: true

module Agent
  # Email preprocessor base class
  #
  # Preprocessors extract structured data from emails before they
  # reach the agent loop.
  class Preprocessor
    class << self
      # Get the appropriate preprocessor for a profile
      def for_profile(profile_name, config)
        preprocessor_type = config.dig("agent", "profiles", profile_name, "preprocessor")

        case preprocessor_type
        when "crisp"
          CrispPreprocessor.new
        else
          DefaultPreprocessor.new
        end
      end
    end

    # Preprocess a Gmail message
    # @param message [Hash] Parsed Gmail message
    # @return [String] Formatted message for the agent
    def preprocess(message)
      raise NotImplementedError
    end

    protected

    def extract_sender_email(message)
      from_header = message.dig(:payload, :headers)&.find { |h| h[:name] == "From" }&.dig(:value)
      return nil unless from_header

      # Extract email from "Name <email@example.com>" format
      match = from_header.match(/<(.+?)>/)
      match ? match[1] : from_header
    end

    def extract_subject(message)
      message.dig(:payload, :headers)&.find { |h| h[:name] == "Subject" }&.dig(:value) || ""
    end

    def extract_body(message)
      payload = message[:payload]

      if payload[:body] && payload[:body][:data]
        return Base64.urlsafe_decode64(payload[:body][:data])
      end

      # Check parts for text/plain
      parts = payload[:parts] || []
      text_part = parts.find { |p| p[:mimeType] == "text/plain" }
      if text_part && text_part[:body] && text_part[:body][:data]
        return Base64.urlsafe_decode64(text_part[:body][:data])
      end

      ""
    rescue StandardError => e
      Rails.logger.warn "Failed to extract body: #{e.message}"
      ""
    end
  end

  # Default pass-through preprocessor
  class DefaultPreprocessor < Preprocessor
    def preprocess(message)
      sender = extract_sender_email(message)
      subject = extract_subject(message)
      body = extract_body(message)

      <<~MSG
        From: #{sender}
        Subject: #{subject}

        #{body}
      MSG
    end
  end

  # Crisp helpdesk preprocessor
  #
  # Extracts customer information from Crisp-forwarded emails
  class CrispPreprocessor < Preprocessor
    # Regex patterns for Crisp formatting (Czech and English)
    CRISP_NAME_PATTERN = /(?:Nová zpráva od|New message from):\s*(.+?)(?:\n|$)/i
    CRISP_EMAIL_PATTERN = /(?:E-mail|Email):\s*(.+?)(?:\n|$)/i
    CRISP_SEPARATOR = /(?:-{3,}|={3,})/

    def preprocess(message)
      body = extract_body(message)
      subject = extract_subject(message)

      # Try to extract Crisp-specific fields
      patient_name = extract_crisp_name(body)
      patient_email = extract_crisp_email(body)
      original_message = extract_original_message(body)

      if patient_name || patient_email
        # Crisp email detected
        format_crisp_message(patient_name, patient_email, subject, original_message)
      else
        # Fall back to default format
        DefaultPreprocessor.new.preprocess(message)
      end
    end

    private

    def extract_crisp_name(body)
      match = body.match(CRISP_NAME_PATTERN)
      match ? match[1].strip : nil
    end

    def extract_crisp_email(body)
      match = body.match(CRISP_EMAIL_PATTERN)
      match ? match[1].strip : nil
    end

    def extract_original_message(body)
      # Find the separator and take content after it
      lines = body.lines
      separator_index = lines.index { |line| line.match?(CRISP_SEPARATOR) }

      if separator_index
        # Take content after separator, skip empty lines
        message_lines = lines[(separator_index + 1)..]
        message_lines.join.strip
      else
        # If no separator found, take the whole body
        body.strip
      end
    end

    def format_crisp_message(patient_name, patient_email, subject, message)
      parts = []
      parts << "New support inquiry from #{patient_name}" if patient_name
      parts << "(#{patient_email})" if patient_email

      header = parts.join(" ")

      <<~MSG
        #{header}
        Subject: #{subject}

        #{message}
      MSG
    end
  end
end
