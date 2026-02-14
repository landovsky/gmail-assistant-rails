# frozen_string_literal: true

# Webhook receiver for Google Pub/Sub push notifications
class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:gmail]

  # POST /webhooks/gmail
  # Receives push notifications from Google Cloud Pub/Sub when Gmail changes occur
  def gmail
    # Decode the Pub/Sub message
    message_data = parse_pubsub_message

    return head :bad_request unless message_data

    # Extract email address from the message
    email_address = message_data["emailAddress"]
    history_id = message_data["historyId"]

    unless email_address && history_id
      Rails.logger.warn "Gmail webhook: missing emailAddress or historyId in message"
      return head :bad_request
    end

    # Find user by email
    user = User.find_by(email: email_address)

    unless user
      Rails.logger.warn "Gmail webhook: user not found for email #{email_address}"
      return head :not_found
    end

    Rails.logger.info "Gmail webhook received for user #{user.id}, history_id #{history_id}"

    # Enqueue sync job to process changes
    SyncJob.perform_later(user.id)

    head :ok
  rescue => e
    Rails.logger.error "Gmail webhook error: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    head :internal_server_error
  end

  private

  def parse_pubsub_message
    return nil unless params[:message]

    # Pub/Sub sends base64-encoded data
    data = params[:message][:data]
    return nil unless data

    # Decode and parse JSON
    decoded = Base64.decode64(data)
    JSON.parse(decoded)
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse Pub/Sub message: #{e.message}"
    nil
  rescue => e
    Rails.logger.error "Failed to decode Pub/Sub message: #{e.message}"
    nil
  end
end
