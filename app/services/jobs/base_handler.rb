module Jobs
  class BaseHandler
    def initialize(job:, user:, gmail_client:)
      @job = job
      @user = user
      @gmail_client = gmail_client
      @payload = job.parsed_payload
    end

    def perform
      raise NotImplementedError, "#{self.class}#perform must be implemented"
    end
  end
end
