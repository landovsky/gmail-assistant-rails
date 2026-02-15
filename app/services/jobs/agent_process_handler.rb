module Jobs
  class AgentProcessHandler < BaseHandler
    # Placeholder - agent framework team builds the agent processing logic
    def perform
      Rails.logger.info("AgentProcessHandler: placeholder for thread #{@payload['thread_id']} profile=#{@payload['profile']}")
    end
  end
end
