module Jobs
  class ClassifyHandler < BaseHandler
    # Placeholder - pipeline team builds the classification logic
    def perform
      Rails.logger.info("ClassifyHandler: placeholder for thread #{@payload['thread_id']}")
    end
  end
end
