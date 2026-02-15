module Jobs
  class DraftHandler < BaseHandler
    def perform
      thread_id = @payload["thread_id"]
      message_id = @payload["message_id"]

      email = Email.find_by(user: @user, gmail_thread_id: thread_id)
      unless email
        Rails.logger.info("DraftHandler: no email record for thread #{thread_id}, skipping")
        return
      end

      unless email.status == "pending"
        Rails.logger.info("DraftHandler: email status is #{email.status}, skipping")
        return
      end

      # Fetch full thread
      thread_data = @gmail_client.get_thread_data(thread_id)
      thread_body = thread_data&.dig(:body) || ""

      # Gather related context (fail-safe)
      llm_gateway = Llm::Gateway.new(user: @user)
      context_gatherer = Drafting::ContextGatherer.new(llm_gateway: llm_gateway, gmail_client: @gmail_client)
      related_context = context_gatherer.gather(
        sender_email: email.sender_email,
        subject: email.subject,
        body: thread_body,
        gmail_thread_id: thread_id
      )

      # Generate draft via LLM
      draft_generator = Drafting::DraftGenerator.new(llm_gateway: llm_gateway)
      draft_body = draft_generator.generate(
        sender_name: email.sender_name,
        sender_email: email.sender_email,
        subject: email.subject,
        thread_body: thread_body,
        resolved_style: email.resolved_style || "business",
        detected_language: email.detected_language || "auto",
        related_context: related_context
      )

      # Trash stale drafts from previous attempts
      trash_thread_drafts(thread_id, exclude_draft_id: nil)

      # Get message headers for In-Reply-To
      first_message = thread_data&.dig(:messages)&.last
      headers = first_message ? Gmail::Client.parse_headers(first_message) : {}
      message_id_header = headers["Message-ID"]

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

      # Move labels: remove Needs Response, add Outbox
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
        event_type: "draft_created",
        detail: "Draft created for thread #{thread_id}"
      )
    end

    private

    def trash_thread_drafts(thread_id, exclude_draft_id: nil)
      drafts_response = @gmail_client.list_drafts
      return unless drafts_response&.drafts

      drafts_response.drafts.each do |draft|
        next if draft.id == exclude_draft_id

        draft_detail = @gmail_client.get_draft(draft.id)
        next unless draft_detail&.message&.thread_id == thread_id

        @gmail_client.delete_draft(draft.id)
      end
    rescue StandardError => e
      Rails.logger.warn("DraftHandler: failed to trash stale drafts: #{e.message}")
    end
  end
end
