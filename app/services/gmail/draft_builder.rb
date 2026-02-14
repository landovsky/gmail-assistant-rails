# frozen_string_literal: true

require "mail"

module Gmail
  # Builds Gmail draft messages in MIME format
  class DraftBuilder
    def initialize(user_email:, to:, subject:, body:, thread_id:, in_reply_to: nil)
      @user_email = user_email
      @to = to
      @subject = subject
      @body = body
      @thread_id = thread_id
      @in_reply_to = in_reply_to
    end

    def build
      mail = Mail.new do
        from @user_email
        to @to
        subject ensure_re_prefix(@subject)
        body @body

        # Threading headers
        if @in_reply_to
          header["In-Reply-To"] = @in_reply_to
          header["References"] = @in_reply_to
        end
      end

      # Create Gmail message object
      message = Google::Apis::GmailV1::Message.new(
        raw: encode_message(mail.to_s),
        thread_id: @thread_id
      )

      message
    end

    private

    def ensure_re_prefix(subject)
      return subject if subject.blank?
      subject.start_with?("Re: ") ? subject : "Re: #{subject}"
    end

    def encode_message(message_string)
      Base64.urlsafe_encode64(message_string, padding: false)
    end
  end
end
