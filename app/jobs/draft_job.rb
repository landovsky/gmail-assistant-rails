# frozen_string_literal: true

# Background job that generates an AI draft reply for an email
#
# Runs when an email is classified as needs_response. Fetches the thread,
# gathers context, generates a draft using LLM, and creates a Gmail draft.
class DraftJob < ApplicationJob
  queue_as :default

  REWORK_MARKER = "✂️"

  # Generate a draft for a specific email
  #
  # @param user_id [Integer] User ID
  # @param gmail_thread_id [String] Gmail thread ID
  def perform(user_id, gmail_thread_id)
    user = User.find(user_id)
    email = Email.find_by!(user: user, gmail_thread_id: gmail_thread_id)

    # Verify email is in pending status
    unless email.status == "pending"
      Rails.logger.info "Skipping draft for thread #{gmail_thread_id} - status is #{email.status}"
      return
    end

    gmail_client = Gmail::Client.new(user)

    # Fetch full thread
    thread = gmail_client.get_thread(gmail_thread_id, format: "full")
    thread_messages = thread.messages || []

    if thread_messages.empty?
      Rails.logger.error "No messages found in thread #{gmail_thread_id}"
      return
    end

    # Gather related context (fail-safe)
    related_context = gather_context(email, thread_messages, user, gmail_client)

    # Generate draft
    draft_text = generate_draft(email, thread_messages, related_context, user, gmail_thread_id)

    # Trash any stale drafts
    trash_stale_drafts(email, gmail_client)

    # Create Gmail draft
    draft_id = create_gmail_draft(email, thread_messages, draft_text, user, gmail_client)

    # Update labels: remove Needs Response, add Outbox
    update_labels(email, user, gmail_client)

    # Update email record
    email.update!(
      status: "drafted",
      draft_id: draft_id,
      drafted_at: Time.current
    )

    # Log event
    EmailEvent.create!(
      user: user,
      gmail_thread_id: gmail_thread_id,
      event_type: "draft_created",
      draft_id: draft_id
    )

    Rails.logger.info "Successfully created draft for thread #{gmail_thread_id}"
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "DraftJob: Record not found - #{e.message}"
  rescue => e
    Rails.logger.error "DraftJob failed for thread #{gmail_thread_id}: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  private

  def gather_context(email, thread_messages, user, gmail_client)
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
      current_thread_id: email.gmail_thread_id,
      user: user,
      gmail_client: gmail_client
    )
  end

  def generate_draft(email, thread_messages, related_context, user, gmail_thread_id)
    Drafting::DraftGenerator.generate(
      email: email,
      thread_messages: thread_messages,
      related_context: related_context,
      user_instructions: nil,
      user: user,
      gmail_thread_id: gmail_thread_id
    )
  end

  def trash_stale_drafts(email, gmail_client)
    return unless email.draft_id.present?

    begin
      gmail_client.delete_draft(email.draft_id)
      Rails.logger.info "Trashed stale draft #{email.draft_id}"

      EmailEvent.create!(
        user: email.user,
        gmail_thread_id: email.gmail_thread_id,
        event_type: "draft_trashed",
        draft_id: email.draft_id,
        detail: "Stale draft from previous attempt"
      )
    rescue => e
      Rails.logger.warn "Failed to trash stale draft #{email.draft_id}: #{e.class} - #{e.message}"
    end
  end

  def create_gmail_draft(email, thread_messages, draft_text, user, gmail_client)
    first_message = thread_messages.first
    parser = Gmail::MessageParser.new(first_message)

    from_info = parser.from
    to = from_info[:email]
    subject = parser.subject
    in_reply_to = parser.header("Message-ID")

    message_object = Gmail::DraftBuilder.new(
      user_email: user.email,
      to: to,
      subject: subject,
      body: draft_text,
      thread_id: email.gmail_thread_id,
      in_reply_to: in_reply_to
    ).build

    draft = gmail_client.create_draft(message_object)
    draft.id
  end

  def update_labels(email, user, gmail_client)
    needs_response_label_id = user.user_labels.find_by(label_key: "needs_response")&.gmail_label_id
    outbox_label_id = user.user_labels.find_by(label_key: "outbox")&.gmail_label_id

    if needs_response_label_id && outbox_label_id
      thread = gmail_client.get_thread(email.gmail_thread_id, format: "minimal")
      message_ids = (thread.messages || []).map(&:id)

      unless message_ids.empty?
        gmail_client.batch_modify_messages(
          message_ids,
          remove_label_ids: [needs_response_label_id],
          add_label_ids: [outbox_label_id]
        )
      end
    end
  end
end
