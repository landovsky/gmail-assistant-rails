# frozen_string_literal: true

module Agent
  # Config-driven email router
  #
  # Routes emails to either the standard pipeline or agent processing
  # based on matching rules (sender, domain, subject, headers, forwarding).
  class Router
    # Route outcomes
    ROUTE_PIPELINE = "pipeline"
    ROUTE_AGENT = "agent"

    def initialize(config)
      @config = config
      @rules = config.dig("routing", "rules") || []
    end

    # Determine the route for an email
    #
    # @param message [Hash] Parsed Gmail message (from Gmail::MessageParser)
    # @return [Hash] { route: "pipeline"|"agent", profile: "name" (if agent) }
    def route_for(message)
      @rules.each do |rule|
        if matches_rule?(message, rule)
          Rails.logger.info "Email matched routing rule: #{rule['name']}"

          route = rule["route"] || ROUTE_PIPELINE
          result = {route: route}
          result[:profile] = rule["profile"] if route == ROUTE_AGENT

          return result
        end
      end

      # Default to pipeline if no rules match
      {route: ROUTE_PIPELINE}
    end

    private

    def matches_rule?(message, rule)
      conditions = rule["match"] || {}

      # All specified conditions must match (AND logic)
      conditions.all? do |condition_type, condition_value|
        case condition_type
        when "all"
          condition_value == true
        when "sender_email"
          matches_sender_email?(message, condition_value)
        when "sender_domain"
          matches_sender_domain?(message, condition_value)
        when "subject_contains"
          matches_subject_contains?(message, condition_value)
        when "header_match"
          matches_headers?(message, condition_value)
        when "forwarded_from"
          matches_forwarded_from?(message, condition_value)
        else
          Rails.logger.warn "Unknown routing condition: #{condition_type}"
          false
        end
      end
    end

    def matches_sender_email?(message, expected_email)
      sender = extract_sender_email(message)
      sender&.downcase == expected_email.downcase
    end

    def matches_sender_domain?(message, expected_domain)
      sender = extract_sender_email(message)
      return false unless sender

      domain = sender.split("@").last
      domain&.downcase == expected_domain.downcase
    end

    def matches_subject_contains?(message, substring)
      subject = message.dig(:payload, :headers)&.find { |h| h[:name] == "Subject" }&.dig(:value) || ""
      subject.downcase.include?(substring.downcase)
    end

    def matches_headers?(message, header_patterns)
      headers = message.dig(:payload, :headers) || []
      header_hash = headers.each_with_object({}) do |h, acc|
        acc[h[:name]] = h[:value]
      end

      header_patterns.all? do |header_name, pattern|
        header_value = header_hash[header_name]
        next false unless header_value

        regex = Regexp.new(pattern, Regexp::IGNORECASE)
        regex.match?(header_value)
      end
    end

    def matches_forwarded_from?(message, forwarded_email)
      # Check multiple signals for forwarding:
      # 1. X-Forwarded-From header
      # 2. Reply-To header
      # 3. Email pattern in body
      # 4. Direct sender match

      headers = message.dig(:payload, :headers) || []
      header_hash = headers.each_with_object({}) do |h, acc|
        acc[h[:name]] = h[:value]
      end

      # Check X-Forwarded-From header
      if header_hash["X-Forwarded-From"]&.downcase&.include?(forwarded_email.downcase)
        return true
      end

      # Check Reply-To header
      if header_hash["Reply-To"]&.downcase&.include?(forwarded_email.downcase)
        return true
      end

      # Check sender email directly
      sender = extract_sender_email(message)
      if sender&.downcase == forwarded_email.downcase
        return true
      end

      # Check body for forwarding patterns
      body = extract_body(message)
      if body && forwarding_pattern_matches?(body, forwarded_email)
        return true
      end

      false
    end

    def forwarding_pattern_matches?(body, email)
      # Common forwarding patterns:
      # "From: email@example.com"
      # "---------- Forwarded message ---------"
      # Email address appears in first few lines

      lines = body.lines.first(10)
      lines.any? { |line| line.downcase.include?(email.downcase) }
    end

    def extract_sender_email(message)
      from_header = message.dig(:payload, :headers)&.find { |h| h[:name] == "From" }&.dig(:value)
      return nil unless from_header

      # Extract email from "Name <email@example.com>" format
      match = from_header.match(/<(.+?)>/)
      match ? match[1] : from_header
    end

    def extract_body(message)
      # Simple body extraction - just get text/plain part if available
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

      nil
    rescue StandardError => e
      Rails.logger.warn "Failed to extract body for routing: #{e.message}"
      nil
    end
  end
end
