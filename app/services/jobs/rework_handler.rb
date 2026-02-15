module Jobs
  class ReworkHandler < BaseHandler
    # Placeholder - pipeline team builds the rework logic
    def perform
      Rails.logger.info("ReworkHandler: placeholder for message #{@payload['message_id']}")
    end
  end
end
