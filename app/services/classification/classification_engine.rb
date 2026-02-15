module Classification
  class ClassificationEngine
    def initialize(rule_engine:, llm_classifier:, contacts_config: nil)
      @rule_engine = rule_engine
      @llm_classifier = llm_classifier
      @contacts_config = contacts_config || load_contacts_config
    end

    def classify(sender_name:, sender_email:, subject:, body:, message_count: 1, snippet: nil, headers: {})
      rule_result = @rule_engine.evaluate(sender_email: sender_email, headers: headers)

      llm_result = @llm_classifier.classify(
        sender_name: sender_name,
        sender_email: sender_email,
        subject: subject,
        body: body,
        message_count: message_count,
        snippet: snippet
      )

      # Safety net: automated email classified as needs_response -> override to fyi
      if rule_result[:is_automated] && llm_result["category"] == "needs_response"
        llm_result["category"] = "fyi"
        llm_result["reasoning"] = "Overridden: automated sender detected by rule engine. Original: #{llm_result['reasoning']}"
      end

      # Resolve communication style with priority chain
      resolved_style = resolve_style(sender_email, llm_result["resolved_style"])
      llm_result["resolved_style"] = resolved_style

      llm_result
    end

    private

    def resolve_style(sender_email, llm_style)
      # 1. Exact email match
      style_overrides = @contacts_config["style_overrides"] || {}
      return style_overrides[sender_email] if style_overrides.key?(sender_email)

      # 2. Domain pattern match
      domain = sender_email.to_s.split("@").last
      domain_overrides = @contacts_config["domain_overrides"] || {}
      domain_overrides.each do |pattern, style|
        return style if File.fnmatch?(pattern, domain, File::FNM_CASEFOLD)
      end

      # 3. LLM-determined style
      return llm_style if llm_style.present?

      # 4. Fallback
      "business"
    end

    def load_contacts_config
      YAML.load_file(Rails.root.join("config", "contacts.yml")) || {}
    rescue StandardError
      {}
    end
  end
end
