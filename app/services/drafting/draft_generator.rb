module Drafting
  class DraftGenerator
    BODY_TRUNCATION = 3000

    def initialize(llm_gateway:, styles_config: nil)
      @llm_gateway = llm_gateway
      @styles_config = styles_config || load_styles_config
    end

    def generate(sender_name:, sender_email:, subject:, thread_body:, resolved_style:, detected_language: "auto", related_context: "", user_instructions: nil)
      system_prompt = build_system_prompt(resolved_style, detected_language)
      user_message = build_user_message(
        sender_name: sender_name,
        sender_email: sender_email,
        subject: subject,
        thread_body: thread_body,
        related_context: related_context,
        user_instructions: user_instructions
      )

      response = @llm_gateway.draft(user_message, system_prompt: system_prompt)

      if response.nil?
        "[ERROR: Draft generation failed — LLM returned no response]"
      else
        wrap_with_marker(response)
      end
    rescue StandardError => e
      "[ERROR: Draft generation failed — #{e.message}]"
    end

    private

    def build_system_prompt(style_name, detected_language)
      style = (@styles_config["styles"] || {})[style_name] || (@styles_config["styles"] || {})["business"] || {}

      rules = (style["rules"] || []).map { |r| "- #{r}" }.join("\n")
      sign_off = style["sign_off"] || ""
      language = style["language"] || detected_language || "auto"

      examples_block = (style["examples"] || []).map do |ex|
        <<~EX
          Context: #{ex['context']}
          Input: #{ex['input']}
          Draft: #{ex['draft']}
        EX
      end.join("\n")

      prompt = <<~PROMPT
        You are an email draft generator. Write a reply following the communication style rules below.

        Style: #{style_name}
        Language: #{language} (if "auto", match the language of the incoming email)

        Rules:
        #{rules}

        Sign-off: #{sign_off}
      PROMPT

      if examples_block.present?
        prompt += "\nExamples:\n#{examples_block}\n"
      end

      prompt += <<~GUIDELINES

        Guidelines:
        - Match the language of the incoming email unless the style specifies otherwise
        - Keep drafts concise - match the length and energy of the sender
        - Include specific details from the original email
        - Never fabricate information. Flag missing context with [TODO: ...]
        - Use the sign_off from the style config
        - Do NOT include the subject line in the body
        - Output ONLY the draft text, nothing else
      GUIDELINES

      prompt
    end

    def build_user_message(sender_name:, sender_email:, subject:, thread_body:, related_context:, user_instructions:)
      msg = <<~MSG
        From: #{sender_name} <#{sender_email}>
        Subject: #{subject}

        Thread:
        #{thread_body.to_s[0, BODY_TRUNCATION]}
      MSG

      if related_context.present?
        msg += "\n#{related_context}\n"
      end

      if user_instructions.present?
        msg += <<~INSTR

          --- User instructions ---
          #{user_instructions}
          --- End instructions ---

          Incorporate these instructions into the draft. They guide WHAT to say,
          not HOW to say it. The draft should still follow the style rules.
        INSTR
      end

      msg
    end

    def wrap_with_marker(draft_text)
      "\n\n✂️\n\n#{draft_text}"
    end

    def load_styles_config
      YAML.load_file(Rails.root.join("config", "communication_styles.yml")) || {}
    rescue StandardError
      {}
    end
  end
end
