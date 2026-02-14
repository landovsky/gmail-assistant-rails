# frozen_string_literal: true

# Background job that handles rework requests for existing drafts
#
# Triggered when user applies the "Rework" label to a thread in Gmail.
# Extracts user instructions, generates a new draft, and manages rework count limits.
class ReworkJob < ApplicationJob
  queue_as :default

  # Process a rework request for a specific email
  #
  # @param user_id [Integer] User ID
  # @param gmail_thread_id [String] Gmail thread ID
  def perform(user_id, gmail_thread_id)
    user = User.find(user_id)
    email = Email.find_by!(user: user, gmail_thread_id: gmail_thread_id)

    success = Drafting::ReworkHandler.handle(
      email: email,
      user: user
    )

    if success
      Rails.logger.info "Successfully reworked draft for thread #{gmail_thread_id}"
    else
      Rails.logger.warn "Rework failed or limit reached for thread #{gmail_thread_id}"
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "ReworkJob: Record not found - #{e.message}"
  rescue => e
    Rails.logger.error "ReworkJob failed for thread #{gmail_thread_id}: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
