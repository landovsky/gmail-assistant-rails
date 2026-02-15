class UserLabel < ApplicationRecord
  belongs_to :user

  STANDARD_KEYS = %w[
    parent needs_response outbox rework action_required
    payment_request fyi waiting done
  ].freeze

  STANDARD_NAMES = {
    "parent" => "🤖 AI",
    "needs_response" => "🤖 AI/Needs Response",
    "outbox" => "🤖 AI/Outbox",
    "rework" => "🤖 AI/Rework",
    "action_required" => "🤖 AI/Action Required",
    "payment_request" => "🤖 AI/Payment Requests",
    "fyi" => "🤖 AI/FYI",
    "waiting" => "🤖 AI/Waiting",
    "done" => "🤖 AI/Done"
  }.freeze

  validates :label_key, presence: true, inclusion: { in: STANDARD_KEYS }
  validates :gmail_label_id, presence: true
  validates :gmail_label_name, presence: true
end
