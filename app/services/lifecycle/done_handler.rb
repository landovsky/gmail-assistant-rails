module Lifecycle
  class DoneHandler
    AI_LABEL_KEYS = %w[needs_response outbox rework action_required payment_request fyi waiting].freeze

    def initialize(gmail_client: nil)
      @gmail_client = gmail_client
    end

    def handle(email:, user:)
      return unless @gmail_client

      label_ids_to_remove = user.user_labels
        .where(label_key: AI_LABEL_KEYS)
        .pluck(:gmail_label_id)

      # Also remove INBOX
      label_ids_to_remove << "INBOX"

      @gmail_client.modify_thread(
        thread_id: email.gmail_thread_id,
        add_label_ids: [],
        remove_label_ids: label_ids_to_remove
      )

      email.update!(status: "archived", acted_at: Time.current)

      EmailEvent.create!(
        user: user,
        gmail_thread_id: email.gmail_thread_id,
        event_type: "archived",
        detail: "Email archived via Done handler"
      )
    end
  end
end
