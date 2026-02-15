module Sync
  class Engine
    MAX_FULL_SYNC_MESSAGES = 50

    def initialize(user:, gmail_client:)
      @user = user
      @client = gmail_client
    end

    def perform(history_id: nil, force_full: false)
      sync_state = @user.sync_state

      if force_full || sync_state.nil? || !sync_state.synced?
        full_sync
      else
        incremental_sync(sync_state, history_id.presence || sync_state.last_history_id)
      end
    end

    private

    def incremental_sync(sync_state, start_history_id)
      seen_jobs = Set.new
      last_response = nil

      loop do
        last_response = @client.list_history(start_history_id, max_results: history_max_results)

        if last_response&.history
          last_response.history.each do |record|
            process_history_record(record, seen_jobs)
          end
        end

        page_token = last_response&.next_page_token
        break unless page_token

        start_history_id = last_response.history_id
      end

      new_history_id = last_response&.history_id || start_history_id
      sync_state.update!(last_history_id: new_history_id.to_s, last_sync_at: Time.current)
    rescue Google::Apis::ClientError => e
      if e.message.include?("historyId")
        Rails.logger.warn("History ID stale for user #{@user.id}, falling back to full sync")
        full_sync
      else
        raise
      end
    end

    def full_sync
      query = build_full_sync_query
      response = @client.list_messages(query: query, max_results: MAX_FULL_SYNC_MESSAGES)

      if response&.messages
        seen_threads = Set.new
        response.messages.each do |msg|
          message = @client.get_message(msg.id, format: "metadata")
          thread_id = message.thread_id
          next if seen_threads.include?(thread_id)
          seen_threads.add(thread_id)

          next if Email.exists?(user: @user, gmail_thread_id: thread_id)
          next if Job.where(user: @user, job_type: %w[classify agent_process])
                     .where("payload LIKE ?", "%#{thread_id}%")
                     .where(status: %w[pending running])
                     .exists?

          enqueue_job("classify", {
            message_id: msg.id,
            thread_id: thread_id
          })
        end
      end

      profile = @client.get_profile
      sync_state = @user.sync_state || @user.build_sync_state
      sync_state.update!(
        last_history_id: profile.history_id.to_s,
        last_sync_at: Time.current
      )
    end

    def process_history_record(record, seen_jobs)
      process_messages_added(record, seen_jobs) if record.messages_added
      process_labels_added(record, seen_jobs) if record.labels_added
      process_messages_deleted(record, seen_jobs) if record.messages_deleted
    end

    def process_messages_added(record, seen_jobs)
      record.messages_added.each do |added|
        message = added.message
        next unless message.label_ids&.include?("INBOX")

        thread_id = message.thread_id

        # Fetch full message for routing (need headers/body for match rules)
        full_message = @client.get_message(message.id)
        headers = Gmail::Client.parse_headers(full_message)
        sender = Gmail::Client.parse_sender(headers["From"])
        body = Gmail::Client.extract_body(full_message.payload)

        email_data = {
          sender_email: sender[:email],
          subject: headers["Subject"] || "",
          body: body,
          headers: headers
        }

        route_result = router.route(email_data)
        job_type = route_result["route"] == "agent" ? "agent_process" : "classify"

        job_key = [job_type, thread_id]
        next if seen_jobs.include?(job_key)
        seen_jobs.add(job_key)

        payload = { message_id: message.id, thread_id: thread_id }
        if job_type == "agent_process"
          payload[:profile] = route_result["profile"] || "default"
          payload[:route_rule] = route_result["name"] || "default"
        end

        enqueue_job(job_type, payload)
      end
    end

    def process_labels_added(record, seen_jobs)
      record.labels_added.each do |label_change|
        message = label_change.message
        label_ids = label_change.label_ids || []

        thread_id = message.thread_id

        done_label = user_label_id("done")
        rework_label = user_label_id("rework")
        needs_response_label = user_label_id("needs_response")

        if done_label && label_ids.include?(done_label)
          job_key = ["cleanup", thread_id]
          unless seen_jobs.include?(job_key)
            seen_jobs.add(job_key)
            enqueue_job("cleanup", { action: "done", thread_id: thread_id, message_id: message.id })
          end
        end

        if rework_label && label_ids.include?(rework_label)
          job_key = ["rework", thread_id]
          unless seen_jobs.include?(job_key)
            seen_jobs.add(job_key)
            enqueue_job("rework", { message_id: message.id })
          end
        end

        if needs_response_label && label_ids.include?(needs_response_label)
          job_key = ["manual_draft", thread_id]
          unless seen_jobs.include?(job_key)
            seen_jobs.add(job_key)
            enqueue_job("manual_draft", { message_id: message.id })
          end
        end
      end
    end

    def process_messages_deleted(record, seen_jobs)
      record.messages_deleted.each do |deleted|
        message = deleted.message
        thread_id = message.thread_id
        job_key = ["cleanup", thread_id]
        next if seen_jobs.include?(job_key)
        seen_jobs.add(job_key)

        enqueue_job("cleanup", { action: "check_sent", thread_id: thread_id, message_id: message.id })
      end
    end

    def enqueue_job(job_type, payload)
      Job.create!(
        user: @user,
        job_type: job_type,
        payload: payload.to_json,
        status: "pending"
      )
    end

    def router
      @router ||= Agents::Router.new(AppConfig.routing["rules"] || [])
    end

    def user_label_id(key)
      @user.user_labels.find_by(label_key: key)&.gmail_label_id
    end

    def build_full_sync_query
      days = AppConfig.sync["full_sync_days"] || 10
      exclusions = UserLabel::STANDARD_NAMES.values.map { |name| "-label:#{name.gsub('/', '-').gsub(' ', '-')}" }
      "in:inbox newer_than:#{days}d -in:trash -in:spam #{exclusions.join(' ')}"
    end

    def history_max_results
      AppConfig.sync["history_max_results"] || 100
    end
  end
end
