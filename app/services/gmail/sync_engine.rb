# frozen_string_literal: true

module Gmail
  # Sync engine that uses Gmail History API to detect new/changed messages
  # and creates Email records for new messages
  class SyncEngine
    HISTORY_PAGE_SIZE = 100
    FULL_SYNC_DAYS_BACK = 10
    MAX_FULL_SYNC_MESSAGES = 50

    attr_reader :user, :client

    def initialize(user)
      @user = user
      @client = Gmail::Client.new(user)
    end

    # Perform incremental sync using History API, or full sync if needed
    def sync!
      sync_state = user.sync_state || user.create_sync_state!(last_history_id: "0")

      if sync_state.last_history_id == "0" || needs_full_sync?(sync_state)
        full_sync!(sync_state)
      else
        incremental_sync!(sync_state)
      end
    end

    private

    def needs_full_sync?(sync_state)
      # If last sync was more than 30 days ago, do full sync
      sync_state.last_sync_at.nil? || sync_state.last_sync_at < 30.days.ago
    end

    def incremental_sync!(sync_state)
      Rails.logger.info "Starting incremental sync for user #{user.id} from history_id #{sync_state.last_history_id}"

      seen_jobs = Set.new
      page_token = nil
      newest_history_id = sync_state.last_history_id

      begin
        loop do
          response = client.list_history(
            sync_state.last_history_id,
            max_results: HISTORY_PAGE_SIZE,
            page_token: page_token
          )

          # Update newest history_id from response
          newest_history_id = response.history_id if response.history_id

          # Process history records
          if response.history&.any?
            response.history.each do |history_record|
              process_history_record(history_record, seen_jobs)
            end
          end

          page_token = response.next_page_token
          break unless page_token
        end

        # Update sync state with newest history_id
        sync_state.update!(
          last_history_id: newest_history_id,
          last_sync_at: Time.current
        )

        Rails.logger.info "Incremental sync completed for user #{user.id}. New history_id: #{newest_history_id}"
      rescue Google::Apis::ClientError => e
        # If history_id is too old, fall back to full sync
        if e.message.include?("historyId") || e.status_code == 404
          Rails.logger.warn "History ID too old for user #{user.id}, falling back to full sync"
          full_sync!(sync_state)
        else
          raise
        end
      end
    end

    def process_history_record(history_record, seen_jobs)
      # Process messagesAdded - new messages arriving in INBOX
      history_record.messages_added&.each do |added|
        next unless added.message.label_ids&.include?("INBOX")

        thread_id = added.message.thread_id
        job_key = ["classify", thread_id]

        unless seen_jobs.include?(job_key)
          enqueue_classify_job(added.message.id, thread_id)
          seen_jobs.add(job_key)
        end
      end

      # Process labelsAdded - user applying labels manually
      history_record.labels_added&.each do |added|
        thread_id = added.message.thread_id
        label_ids = added.label_ids || []

        # Check for manual actions that need processing
        if label_ids.include?(user_label_id("needs_response"))
          job_key = ["manual_draft", thread_id]
          unless seen_jobs.include?(job_key)
            enqueue_manual_draft_job(thread_id)
            seen_jobs.add(job_key)
          end
        elsif label_ids.include?(user_label_id("rework"))
          job_key = ["rework", thread_id]
          unless seen_jobs.include?(job_key)
            enqueue_rework_job(thread_id)
            seen_jobs.add(job_key)
          end
        elsif label_ids.include?(user_label_id("done"))
          job_key = ["done", thread_id]
          unless seen_jobs.include?(job_key)
            enqueue_done_job(thread_id)
            seen_jobs.add(job_key)
          end
        end
      end

      # Process messagesDeleted - might indicate draft was sent
      history_record.messages_deleted&.each do |deleted|
        thread_id = deleted.message.thread_id
        job_key = ["cleanup", thread_id]

        unless seen_jobs.include?(job_key)
          enqueue_cleanup_job(thread_id)
          seen_jobs.add(job_key)
        end
      end
    end

    def full_sync!(sync_state)
      Rails.logger.info "Starting full sync for user #{user.id}"

      # Build search query: recent inbox messages, excluding AI-labeled and trash/spam
      query_parts = [
        "in:inbox",
        "newer_than:#{FULL_SYNC_DAYS_BACK}d",
        "-in:trash",
        "-in:spam"
      ]

      # Exclude AI-labeled messages
      %w[needs_response outbox rework action_required payment_request fyi waiting done].each do |label_key|
        if label_id = user_label_id(label_key)
          query_parts << "-label:#{label_id}"
        end
      end

      query = query_parts.join(" ")

      # Fetch messages
      response = client.list_messages(
        query: query,
        max_results: MAX_FULL_SYNC_MESSAGES
      )

      # Enqueue classify jobs for each message
      if response.messages&.any?
        response.messages.each do |message|
          enqueue_classify_job(message.id, message.thread_id)
        end
        Rails.logger.info "Full sync: enqueued #{response.messages.size} classify jobs for user #{user.id}"
      else
        Rails.logger.info "Full sync: no messages found for user #{user.id}"
      end

      # Get current history_id and update sync state
      profile = client.get_profile
      sync_state.update!(
        last_history_id: profile.history_id.to_s,
        last_sync_at: Time.current
      )

      Rails.logger.info "Full sync completed for user #{user.id}. History_id: #{profile.history_id}"
    end

    def enqueue_classify_job(message_id, thread_id)
      # Check routing if agent config exists
      route = determine_route(message_id)

      if route[:route] == "agent"
        # Enqueue agent processing job
        AgentProcessJob.enqueue_tracked(
          user: user,
          job_type: "agent_process",
          payload: { message_id: message_id, thread_id: thread_id, profile: route[:profile] },
          user_id: user.id,
          gmail_thread_id: thread_id,
          gmail_message_id: message_id,
          profile_name: route[:profile]
        )
      else
        # Default to classify job
        ClassifyJob.enqueue_tracked(
          user: user,
          job_type: "classify",
          payload: { message_id: message_id, thread_id: thread_id },
          user_id: user.id,
          gmail_thread_id: thread_id,
          gmail_message_id: message_id
        )
      end
    end

    def determine_route(message_id)
      # Check if agent config exists
      config_path = Rails.root.join("config", "agent.yml")
      return { route: "pipeline" } unless File.exist?(config_path)

      begin
        config = YAML.load_file(config_path)
        return { route: "pipeline" } unless config&.dig("routing", "rules")

        # Fetch message to check routing
        message = client.get_message(message_id)
        router = Agent::Router.new(config)
        router.route_for(message)
      rescue StandardError => e
        Rails.logger.warn "Routing check failed, defaulting to pipeline: #{e.message}"
        { route: "pipeline" }
      end
    end

    def enqueue_manual_draft_job(thread_id)
      DraftJob.enqueue_tracked(
        user: user,
        job_type: "manual_draft",
        payload: { thread_id: thread_id },
        user_id: user.id,
        gmail_thread_id: thread_id
      )
    end

    def enqueue_rework_job(thread_id)
      ReworkJob.enqueue_tracked(
        user: user,
        job_type: "rework",
        payload: { thread_id: thread_id },
        user_id: user.id,
        gmail_thread_id: thread_id
      )
    end

    def enqueue_done_job(thread_id)
      CleanupJob.enqueue_tracked(
        user: user,
        job_type: "cleanup",
        payload: { thread_id: thread_id, action: "done" },
        user_id: user.id,
        gmail_thread_id: thread_id,
        action: "done"
      )
    end

    def enqueue_cleanup_job(thread_id)
      CleanupJob.enqueue_tracked(
        user: user,
        job_type: "cleanup",
        payload: { thread_id: thread_id, action: "check_sent" },
        user_id: user.id,
        gmail_thread_id: thread_id,
        action: "check_sent"
      )
    end

    def user_label_id(label_key)
      user.user_labels.find_by(label_key: label_key)&.gmail_label_id
    end
  end
end
