class AgentRun < ApplicationRecord
  # Associations
  belongs_to :user

  # Validations
  validates :gmail_thread_id, presence: true
  validates :profile, presence: true
  validates :status, presence: true, inclusion: {
    in: %w[running completed error max_iterations],
    message: "%{value} is not a valid status"
  }
end
