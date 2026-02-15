module Jobs
  class ManualDraftHandler < BaseHandler
    SCISSORS_MARKER = "\u2702\uFE0F" # ✂️

    def perform
      message_id = @payload["message_id"]

      # Fetch message to get thread_id
      message = @gmail_client.get_message(message_id)
      thread_id = message.thread_id
      headers = Gmail::Client.parse_headers(message)
      sender = Gmail::Client.parse_sender(headers["From"])

      # Check if already drafted
      email = Email.find_by(user: @user, gmail_thread_id: thread_id)
      if email&.status == "drafted"
        Rails.logger.info("ManualDraftHandler: thread #{thread_id} already drafted, skipping")
        return
      end

      # Fetch full thread
      thread_data = @gmail_client.get_thread_data(thread_id)
      thread_body = thread_data&.dig(:body) || ""

      # Look for user's notes draft in the thread
      user_instructions = extract_notes_draft(thread_id)

      # Create or update database record
      subject = headers["Subject"] || ""
      if email
        email.update!(classification: "needs_response", status: "pending")
      else
        email = Email.create!(
          user: @user,
          gmail_thread_id: thread_id,
          gmail_message_id: message_id,
          sender_email: sender[:email],
          sender_name: sender[:name],
          subject: subject,
          classification: "needs_response",
          confidence: "high",
          status: "pending",
          message_count: thread_data&.dig(:message_count) || 1
        )
      end

      # Gather related context (fail-safe)
      llm_gateway = Llm::Gateway.new(user: @user)
      context_gatherer = Drafting::ContextGatherer.new(llm_gateway: llm_gateway, gmail_client: @gmail_client)
      related_context = context_gatherer.gather(
        sender_email: email.sender_email,
        subject: email.subject,
        body: thread_body,
        gmail_thread_id: thread_id
      )

      # Generate draft
      draft_generator = Drafting::DraftGenerator.new(llm_gateway: llm_gateway)
      draft_body = draft_generator.generate(
        sender_name: email.sender_name,
        sender_email: email.sender_email,
        subject: email.subject,
        thread_body: thread_body,
        resolved_style: email.resolved_style || "business",
        detected_language: email.detected_language || "auto",
        related_context: related_context,
        user_instructions: user_instructions
      )

      # Trash notes draft and stale AI drafts
      trash_thread_drafts(thread_id)

      # Get message headers for In-Reply-To
      last_message = thread_data&.dig(:messages)&.last
      last_headers = last_message ? Gmail::Client.parse_headers(last_message) : {}
      message_id_header = last_headers["Message-ID"]

      # Create new Gmail draft
      new_draft = @gmail_client.create_draft(
        to: email.sender_email,
        subject: email.subject,
        body: draft_body,
        thread_id: thread_id,
        in_reply_to: message_id_header,
        references: message_id_header
      )

      new_draft_id = new_draft&.id

      # Move labels: Needs Response -> Outbox
      nr_label = @user.user_labels.find_by(label_key: "needs_response")
      outbox_label = @user.user_labels.find_by(label_key: "outbox")

      add_ids = outbox_label ? [outbox_label.gmail_label_id] : []
      remove_ids = nr_label ? [nr_label.gmail_label_id] : []

      @gmail_client.modify_thread(thread_id: thread_id, add_label_ids: add_ids, remove_label_ids: remove_ids)

      # Update database
      email.update!(status: "drafted", draft_id: new_draft_id)

      # Log event
      EmailEvent.create!(
        user: @user,
        gmail_thread_id: thread_id,
        event_type: "manual_draft_created",
        detail: "Manual draft created for thread #{thread_id}"
      )
    end

    private

    def extract_notes_draft(thread_id)
      drafts_response = @gmail_client.list_drafts
      return nil unless drafts_response&.drafts

      drafts_response.drafts.each do |draft|
        draft_detail = @gmail_client.get_draft(draft.id)
        next unless draft_detail&.message&.thread_id == thread_id

        body = Gmail::Client.extract_body(draft_detail.message.payload)
        next if body.blank?

        # Extract instructions from above the scissors marker
        if body.include?(SCISSORS_MARKER)
          instruction = body.split(SCISSORS_MARKER, 2).first.to_s.strip
          return instruction.presence
        else
          # Treat entire draft body as instructions
          return body.strip.presence
        end
      end

      nil
    rescue StandardError => e
      Rails.logger.warn("ManualDraftHandler: failed to extract notes draft: #{e.message}")
      nil
    end

    def trash_thread_drafts(thread_id)
      drafts_response = @gmail_client.list_drafts
      return unless drafts_response&.drafts

      drafts_response.drafts.each do |draft|
        draft_detail = @gmail_client.get_draft(draft.id)
        next unless draft_detail&.message&.thread_id == thread_id

        @gmail_client.delete_draft(draft.id)
      end
    rescue StandardError => e
      Rails.logger.warn("ManualDraftHandler: failed to trash drafts: #{e.message}")
    end
  end
end
