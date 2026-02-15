module Agents
  class DefaultPreprocessor
    def process(email_data)
      {
        sender_email: email_data[:sender_email],
        subject: email_data[:subject],
        body: email_data[:body]
      }
    end
  end
end
