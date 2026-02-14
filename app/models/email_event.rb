class EmailEvent < ApplicationRecord
  # Associations
  belongs_to :user

  # Validations
  validates :gmail_thread_id, presence: true
  validates :event_type, presence: true, inclusion: {
    in: %w[classified label_added label_removed draft_created draft_trashed draft_reworked sent_detected archived rework_limit_reached waiting_retriaged error],
    message: "%{value} is not a valid event type"
  }
end
