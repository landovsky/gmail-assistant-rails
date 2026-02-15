class Job < ApplicationRecord
  belongs_to :user

  JOB_TYPES = %w[sync classify draft cleanup rework manual_draft agent_process].freeze
  STATUSES = %w[pending running completed failed].freeze

  validates :job_type, presence: true, inclusion: { in: JOB_TYPES }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending") }
  scope :running, -> { where(status: "running") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }

  def parsed_payload
    JSON.parse(payload || "{}")
  rescue JSON::ParserError
    {}
  end

  def retryable?
    attempts < max_attempts
  end

  # Atomic job claiming - returns the claimed job or nil
  def self.claim_next
    job = pending.where("attempts < max_attempts").order(:created_at).lock("FOR UPDATE").first
    return nil unless job

    job.update!(status: "running", attempts: job.attempts + 1, started_at: Time.current)
    job
  rescue ActiveRecord::StatementInvalid
    # SQLite doesn't support FOR UPDATE, use optimistic approach
    job = pending.where("attempts < max_attempts").order(:created_at).first
    return nil unless job

    updated = Job.where(id: job.id, status: "pending")
                 .update_all(status: "running", attempts: job.attempts + 1, started_at: Time.current)
    updated > 0 ? job.reload : nil
  end

  def complete!
    update!(status: "completed", completed_at: Time.current)
  end

  def fail!(error_msg)
    if retryable?
      update!(status: "pending", error_message: error_msg)
    else
      update!(status: "failed", error_message: error_msg, completed_at: Time.current)
    end
  end
end
