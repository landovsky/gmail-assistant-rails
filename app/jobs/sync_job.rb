# frozen_string_literal: true

# Background job that performs email sync for a user
# Can be scheduled periodically as a polling fallback
class SyncJob < ApplicationJob
  queue_as :default

  # Sync emails for a specific user
  def perform(user_id)
    user = User.find(user_id)
    Gmail::SyncEngine.new(user).sync!
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "SyncJob: User #{user_id} not found"
  rescue => e
    Rails.logger.error "SyncJob failed for user #{user_id}: #{e.class} - #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end

  # Sync all active users (for scheduled polling)
  def self.sync_all_users
    User.find_each do |user|
      SyncJob.perform_later(user.id)
    end
  end
end
