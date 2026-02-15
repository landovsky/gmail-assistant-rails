module Lifecycle
  class WaitingRetriager
    def initialize(gmail_client: nil)
      @gmail_client = gmail_client
    end

    def handle(email:, user:)
      return unless @gmail_client

      thread_data = @gmail_client.get_thread(thread_id: email.gmail_thread_id)
      return unless thread_data

      current_message_count = thread_data[:message_count] || thread_data["message_count"] || 0

      if current_message_count > (email.message_count || 0)
        waiting_label = user.user_labels.find_by(label_key: "waiting")

        if waiting_label
          @gmail_client.modify_thread(
            thread_id: email.gmail_thread_id,
            add_label_ids: [],
            remove_label_ids: [waiting_label.gmail_label_id]
          )
        end

        EmailEvent.create!(
          user: user,
          gmail_thread_id: email.gmail_thread_id,
          event_type: "waiting_retriaged",
          detail: "New messages detected (#{email.message_count} -> #{current_message_count})"
        )
      end
    end
  end
end
