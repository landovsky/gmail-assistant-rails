class EmailEvent < ApplicationRecord
  belongs_to :user

  EVENT_TYPES = %w[
    classified label_added label_removed draft_created draft_trashed
    draft_reworked sent_detected archived rework_limit_reached
    waiting_retriaged error
  ].freeze

  validates :gmail_thread_id, presence: true
  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
end
