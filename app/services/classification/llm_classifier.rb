module Classification
  class LlmClassifier
    VALID_CATEGORIES = %w[needs_response action_required payment_request fyi waiting].freeze
    DEFAULT_RESULT = {
      "category" => "needs_response",
      "confidence" => "low",
      "reasoning" => "Fallback: classification unavailable",
      "detected_language" => "en",
      "resolved_style" => "business"
    }.freeze

    SYSTEM_PROMPT = <<~PROMPT
      You are an email classifier. Classify the email into exactly ONE category.

      Categories:
      - needs_response: Direct question, personal request, social obligation to reply
      - action_required: Meeting request, signature needed, approval, deadline task
      - payment_request: Invoice, billing, amount due (unpaid only - payment confirmations are fyi)
      - fyi: Newsletter, automated notification, CC'd thread, no action needed
      - waiting: User sent the last message, awaiting reply

      Priority rules:
      - Meetings, approvals, deadlines -> action_required
      - Invoices, billing -> payment_request
      - Direct questions, personal requests -> needs_response
      - Uncertain -> prefer needs_response over fyi

      Available communication styles: %{style_names}
      Select the most appropriate style based on the email's tone, sender relationship signals, and content.

      Return ONLY valid JSON:
      {"category": "...", "confidence": "high|medium|low", "reasoning": "...", "detected_language": "cs|en|de|...", "resolved_style": "..."}
    PROMPT

    def initialize(llm_gateway:, styles_config: nil)
      @llm_gateway = llm_gateway
      @styles_config = styles_config || load_styles_config
    end

    def classify(sender_name:, sender_email:, subject:, body:, message_count: 1, snippet: nil)
      user_message = build_user_message(
        sender_name: sender_name,
        sender_email: sender_email,
        subject: subject,
        body: body,
        message_count: message_count,
        snippet: snippet
      )

      style_names = (@styles_config["styles"] || {}).keys.join(", ")
      system_prompt = format(SYSTEM_PROMPT, style_names: style_names)

      response = @llm_gateway.classify(user_message, system_prompt: system_prompt)
      parse_response(response)
    end

    private

    def build_user_message(sender_name:, sender_email:, subject:, body:, message_count:, snippet:)
      content = body.present? ? body.to_s[0, 2000] : snippet.to_s

      <<~MSG
        From: #{sender_name} <#{sender_email}>
        Subject: #{subject}
        Messages in thread: #{message_count}

        #{content}
      MSG
    end

    def parse_response(response)
      return DEFAULT_RESULT.dup if response.nil?

      json_match = response.match(/\{[^}]+\}/m)
      return DEFAULT_RESULT.dup unless json_match

      result = JSON.parse(json_match[0])

      unless VALID_CATEGORIES.include?(result["category"])
        result["category"] = "needs_response"
      end

      result["confidence"] ||= "medium"
      result["reasoning"] ||= ""
      result["detected_language"] ||= "en"
      result["resolved_style"] ||= "business"

      result
    rescue JSON::ParserError
      DEFAULT_RESULT.dup
    end

    def load_styles_config
      YAML.load_file(Rails.root.join("config", "communication_styles.yml")) || {}
    rescue StandardError
      {}
    end
  end
end
