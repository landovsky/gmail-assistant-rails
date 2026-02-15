module Api
  class ResetController < ApplicationController
    def create
      deleted = {
        jobs: Job.delete_all,
        emails: Email.delete_all,
        email_events: EmailEvent.delete_all,
        sync_state: SyncState.delete_all
      }

      render json: {
        deleted: deleted,
        total: deleted.values.sum
      }
    end
  end
end
