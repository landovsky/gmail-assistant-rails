# frozen_string_literal: true

module Gmail
  # Manages Gmail Pub/Sub watch lifecycle
  # Registers watches for push notifications and handles renewal
  class WatchManager
    WATCH_EXPIRATION_DAYS = 7 # Gmail watches expire after 7 days
    RENEW_BEFORE_HOURS = 24 # Renew 24 hours before expiration

    attr_reader :user, :client

    def initialize(user)
      @user = user
      @client = Gmail::Client.new(user)
    end

    # Register or renew a Pub/Sub watch for this user
    def setup_watch!
      sync_state = user.sync_state || user.create_sync_state!(last_history_id: "0")

      # Check if watch needs renewal
      if watch_valid?(sync_state)
        Rails.logger.info "Watch still valid for user #{user.id}, skipping setup"
        return
      end

      # Get Pub/Sub topic from configuration
      topic_name = pubsub_topic_name
      unless topic_name
        Rails.logger.error "Pub/Sub topic not configured, cannot setup watch for user #{user.id}"
        return
      end

      # Get label IDs to watch
      label_ids = watch_label_ids

      Rails.logger.info "Setting up Gmail watch for user #{user.id} with topic #{topic_name}"

      # Register watch
      response = client.watch(
        topic_name,
        label_ids: label_ids,
        label_filter_behavior: "include"
      )

      # Update sync state with watch info
      expiration_time = Time.at(response.expiration / 1000.0) # Gmail returns milliseconds
      sync_state.update!(
        watch_expiration: expiration_time,
        watch_resource_id: response.history_id.to_s
      )

      Rails.logger.info "Watch setup complete for user #{user.id}, expires at #{expiration_time}"
    rescue => e
      Rails.logger.error "Failed to setup watch for user #{user.id}: #{e.class} - #{e.message}"
      raise
    end

    # Stop the current watch for this user
    def stop_watch!
      Rails.logger.info "Stopping watch for user #{user.id}"

      client.stop_watch

      # Clear watch info from sync state
      if sync_state = user.sync_state
        sync_state.update!(
          watch_expiration: nil,
          watch_resource_id: nil
        )
      end

      Rails.logger.info "Watch stopped for user #{user.id}"
    rescue => e
      Rails.logger.error "Failed to stop watch for user #{user.id}: #{e.class} - #{e.message}"
      raise
    end

    # Renew watches for all users that are expiring soon
    def self.renew_expiring_watches
      cutoff = RENEW_BEFORE_HOURS.hours.from_now

      SyncState.where("watch_expiration IS NOT NULL AND watch_expiration < ?", cutoff).find_each do |sync_state|
        user = sync_state.user
        Rails.logger.info "Renewing watch for user #{user.id}"

        begin
          WatchManager.new(user).setup_watch!
        rescue => e
          Rails.logger.error "Failed to renew watch for user #{user.id}: #{e.class} - #{e.message}"
        end
      end
    end

    private

    def watch_valid?(sync_state)
      return false unless sync_state.watch_expiration

      # Watch is valid if it doesn't expire within the renewal window
      sync_state.watch_expiration > RENEW_BEFORE_HOURS.hours.from_now
    end

    def pubsub_topic_name
      # Get from Rails configuration
      # Format: projects/{project-id}/topics/{topic-name}
      Rails.application.config.gmail_pubsub_topic
    rescue
      nil
    end

    def watch_label_ids
      # Watch INBOX and key action labels
      label_ids = ["INBOX"]

      # Add AI labels
      %w[needs_response rework done].each do |label_key|
        if label_id = user_label_id(label_key)
          label_ids << label_id
        end
      end

      label_ids
    end

    def user_label_id(label_key)
      user.user_labels.find_by(label_key: label_key)&.gmail_label_id
    end
  end
end
