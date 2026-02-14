class Email < ApplicationRecord
  # Associations
  belongs_to :user
  has_many :email_events, primary_key: :gmail_thread_id, foreign_key: :gmail_thread_id, dependent: :destroy
  has_many :llm_calls, primary_key: :gmail_thread_id, foreign_key: :gmail_thread_id, dependent: :destroy
  has_many :agent_runs, primary_key: :gmail_thread_id, foreign_key: :gmail_thread_id, dependent: :destroy

  # Validations
  validates :gmail_thread_id, presence: true, uniqueness: { scope: :user_id }
  validates :gmail_message_id, presence: true
  validates :sender_email, presence: true
  validates :classification, presence: true, inclusion: {
    in: %w[needs_response action_required payment_request fyi waiting],
    message: "%{value} is not a valid classification"
  }
  validates :confidence, inclusion: {
    in: %w[high medium low],
    message: "%{value} is not a valid confidence level"
  }
  validates :status, inclusion: {
    in: %w[pending drafted rework_requested sent skipped archived],
    message: "%{value} is not a valid status"
  }
end
