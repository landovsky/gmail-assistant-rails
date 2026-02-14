# frozen_string_literal: true

module Drafting
  # Handles rework requests for existing drafts
  #
  # Extracts user instructions from above the rework marker, generates a new draft
  # with those instructions, and manages the rework count limit (max 3).
  class ReworkHandler
    REWORK_MARKER = "✂️"
    MAX_REWORK_COUNT = 3
    LAST_REWORK_WARNING = "⚠️ This is the last automatic rework. Further changes must be made manually.\n\n"

    # Process a rework request
    #
    # @param email [Email] Email record
    # @param user [User] User making the request
    # @return [Boolean] True if rework succeeded, false if limit reached
    def self.handle(email:, user:)
      new(email: email, user: user).handle
    end

    def initialize(email:, user:)
      @email = email
      @user = user
      @gmail_client = Gmail::Client.new(user)
    end

    def handle
      # Check rework limit
      if @email.rework_count >= MAX_REWORK_COUNT
        handle_rework_limit_reached
        return false
      end

      # Fetch current draft
      unless @email.draft_id.present?
        Rails.logger.error "Rework requested but no draft_id found for email #{@email.gmail_thread_id}"
        return false
      end

      draft = fetch_current_draft
      return false unless draft

      # Extract instructions
      instruction = extract_instruction(draft)

      # Fetch full thread
      thread = @gmail_client.get_thread(@email.gmail_thread_id, format: "full")
      thread_messages = thread.messages || []

      # Gather related context (fail-safe)
      related_context = gather_context(thread_messages)

      # Generate new draft
      draft_text = generate_rework_draft(thread_messages, related_context, instruction)

      # Add warning if this is the 3rd rework
      if @email.rework_count == 2 # Will become 3 after this rework
        draft_text = LAST_REWORK_WARNING + draft_text
      end

      # Trash old draft
      trash_draft(@email.draft_id)

      # Create new draft
      new_draft_id = create_new_draft(thread_messages, draft_text)

      # Update labels
      update_labels_after_rework

      # Update email record
      @email.update!(
        rework_count: @email.rework_count + 1,
        draft_id: new_draft_id,
        last_rework_instruction: instruction,
        status: @email.rework_count == 2 ? "drafted" : "drafted" # Keep as drafted
      )

      # Log event
      EmailEvent.create!(
        user: @user,
        gmail_thread_id: @email.gmail_thread_id,
        event_type: "draft_reworked",
        draft_id: new_draft_id,
        detail: "Rework #{@email.rework_count + 1}/#{MAX_REWORK_COUNT}"
      )

      Rails.logger.info "Reworked draft for thread #{@email.gmail_thread_id} (count: #{@email.rework_count})"
      true
    rescue => e
      Rails.logger.error "Rework handler failed for thread #{@email.gmail_thread_id}: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      false
    end

    private

    def handle_rework_limit_reached
      # Move labels from Rework → Action Required
      rework_label_id = @user.user_labels.find_by(label_key: "rework")&.gmail_label_id
      action_required_label_id = @user.user_labels.find_by(label_key: "action_required")&.gmail_label_id

      if rework_label_id && action_required_label_id
        thread = @gmail_client.get_thread(@email.gmail_thread_id, format: "minimal")
        message_ids = (thread.messages || []).map(&:id)

        unless message_ids.empty?
          @gmail_client.batch_modify_messages(
            message_ids,
            remove_label_ids: [rework_label_id],
            add_label_ids: [action_required_label_id]
          )
        end
      end

      # Update email status
      @email.update!(status: "skipped")

      # Log event
      EmailEvent.create!(
        user: @user,
        gmail_thread_id: @email.gmail_thread_id,
        event_type: "rework_limit_reached",
        detail: "Maximum rework count (#{MAX_REWORK_COUNT}) reached"
      )

      Rails.logger.warn "Rework limit reached for thread #{@email.gmail_thread_id}"
    end

    def fetch_current_draft
      @gmail_client.get_draft(@email.draft_id)
    rescue => e
      Rails.logger.error "Failed to fetch draft #{@email.draft_id}: #{e.class} - #{e.message}"
      nil
    end

    def extract_instruction(draft)
      # Extract body from draft message
      message = draft.message
      parser = Gmail::MessageParser.new(message)
      body = parser.body

      # Split on marker
      parts = body.split(REWORK_MARKER, 2)

      if parts.length == 2
        instruction = parts[0].strip
        return instruction if instruction.present?
      end

      "(no specific instruction provided)"
    end

    def gather_context(thread_messages)
      first_message = thread_messages.first
      parser = Gmail::MessageParser.new(first_message)

      from_info = parser.from
      sender_email = from_info[:email]
      subject = parser.subject
      body = parser.body

      Drafting::ContextGatherer.gather(
        sender_email: sender_email,
        subject: subject,
        body: body,
        current_thread_id: @email.gmail_thread_id,
        user: @user,
        gmail_client: @gmail_client
      )
    end

    def generate_rework_draft(thread_messages, related_context, instruction)
      Drafting::DraftGenerator.generate(
        email: @email,
        thread_messages: thread_messages,
        related_context: related_context,
        user_instructions: instruction,
        user: @user,
        gmail_thread_id: @email.gmail_thread_id
      )
    end

    def trash_draft(draft_id)
      @gmail_client.delete_draft(draft_id)
    rescue => e
      Rails.logger.warn "Failed to trash draft #{draft_id}: #{e.class} - #{e.message}"
    end

    def create_new_draft(thread_messages, draft_text)
      first_message = thread_messages.first
      parser = Gmail::MessageParser.new(first_message)

      from_info = parser.from
      to = from_info[:email]
      subject = parser.subject
      in_reply_to = parser.header("Message-ID")

      message_object = Gmail::DraftBuilder.new(
        user_email: @user.email,
        to: to,
        subject: subject,
        body: draft_text,
        thread_id: @email.gmail_thread_id,
        in_reply_to: in_reply_to
      ).build

      draft = @gmail_client.create_draft(message_object)
      draft.id
    end

    def update_labels_after_rework
      rework_label_id = @user.user_labels.find_by(label_key: "rework")&.gmail_label_id
      outbox_label_id = @user.user_labels.find_by(label_key: "outbox")&.gmail_label_id
      action_required_label_id = @user.user_labels.find_by(label_key: "action_required")&.gmail_label_id

      # If this is the 3rd rework, move to Action Required instead of Outbox
      if @email.rework_count == 2
        add_label = action_required_label_id
      else
        add_label = outbox_label_id
      end

      if rework_label_id && add_label
        thread = @gmail_client.get_thread(@email.gmail_thread_id, format: "minimal")
        message_ids = (thread.messages || []).map(&:id)

        unless message_ids.empty?
          @gmail_client.batch_modify_messages(
            message_ids,
            remove_label_ids: [rework_label_id],
            add_label_ids: [add_label]
          )
        end
      end
    end
  end
end
