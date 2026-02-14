# frozen_string_literal: true

# Background job that classifies an individual email
#
# Runs the two-tier classification pipeline (rules + LLM) and applies
# Gmail labels based on the result.
class ClassifyJob < ApplicationJob
  queue_as :default

  # Classify a specific email
  #
  # @param user_id [Integer] User ID
  # @param gmail_thread_id [String] Gmail thread ID
  # @param gmail_message_id [String] Gmail message ID
  def perform(user_id, gmail_thread_id, gmail_message_id)
    user = User.find(user_id)
    email = Email.find_by!(user: user, gmail_thread_id: gmail_thread_id)

    # Fetch the message from Gmail
    gmail_client = Gmail::Client.new(user)
    message = gmail_client.get_message(gmail_message_id)

    # Run classification pipeline
    Classification::Classifier.classify_and_label(
      email: email,
      message: message
    )

    Rails.logger.info "Successfully classified email #{gmail_thread_id} as #{email.classification}"
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.warn "ClassifyJob: Record not found - #{e.message}"
  rescue => e
    Rails.logger.error "ClassifyJob failed for thread #{gmail_thread_id}: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
