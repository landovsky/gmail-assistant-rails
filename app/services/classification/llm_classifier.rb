# frozen_string_literal: true

module Classification
  # LLM-based email classification for intent detection
  #
  # Analyzes email content to classify into one of five categories and detect
  # appropriate response style.
  class LlmClassifier
    VALID_CATEGORIES = %w[needs_response action_required payment_request fyi waiting].freeze
    VALID_CONFIDENCE_LEVELS = %w[high medium low].freeze
    DEFAULT_CATEGORY = "needs_response"
    DEFAULT_CONFIDENCE = "low"
    DEFAULT_STYLE = "business"
    MAX_BODY_LENGTH = 2000

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are an email classification assistant. Classify emails into exactly ONE category.

      Categories:
      - needs_response: Direct question, personal request, social obligation to reply
      - action_required: Meeting request, signature needed, approval, deadline task
      - payment_request: Invoice, billing, amount due (unpaid only — payment confirmations classify as fyi)
      - fyi: Newsletter, automated notification, CC'd thread, no action needed
      - waiting: User sent the last message, awaiting reply

      Priority rules:
      1. Meetings → action_required
      2. Invoices → payment_request
      3. Direct questions → needs_response
      4. Uncertain → prefer needs_response over fyi

      Response style detection:
      Detect the appropriate response style based on the email's tone and sender relationship:
      - business: Professional, formal tone
      - casual: Informal, friendly tone
      - technical: Technical discussion, code or system-related

      Return JSON with this exact structure:
      {
        "category": "needs_response|action_required|payment_request|fyi|waiting",
        "confidence": "high|medium|low",
        "reasoning": "Brief explanation of classification",
        "detected_language": "cs|en|de|...",
        "resolved_style": "business|casual|technical"
      }
    PROMPT

    # Classify an email using LLM
    #
    # @param sender_name [String] Sender's name
    # @param sender_email [String] Sender's email address
    # @param subject [String] Email subject
    # @param body [String] Email body (will be truncated)
    # @param snippet [String] Email snippet (used if body is empty)
    # @param message_count [Integer] Number of messages in thread
    # @param user [User] User for LLM call tracking
    # @param gmail_thread_id [String] Gmail thread ID for tracking
    # @return [Hash] Classification result with :category, :confidence, :reasoning, :detected_language, :resolved_style
    def self.classify(sender_name:, sender_email:, subject:, body:, snippet:, message_count:, user:, gmail_thread_id:)
      new(
        sender_name: sender_name,
        sender_email: sender_email,
        subject: subject,
        body: body,
        snippet: snippet,
        message_count: message_count,
        user: user,
        gmail_thread_id: gmail_thread_id
      ).classify
    end

    def initialize(sender_name:, sender_email:, subject:, body:, snippet:, message_count:, user:, gmail_thread_id:)
      @sender_name = sender_name
      @sender_email = sender_email
      @subject = subject
      @body = body
      @snippet = snippet
      @message_count = message_count
      @user = user
      @gmail_thread_id = gmail_thread_id
    end

    def classify
      response = call_llm
      parse_response(response)
    rescue Llm::Error, JSON::ParserError => e
      Rails.logger.error "LLM classification failed: #{e.class} - #{e.message}"
      track_llm_error(e)
      fallback_result
    end

    private

    def call_llm
      user_message = build_user_message

      start_time = Time.current
      result = Llm::Gateway.complete(
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: user_message }
        ],
        model_tier: :fast,
        temperature: 0.3
      )
      latency_ms = ((Time.current - start_time) * 1000).to_i

      track_llm_success(user_message, result, latency_ms)
      result
    end

    def build_user_message
      content = @body.presence || @snippet.presence || ""
      truncated_content = content.truncate(MAX_BODY_LENGTH, omission: "...")

      <<~MESSAGE
        From: #{@sender_name} <#{@sender_email}>
        Subject: #{@subject}
        Messages in thread: #{@message_count}

        #{truncated_content}
      MESSAGE
    end

    def parse_response(result)
      content = result.dig(:choices, 0, :message, :content)
      raise Llm::Error, "Empty LLM response" if content.blank?

      parsed = JSON.parse(content)

      category = parsed["category"]
      unless VALID_CATEGORIES.include?(category)
        Rails.logger.warn "Invalid category '#{category}' from LLM, using default"
        category = DEFAULT_CATEGORY
      end

      confidence = parsed["confidence"]
      unless VALID_CONFIDENCE_LEVELS.include?(confidence)
        Rails.logger.warn "Invalid confidence '#{confidence}' from LLM, using default"
        confidence = DEFAULT_CONFIDENCE
      end

      {
        category: category,
        confidence: confidence,
        reasoning: parsed["reasoning"].to_s.truncate(500),
        detected_language: parsed["detected_language"] || "cs",
        resolved_style: parsed["resolved_style"] || DEFAULT_STYLE
      }
    end

    def fallback_result
      {
        category: DEFAULT_CATEGORY,
        confidence: DEFAULT_CONFIDENCE,
        reasoning: "LLM classification failed - using safe default",
        detected_language: "cs",
        resolved_style: DEFAULT_STYLE
      }
    end

    def track_llm_success(user_message, result, latency_ms)
      content = result.dig(:choices, 0, :message, :content)
      usage = result[:usage] || {}

      LlmCall.create!(
        user: @user,
        gmail_thread_id: @gmail_thread_id,
        call_type: "classify",
        model: extract_model(result),
        system_prompt: SYSTEM_PROMPT,
        user_message: user_message,
        response_text: content,
        prompt_tokens: usage[:prompt_tokens] || 0,
        completion_tokens: usage[:completion_tokens] || 0,
        total_tokens: usage[:total_tokens] || 0,
        latency_ms: latency_ms
      )
    rescue => e
      Rails.logger.error "Failed to track LLM call: #{e.class} - #{e.message}"
    end

    def track_llm_error(error)
      LlmCall.create!(
        user: @user,
        gmail_thread_id: @gmail_thread_id,
        call_type: "classify",
        model: "unknown",
        system_prompt: SYSTEM_PROMPT,
        user_message: build_user_message,
        error: "#{error.class}: #{error.message}"
      )
    rescue => e
      Rails.logger.error "Failed to track LLM error: #{e.class} - #{e.message}"
    end

    def extract_model(result)
      result[:model] || ENV["LLM_FAST_MODEL"] || "unknown"
    end
  end
end
