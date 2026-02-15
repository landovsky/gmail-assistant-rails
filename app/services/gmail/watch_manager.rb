module Gmail
  class WatchManager
    def initialize(client)
      @client = client
    end

    def register_watch(user)
      label_ids = build_label_ids(user)
      topic = AppConfig.sync["pubsub_topic"]

      return nil if topic.blank?

      response = @client.watch(topic_name: topic, label_ids: label_ids)

      sync_state = user.sync_state || user.create_sync_state
      sync_state.update!(
        watch_resource_id: response.history_id.to_s,
        watch_expiration: Time.at(response.expiration.to_i / 1000)
      )

      response
    end

    def stop_watch
      @client.stop_watch
    end

    def self.renew_all_watches
      User.active.onboarded.find_each do |user|
        client = Gmail::Client.new(user_email: user.email)
        manager = new(client)
        manager.register_watch(user)
      rescue StandardError => e
        Rails.logger.error("Watch renewal failed for user #{user.id}: #{e.message}")
      end
    end

    private

    def build_label_ids(user)
      ids = ["INBOX"]
      %w[needs_response rework done].each do |key|
        label = user.user_labels.find_by(label_key: key)
        ids << label.gmail_label_id if label
      end
      ids
    end
  end
end
