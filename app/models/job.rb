class Job < ApplicationRecord
  # Associations
  belongs_to :user

  # Validations
  validates :job_type, presence: true, inclusion: {
    in: %w[sync classify draft cleanup rework manual_draft agent_process],
    message: "%{value} is not a valid job type"
  }
  validates :status, inclusion: {
    in: %w[pending running completed failed],
    message: "%{value} is not a valid status"
  }
end
