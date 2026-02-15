module Jobs
  class ReworkHandler < BaseHandler
    def perform
      message_id = @payload["message_id"]

      # Fetch message to get thread_id
      message = @gmail_client.get_message(message_id)
      thread_id = message.thread_id

      email = Email.find_by(user: @user, gmail_thread_id: thread_id)
      unless email
        Rails.logger.info("ReworkHandler: no email record for thread #{thread_id}, skipping")
        return
      end

      # Build dependencies and delegate to lifecycle rework handler
      llm_gateway = Llm::Gateway.new(user: @user)
      draft_generator = Drafting::DraftGenerator.new(llm_gateway: llm_gateway)
      context_gatherer = Drafting::ContextGatherer.new(llm_gateway: llm_gateway, gmail_client: @gmail_client)

      handler = Lifecycle::ReworkHandler.new(
        draft_generator: draft_generator,
        context_gatherer: context_gatherer,
        gmail_client: @gmail_client
      )

      handler.handle(email: email, user: @user)
    end
  end
end
