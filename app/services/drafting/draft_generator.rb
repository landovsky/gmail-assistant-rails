# frozen_string_literal: true

module Drafting
  # Generates AI draft replies using LLM
  #
  # Builds a system prompt from communication style config and generates
  # draft text that matches the appropriate style and language.
  class DraftGenerator
    REWORK_MARKER = "✂️"
    MAX_THREAD_BODY_LENGTH = 3000
    DEFAULT_STYLE = "business"
    DEFAULT_LANGUAGE = "cs"

    # Generate a draft reply
    #
    # @param email [Email] Email record with classification and style
    # @param thread_messages [Array<Google::Apis::GmailV1::Message>] Full thread messages
    # @param related_context [String, nil] Related context block from context gatherer
    # @param user_instructions [String, nil] User's rework instructions (for rework/manual draft)
    # @param user [User] User for LLM call tracking
    # @param gmail_thread_id [String] Gmail thread ID for tracking
    # @return [String] Draft text with rework marker
    def self.generate(email:, thread_messages:, related_context:, user_instructions:, user:, gmail_thread_id:)
      new(
        email: email,
        thread_messages: thread_messages,
        related_context: related_context,
        user_instructions: user_instructions,
        user: user,
        gmail_thread_id: gmail_thread_id
      ).generate
    end

    def initialize(email:, thread_messages:, related_context:, user_instructions:, user:, gmail_thread_id:)
      @email = email
      @thread_messages = thread_messages
      @related_context = related_context
      @user_instructions = user_instructions
      @user = user
      @gmail_thread_id = gmail_thread_id
      @communication_styles = load_communication_styles
    end

    def generate
      system_prompt = build_system_prompt
      user_message = build_user_message

      start_time = Time.current
      result = Llm::Gateway.complete(
        messages: [
          { role: "system", content: system_prompt },
          { role: "user", content: user_message }
        ],
        model_tier: :quality,
        temperature: 0.7
      )
      latency_ms = ((Time.current - start_time) * 1000).to_i

      draft_text = result.dig(:choices, 0, :message, :content)
      track_llm_success(system_prompt, user_message, result, latency_ms)

      # Wrap with rework marker
      "\n\n#{REWORK_MARKER}\n\n#{draft_text}"
    rescue => e
      Rails.logger.error "Draft generation failed: #{e.class} - #{e.message}"
      track_llm_error(system_prompt, user_message, e)
      "\n\n#{REWORK_MARKER}\n\n[ERROR: Draft generation failed — #{e.message}]"
    end

    private

    def load_communication_styles
      # Load from user settings (DB-first, YAML-fallback pattern)
      setting = @user.user_settings.find_by(setting_key: "communication_styles")
      if setting&.setting_value.present?
        JSON.parse(setting.setting_value)
      else
        # Fallback to default styles
        default_communication_styles
      end
    rescue => e
      Rails.logger.warn "Failed to load communication styles: #{e.class} - #{e.message}"
      default_communication_styles
    end

    def default_communication_styles
      {
        "business" => {
          "language" => "auto",
          "rules" => [
            "Use professional, formal tone",
            "Be concise and respectful",
            "Avoid emojis and casual expressions"
          ],
          "sign_off" => "Best regards",
          "examples" => []
        },
        "casual" => {
          "language" => "auto",
          "rules" => [
            "Use friendly, informal tone",
            "Be warm and personable",
            "Emojis are okay if appropriate"
          ],
          "sign_off" => "Cheers",
          "examples" => []
        },
        "technical" => {
          "language" => "auto",
          "rules" => [
            "Use precise technical language",
            "Be direct and clear",
            "Include technical details when relevant"
          ],
          "sign_off" => "Best",
          "examples" => []
        }
      }
    end

    def build_system_prompt
      style_name = @email.resolved_style || DEFAULT_STYLE
      style_config = @communication_styles[style_name] || @communication_styles[DEFAULT_STYLE]

      language = style_config["language"] || "auto"
      rules = style_config["rules"] || []
      sign_off = style_config["sign_off"] || "Best regards"
      examples = style_config["examples"] || []

      prompt = <<~PROMPT
        You are an email draft generator. Write a reply following the communication style rules below.

        Style: #{style_name}
        Language: #{language} (if "auto", match the language of the incoming email)

        Rules:
      PROMPT

      rules.each do |rule|
        prompt += "- #{rule}\n"
      end

      prompt += "\nSign-off: #{sign_off}\n"

      if examples.any?
        prompt += "\nExamples:\n"
        examples.each do |example|
          prompt += "Context: #{example['context']}\n"
          prompt += "Input: #{example['input']}\n"
          prompt += "Draft: #{example['draft']}\n\n"
        end
      end

      prompt += <<~GUIDELINES

        Guidelines:
        - Match the language of the incoming email unless the style specifies otherwise
        - Keep drafts concise — match the length and energy of the sender
        - Include specific details from the original email
        - Never fabricate information. Flag missing context with [TODO: ...]
        - Use the sign_off from the style config
        - Do NOT include the subject line in the body
        - Output ONLY the draft text, nothing else
      GUIDELINES

      prompt
    end

    def build_user_message
      # Extract thread information
      first_message = @thread_messages.first
      parser = Gmail::MessageParser.new(first_message)

      from_info = parser.from
      sender_email = from_info[:email]
      sender_name = from_info[:name].presence || sender_email
      subject = parser.subject

      # Combine thread messages
      thread_body = @thread_messages.map do |msg|
        msg_parser = Gmail::MessageParser.new(msg)
        msg_from = msg_parser.from
        from_display = msg_from[:name].present? ? "#{msg_from[:name]} <#{msg_from[:email]}>" : msg_from[:email]
        body = msg_parser.body
        "From: #{from_display}\n#{body}"
      end.join("\n\n---\n\n")

      truncated_thread = thread_body.truncate(MAX_THREAD_BODY_LENGTH, omission: "\n\n[... thread truncated ...]")

      message = <<~MESSAGE
        From: #{sender_name} <#{sender_email}>
        Subject: #{subject}

        Thread:
        #{truncated_thread}
      MESSAGE

      # Add related context if available
      if @related_context.present?
        message += "\n\n#{@related_context}\n"
      end

      # Add user instructions if present (for rework/manual draft)
      if @user_instructions.present?
        message += <<~INSTRUCTIONS

          --- User instructions ---
          #{@user_instructions}
          --- End instructions ---

          Incorporate these instructions into the draft. They guide WHAT to say,
          not HOW to say it. The draft should still follow the style rules.
        INSTRUCTIONS
      end

      message
    end

    def track_llm_success(system_prompt, user_message, result, latency_ms)
      content = result.dig(:choices, 0, :message, :content)
      usage = result[:usage] || {}

      call_type = @user_instructions.present? ? "rework" : "draft"

      LlmCall.create!(
        user: @user,
        gmail_thread_id: @gmail_thread_id,
        call_type: call_type,
        model: extract_model(result),
        system_prompt: system_prompt,
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

    def track_llm_error(system_prompt, user_message, error)
      call_type = @user_instructions.present? ? "rework" : "draft"

      LlmCall.create!(
        user: @user,
        gmail_thread_id: @gmail_thread_id,
        call_type: call_type,
        model: "unknown",
        system_prompt: system_prompt,
        user_message: user_message,
        error: "#{error.class}: #{error.message}"
      )
    rescue => e
      Rails.logger.error "Failed to track LLM error: #{e.class} - #{e.message}"
    end

    def extract_model(result)
      result[:model] || ENV["LLM_QUALITY_MODEL"] || "unknown"
    end
  end
end
