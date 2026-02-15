module Classification
  class RuleEngine
    AUTOMATED_SENDER_PATTERNS = %w[
      noreply no-reply mailer-daemon postmaster notifications bounce
    ].freeze

    AUTOMATION_HEADERS = %w[
      List-Id List-Unsubscribe X-Auto-Response-Suppress
      Feedback-ID X-Autoreply X-Autorespond
    ].freeze

    PRECEDENCE_VALUES = %w[bulk list auto_reply junk].freeze

    def initialize(contacts_config: nil)
      @contacts_config = contacts_config || load_contacts_config
    end

    def evaluate(sender_email:, headers: {})
      return { is_automated: true } if blacklisted?(sender_email)
      return { is_automated: true } if automated_sender?(sender_email)
      return { is_automated: true } if automation_headers?(headers)

      { is_automated: false }
    end

    private

    def blacklisted?(sender_email)
      blacklist = @contacts_config["blacklist"] || []
      blacklist.any? { |pattern| File.fnmatch?(pattern, sender_email, File::FNM_CASEFOLD) }
    end

    def automated_sender?(sender_email)
      local_part = sender_email.to_s.split("@").first.to_s.downcase
      AUTOMATED_SENDER_PATTERNS.any? { |pattern| local_part.include?(pattern) }
    end

    def automation_headers?(headers)
      return false if headers.nil? || headers.empty?

      auto_submitted = headers["Auto-Submitted"]
      if auto_submitted && auto_submitted.to_s.downcase != "no"
        return true
      end

      precedence = headers["Precedence"]
      if precedence && PRECEDENCE_VALUES.include?(precedence.to_s.downcase)
        return true
      end

      AUTOMATION_HEADERS.any? { |header| headers.key?(header) && headers[header].present? }
    end

    def load_contacts_config
      YAML.load_file(Rails.root.join("config", "contacts.yml")) || {}
    rescue StandardError
      {}
    end
  end
end
