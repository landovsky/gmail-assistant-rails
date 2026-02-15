module Jobs
  class SyncHandler < BaseHandler
    def perform
      engine = Sync::Engine.new(user: @user, gmail_client: @gmail_client)
      engine.perform(
        history_id: @payload["history_id"],
        force_full: @payload["force_full"] == true
      )
    end
  end
end
