class SyncState < ApplicationRecord
  self.primary_key = "user_id"

  belongs_to :user

  def synced?
    last_history_id != "0"
  end
end
