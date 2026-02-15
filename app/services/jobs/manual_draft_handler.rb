module Jobs
  class ManualDraftHandler < BaseHandler
    # Placeholder - pipeline team builds the manual draft logic
    def perform
      Rails.logger.info("ManualDraftHandler: placeholder for message #{@payload['message_id']}")
    end
  end
end
