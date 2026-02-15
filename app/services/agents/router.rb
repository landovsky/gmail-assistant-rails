module Agents
  class Router
    DEFAULT_ROUTE = { "route" => "pipeline", "profile" => nil }.freeze

    def initialize(rules = [])
      @rules = rules || []
    end

    def route(email_data)
      @rules.each do |rule|
        match = rule["match"] || {}
        next unless matches?(match, email_data)

        return {
          "route" => rule["route"] || "pipeline",
          "profile" => rule["profile"]
        }
      end

      DEFAULT_ROUTE.dup
    end

    private

    def matches?(conditions, email_data)
      conditions.all? do |key, value|
        case key.to_s
        when "all"
          value == true
        when "sender_email"
          email_data[:sender_email]&.downcase == value.downcase
        when "sender_domain"
          domain = email_data[:sender_email]&.split("@")&.last
          domain&.downcase == value.downcase
        when "subject_contains"
          email_data[:subject]&.downcase&.include?(value.downcase)
        when "header_match"
          headers = email_data[:headers] || {}
          value.all? do |header_name, pattern|
            header_value = headers[header_name]
            header_value && Regexp.new(pattern, Regexp::IGNORECASE).match?(header_value)
          end
        when "forwarded_from"
          check_forwarded_from(email_data, value)
        else
          false
        end
      end
    end

    def check_forwarded_from(email_data, expected)
      headers = email_data[:headers] || {}

      # Check X-Forwarded-From header
      return true if headers["X-Forwarded-From"]&.include?(expected)

      # Check Reply-To header
      return true if headers["Reply-To"]&.include?(expected)

      # Check sender email directly
      return true if email_data[:sender_email]&.include?(expected)

      # Check body for email pattern
      return true if email_data[:body]&.include?(expected)

      false
    end
  end
end
