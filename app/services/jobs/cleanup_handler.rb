module Jobs
  class CleanupHandler < BaseHandler
    def perform
      action = @payload["action"]
      thread_id = @payload["thread_id"]

      email = Email.find_by(user: @user, gmail_thread_id: thread_id)

      case action
      when "done"
        handle_done(email)
      when "check_sent"
        handle_check_sent(email)
      else
        Rails.logger.warn("CleanupHandler: unknown action '#{action}' for thread #{thread_id}")
      end
    end

    private

    def handle_done(email)
      unless email
        Rails.logger.info("CleanupHandler: no email record for done action, skipping")
        return
      end

      handler = Lifecycle::DoneHandler.new(gmail_client: @gmail_client)
      handler.handle(email: email, user: @user)
    end

    def handle_check_sent(email)
      unless email
        Rails.logger.info("CleanupHandler: no email record for check_sent action, skipping")
        return
      end

      detector = Lifecycle::SentDetector.new(gmail_client: @gmail_client)
      detector.handle(email: email, user: @user)
    end
  end
end
