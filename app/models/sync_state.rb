class SyncState < ApplicationRecord
  # Associations
  belongs_to :user

  # Validations
  validates :last_history_id, presence: true
end
