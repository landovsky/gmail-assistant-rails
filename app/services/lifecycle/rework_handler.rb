module Lifecycle
  class ReworkHandler
    REWORK_LIMIT = 3
    SCISSORS_MARKER = "\u2702\uFE0F" # ✂️

    def initialize(draft_generator:, context_gatherer:, gmail_client: nil)
      @draft_generator = draft_generator
      @context_gatherer = context_gatherer
      @gmail_client = gmail_client
    end

    def handle(email:, user:)
      if email.rework_count >= REWORK_LIMIT
        handle_limit_reached(email: email, user: user)
        return
      end

      draft_body = fetch_current_draft(email)
      instruction = extract_instruction(draft_body)

      thread_data = @gmail_client&.get_thread(thread_id: email.gmail_thread_id)
      thread_body = thread_data&.dig(:body) || thread_data&.dig("body") || ""

      related_context = @context_gatherer.gather(
        sender_email: email.sender_email,
        subject: email.subject,
        body: thread_body,
        gmail_thread_id: email.gmail_thread_id
      )

      new_count = email.rework_count + 1

      new_draft_body = @draft_generator.generate(
        sender_name: email.sender_name,
        sender_email: email.sender_email,
        subject: email.subject,
        thread_body: thread_body,
        resolved_style: email.resolved_style,
        detected_language: email.detected_language,
        related_context: related_context,
        user_instructions: instruction
      )

      if new_count == REWORK_LIMIT
        warning = "⚠️ This is the last automatic rework. Further changes must be made manually.\n\n"
        new_draft_body = warning + new_draft_body
      end

      # Trash old draft
      @gmail_client&.trash_draft(draft_id: email.draft_id) if email.draft_id.present?

      # Create new draft
      new_draft_id = @gmail_client&.create_draft(
        thread_id: email.gmail_thread_id,
        body: new_draft_body,
        subject: "Re: #{email.subject}"
      )

      # Move labels
      if new_count == REWORK_LIMIT
        move_labels(user: user, email: email, from: "rework", to: "action_required")
      else
        move_labels(user: user, email: email, from: "rework", to: "outbox")
      end

      email.update!(
        rework_count: new_count,
        draft_id: new_draft_id,
        last_rework_instruction: instruction,
        status: new_count == REWORK_LIMIT ? "skipped" : "drafted"
      )

      log_event(user: user, email: email, event_type: "draft_reworked",
                detail: "Rework ##{new_count}: #{instruction.truncate(200)}")
    end

    private

    def handle_limit_reached(email:, user:)
      move_labels(user: user, email: email, from: "rework", to: "action_required")
      email.update!(status: "skipped")
      log_event(user: user, email: email, event_type: "rework_limit_reached",
                detail: "Rework count #{email.rework_count} >= limit #{REWORK_LIMIT}")
    end

    def fetch_current_draft(email)
      return "" unless email.draft_id.present? && @gmail_client
      @gmail_client.get_draft(draft_id: email.draft_id)&.dig(:body) || ""
    rescue StandardError => e
      Rails.logger.warn("Failed to fetch draft for rework: #{e.message}")
      ""
    end

    def extract_instruction(draft_body)
      return "(no specific instruction provided)" if draft_body.blank?

      parts = draft_body.split(SCISSORS_MARKER, 2)
      instruction = parts.first.to_s.strip

      instruction.present? ? instruction : "(no specific instruction provided)"
    end

    def move_labels(user:, email:, from:, to:)
      return unless @gmail_client

      from_label = user.user_labels.find_by(label_key: from)
      to_label = user.user_labels.find_by(label_key: to)

      @gmail_client.modify_thread(
        thread_id: email.gmail_thread_id,
        add_label_ids: [to_label&.gmail_label_id].compact,
        remove_label_ids: [from_label&.gmail_label_id].compact
      )
    rescue StandardError => e
      Rails.logger.warn("Failed to move labels: #{e.message}")
    end

    def log_event(user:, email:, event_type:, detail:)
      EmailEvent.create!(
        user: user,
        gmail_thread_id: email.gmail_thread_id,
        event_type: event_type,
        detail: detail
      )
    rescue StandardError => e
      Rails.logger.error("Failed to log event: #{e.message}")
    end
  end
end
