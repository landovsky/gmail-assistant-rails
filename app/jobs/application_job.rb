class ApplicationJob < ActiveJob::Base
  include JobTracker

  # Retry configuration for all jobs
  # Maximum 3 attempts as per spec (attempts counter starts at 0)
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # Discard jobs for deleted users
  discard_on ActiveRecord::RecordNotFound do |job, error|
    Rails.logger.warn "Job #{job.class.name} discarded: #{error.message}"
  end

  # Log job lifecycle events
  before_enqueue do |job|
    log_job_event(job, "enqueued")
  end

  before_perform do |job|
    log_job_event(job, "started")
  end

  after_perform do |job|
    log_job_event(job, "completed")
  end

  rescue_from(StandardError) do |exception|
    # Log the error before retry/failure
    Rails.logger.error "Job #{self.class.name} error: #{exception.class} - #{exception.message}"
    Rails.logger.error exception.backtrace.join("\n")

    # Re-raise to trigger retry mechanism
    raise exception
  end

  private

  def log_job_event(job, event)
    Rails.logger.info "Job #{job.class.name} #{event}: #{job.job_id}"
  end
end
