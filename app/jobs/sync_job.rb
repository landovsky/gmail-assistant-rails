# frozen_string_literal: true

# Background job that performs email sync for a user
# Can be scheduled periodically as a polling fallback
class SyncJob < ApplicationJob
  queue_as :default

  # Sync emails for a specific user
  # @param user_id [Integer] User ID
  # @param force_full [Boolean] Force a full sync instead of incremental (default: false)
  def perform(user_id, force_full: false)
    user = User.find(user_id)
    sync_engine = Gmail::SyncEngine.new(user)

    if force_full
      sync_state = user.sync_state || user.create_sync_state!(last_history_id: "0")
      sync_engine.send(:full_sync!, sync_state)
      Rails.logger.info "Completed full sync for user #{user_id}"
    else
      sync_engine.sync!
      Rails.logger.info "Completed incremental sync for user #{user_id}"
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "SyncJob: User #{user_id} not found"
  rescue => e
    Rails.logger.error "SyncJob failed for user #{user_id}: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  # Sync all active users (for scheduled polling)
  # Uses incremental sync via History API
  def self.sync_all_users
    User.find_each do |user|
      SyncJob.perform_later(user.id)
    end
  end

  # Full sync for all active users (for scheduled catch-up scan)
  # Forces a full scan of inbox to catch any missed emails
  def self.full_sync_all_users
    User.find_each do |user|
      SyncJob.perform_later(user.id, force_full: true)
    end
  end
end
