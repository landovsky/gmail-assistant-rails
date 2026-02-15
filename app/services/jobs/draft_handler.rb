module Jobs
  class DraftHandler < BaseHandler
    # Placeholder - pipeline team builds the draft generation logic
    def perform
      Rails.logger.info("DraftHandler: placeholder for thread #{@payload['thread_id']}")
    end
  end
end
