module Lifecycle
  class SentDetector
    def initialize(gmail_client: nil)
      @gmail_client = gmail_client
    end

    def handle(email:, user:)
      return unless @gmail_client
      return unless email.draft_id.present?

      draft_exists = @gmail_client.draft_exists?(draft_id: email.draft_id)

      unless draft_exists
        outbox_label = user.user_labels.find_by(label_key: "outbox")

        if outbox_label
          @gmail_client.modify_thread(
            thread_id: email.gmail_thread_id,
            add_label_ids: [],
            remove_label_ids: [outbox_label.gmail_label_id]
          )
        end

        email.update!(status: "sent", acted_at: Time.current)

        EmailEvent.create!(
          user: user,
          gmail_thread_id: email.gmail_thread_id,
          event_type: "sent_detected",
          detail: "Draft #{email.draft_id} no longer exists - likely sent"
        )
      end
    end
  end
end
