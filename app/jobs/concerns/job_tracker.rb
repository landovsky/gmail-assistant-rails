# frozen_string_literal: true

# Concern for tracking job execution in the custom jobs table
# This provides application-level job tracking separate from the queue system
module JobTracker
  extend ActiveSupport::Concern

  class_methods do
    # Create a tracked job record and enqueue it
    # Returns the Job tracking record
    def enqueue_tracked(user:, job_type:, payload: {}, **job_args)
      # Create tracking record in custom jobs table
      job_record = Job.create!(
        user: user,
        job_type: job_type,
        payload: payload.to_json,
        status: "pending",
        attempts: 0,
        max_attempts: 3
      )

      # Enqueue the ActiveJob
      perform_later(**job_args)

      Rails.logger.info "Enqueued #{job_type} job for user #{user.id} (Job ##{job_record.id})"

      job_record
    end
  end
end
