module Jobs
  class CleanupHandler < BaseHandler
    # Placeholder - pipeline team builds the cleanup logic
    def perform
      Rails.logger.info("CleanupHandler: placeholder action=#{@payload['action']} thread=#{@payload['thread_id']}")
    end
  end
end
