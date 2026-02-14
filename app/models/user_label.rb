class UserLabel < ApplicationRecord
  self.primary_key = [:user_id, :label_key]

  # Associations
  belongs_to :user

  # Validations
  validates :label_key, presence: true
  validates :gmail_label_id, presence: true
  validates :gmail_label_name, presence: true
  validates :label_key, inclusion: {
    in: %w[parent needs_response outbox rework action_required payment_request fyi waiting done],
    message: "%{value} is not a valid label key"
  }
end
