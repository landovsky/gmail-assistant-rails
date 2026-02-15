class SyncState < ApplicationRecord
  belongs_to :user

  def synced?
    last_history_id != "0"
  end
end
