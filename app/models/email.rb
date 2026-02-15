class Email < ApplicationRecord
  belongs_to :user

  CLASSIFICATIONS = %w[needs_response action_required payment_request fyi waiting].freeze
  CONFIDENCES = %w[high medium low].freeze
  STATUSES = %w[pending drafted rework_requested sent skipped archived].freeze

  validates :gmail_thread_id, presence: true, uniqueness: { scope: :user_id }
  validates :gmail_message_id, presence: true
  validates :sender_email, presence: true
  validates :classification, presence: true, inclusion: { in: CLASSIFICATIONS }
  validates :confidence, inclusion: { in: CONFIDENCES }
  validates :status, inclusion: { in: STATUSES }

  scope :by_classification, ->(c) { where(classification: c) }
  scope :by_status, ->(s) { where(status: s) }
  scope :needs_response, -> { by_classification("needs_response") }
  scope :pending, -> { by_status("pending") }
  scope :drafted, -> { by_status("drafted") }
  scope :active, -> { where.not(status: %w[sent archived skipped]) }
end
