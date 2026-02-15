# frozen_string_literal: true

# Background job that handles email cleanup and archival
#
# Triggered when:
# - User applies the "Done" label (action=done)
# - A message is deleted (sent detection, action=check_sent)
class CleanupJob < ApplicationJob
  queue_as :default

  # Process cleanup action for a specific email
  #
  # @param user_id [Integer] User ID
  # @param gmail_thread_id [String] Gmail thread ID
  # @param action [String] "done" or "check_sent"
  def perform(user_id, gmail_thread_id, action:)
    user = User.find(user_id)
    email = Email.find_by!(user: user, gmail_thread_id: gmail_thread_id)
    gmail_client = Gmail::Client.new(user)

    case action
    when "done"
      handle_done(email, user, gmail_client)
      Rails.logger.info "Successfully archived thread #{gmail_thread_id}"
    when "check_sent"
      handle_sent_detection(email, user, gmail_client)
      Rails.logger.info "Successfully processed sent detection for thread #{gmail_thread_id}"
    else
      Rails.logger.error "Unknown cleanup action: #{action}"
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "CleanupJob: Record not found - #{e.message}"
  rescue => e
    Rails.logger.error "CleanupJob failed for thread #{gmail_thread_id}, action=#{action}: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  # Cleanup old completed/failed jobs
  # @param days [Integer] Number of days to keep (default 7)
  def self.cleanup_old_jobs(days = 7)
    cutoff_date = days.days.ago
    deleted_count = Job.where(status: %w[completed failed])
                       .where("completed_at < ?", cutoff_date)
                       .delete_all

    Rails.logger.info "Cleaned up #{deleted_count} old jobs (older than #{days} days)"
    deleted_count
  end

  private

  # Handle the "Done" label action
  # Removes all AI labels and INBOX, archives the thread
  def handle_done(email, user, gmail_client)
    # Get all AI label IDs
    ai_label_keys = %w[needs_response outbox rework action_required payment_request fyi waiting]
    ai_label_ids = user.user_labels
                      .where(label_key: ai_label_keys)
                      .pluck(:gmail_label_id)

    # Fetch thread messages
    thread = gmail_client.get_thread(email.gmail_thread_id, format: "minimal")
    message_ids = (thread.messages || []).map(&:id)

    unless message_ids.empty?
      # Remove all AI labels and INBOX from all messages
      remove_label_ids = ai_label_ids + ["INBOX"]
      gmail_client.batch_modify_messages(
        message_ids,
        remove_label_ids: remove_label_ids
      )
    end

    # Update email status
    email.update!(
      status: "archived",
      acted_at: Time.current
    )

    # Log event
    EmailEvent.create!(
      user: user,
      gmail_thread_id: email.gmail_thread_id,
      event_type: "archived"
    )
  end

  # Handle sent detection
  # Checks if a draft was sent and updates status accordingly
  def handle_sent_detection(email, user, gmail_client)
    # Skip if no draft_id
    return unless email.draft_id.present?

    # Check if draft still exists
    draft_exists = false
    begin
      gmail_client.get_draft(email.draft_id)
      draft_exists = true
    rescue => e
      # Draft not found - it was likely sent
      Rails.logger.info "Draft #{email.draft_id} not found, assuming it was sent"
    end

    # If draft is gone, it was sent
    unless draft_exists
      # Remove Outbox label from all thread messages
      outbox_label_id = user.user_labels.find_by(label_key: "outbox")&.gmail_label_id

      if outbox_label_id
        thread = gmail_client.get_thread(email.gmail_thread_id, format: "minimal")
        message_ids = (thread.messages || []).map(&:id)

        unless message_ids.empty?
          gmail_client.batch_modify_messages(
            message_ids,
            remove_label_ids: [outbox_label_id]
          )
        end
      end

      # Update email status
      email.update!(
        status: "sent",
        acted_at: Time.current
      )

      # Log event
      EmailEvent.create!(
        user: user,
        gmail_thread_id: email.gmail_thread_id,
        event_type: "sent_detected",
        draft_id: email.draft_id
      )
    end
  end
end
