require "google/apis/gmail_v1"
require "googleauth"

module Gmail
  class Client
    RETRYABLE_STATUS_CODES = [429, 500, 502, 503, 504].freeze
    RETRYABLE_ERRORS = [
      Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::EHOSTUNREACH,
      Errno::ENETUNREACH, Errno::ETIMEDOUT, Net::OpenTimeout,
      Net::ReadTimeout, SocketError, IOError
    ].freeze
    MAX_RETRIES = 3
    BASE_DELAY = 1

    attr_reader :service, :user_email

    def initialize(user_email: "me")
      @user_email = user_email
      @service = Google::Apis::GmailV1::GmailService.new
      @service.authorization = build_authorization
    end

    # --- Messages ---

    def list_messages(query: nil, label_ids: nil, max_results: 100)
      with_retry do
        @service.list_user_messages("me", q: query, label_ids: label_ids, max_results: max_results)
      end
    end

    def get_message(message_id, format: "full")
      with_retry do
        @service.get_user_message("me", message_id, format: format)
      end
    end

    def modify_message(message_id, add_label_ids: [], remove_label_ids: [])
      body = Google::Apis::GmailV1::ModifyMessageRequest.new(
        add_label_ids: add_label_ids,
        remove_label_ids: remove_label_ids
      )
      with_retry do
        @service.modify_message("me", message_id, body)
      end
    end

    def batch_modify_messages(message_ids, add_label_ids: [], remove_label_ids: [])
      body = Google::Apis::GmailV1::BatchModifyMessagesRequest.new(
        ids: message_ids,
        add_label_ids: add_label_ids,
        remove_label_ids: remove_label_ids
      )
      with_retry do
        @service.batch_modify_messages("me", body)
      end
    end

    # --- Threads ---

    def get_thread(thread_id, format: "full")
      with_retry do
        @service.get_user_thread("me", thread_id, format: format)
      end
    end

    # Modify labels on all messages in a thread (batch operation)
    def modify_thread(thread_id:, add_label_ids: [], remove_label_ids: [])
      thread = get_thread(thread_id, format: "minimal")
      return unless thread&.messages&.any?

      message_ids = thread.messages.map(&:id)
      batch_modify_messages(message_ids, add_label_ids: add_label_ids, remove_label_ids: remove_label_ids)
    end

    # Get thread data as a parsed hash with body, sender, subject, message_count
    def get_thread_data(thread_id)
      thread = get_thread(thread_id)
      return nil unless thread&.messages&.any?

      messages = thread.messages
      first_message = messages.first
      headers = self.class.parse_headers(first_message)
      sender = self.class.parse_sender(headers["From"])

      bodies = messages.map { |msg| self.class.extract_body(msg.payload) }
      combined_body = bodies.reject(&:blank?).join("\n\n---\n\n")

      {
        thread_id: thread_id,
        sender: "#{sender[:name]} <#{sender[:email]}>",
        sender_name: sender[:name],
        sender_email: sender[:email],
        subject: headers["Subject"] || "",
        body: combined_body,
        message_count: messages.size,
        messages: messages
      }
    end

    # Search for threads matching a query, returns array of {thread_id:} hashes
    def search_threads(query:, max_results: 10)
      response = list_messages(query: query, max_results: max_results)
      return [] unless response&.messages

      response.messages.map { |msg| { thread_id: msg.thread_id } }.uniq { |h| h[:thread_id] }
    end

    # --- Drafts ---

    def create_draft(to:, subject:, body:, thread_id: nil, in_reply_to: nil, references: nil, from: nil)
      raw = build_mime_message(
        from: from || user_email,
        to: to,
        subject: subject,
        body: body,
        in_reply_to: in_reply_to,
        references: references
      )

      message = Google::Apis::GmailV1::Message.new(raw: raw, thread_id: thread_id)
      draft = Google::Apis::GmailV1::Draft.new(message: message)

      with_retry do
        @service.create_user_draft("me", draft)
      end
    end

    def get_draft(draft_id)
      with_retry do
        @service.get_user_draft("me", draft_id)
      end
    end

    def delete_draft(draft_id)
      with_retry do
        @service.delete_user_draft("me", draft_id)
      end
    end

    # Trash a draft (alias for delete_draft, named for clarity)
    def trash_draft(draft_id:)
      delete_draft(draft_id)
    end

    # Check if a draft still exists
    def draft_exists?(draft_id:)
      get_draft(draft_id)
      true
    rescue Google::Apis::ClientError => e
      return false if e.status_code == 404 || e.message.include?("notFound")
      raise
    end

    # Get draft body as parsed text
    def get_draft_body(draft_id)
      draft = get_draft(draft_id)
      return nil unless draft&.message&.payload

      self.class.extract_body(draft.message.payload)
    end

    def list_drafts(max_results: 100)
      with_retry do
        @service.list_user_drafts("me", max_results: max_results)
      end
    end

    # --- History ---

    def list_history(start_history_id, label_id: nil, max_results: 100)
      with_retry do
        @service.list_user_histories(
          "me",
          start_history_id: start_history_id,
          label_id: label_id,
          max_results: max_results,
          history_types: %w[messageAdded labelAdded messageDeleted]
        )
      end
    end

    # --- Watch ---

    def watch(topic_name:, label_ids: [])
      request = Google::Apis::GmailV1::WatchRequest.new(
        topic_name: topic_name,
        label_ids: label_ids,
        label_filter_behavior: "INCLUDE"
      )
      with_retry do
        @service.watch_user("me", request)
      end
    end

    def stop_watch
      with_retry do
        @service.stop_user("me")
      end
    end

    # --- Labels ---

    def list_labels
      with_retry do
        @service.list_user_labels("me")
      end
    end

    def create_label(name)
      label = Google::Apis::GmailV1::Label.new(
        name: name,
        label_list_visibility: "labelShow",
        message_list_visibility: "show"
      )
      with_retry do
        @service.create_user_label("me", label)
      end
    end

    # --- Profile ---

    def get_profile
      with_retry do
        @service.get_user_profile("me")
      end
    end

    # --- Message Parsing ---

    def self.parse_headers(message)
      headers = {}
      return headers unless message&.payload&.headers

      target_headers = %w[
        From To Subject Date Message-ID Auto-Submitted Precedence
        List-Id List-Unsubscribe X-Auto-Response-Suppress Feedback-ID
        X-Autoreply X-Autorespond X-Forwarded-From Reply-To
      ]

      message.payload.headers.each do |header|
        headers[header.name] = header.value if target_headers.include?(header.name)
      end
      headers
    end

    def self.parse_sender(from_header)
      return { name: "", email: "" } if from_header.nil? || from_header.empty?

      if from_header =~ /\A\s*"?([^"<]*?)"?\s*<([^>]+)>\s*\z/
        { name: $1.strip, email: $2.strip.downcase }
      else
        { name: "", email: from_header.strip.downcase }
      end
    end

    def self.extract_body(payload)
      return "" unless payload

      if payload.mime_type == "text/plain" && payload.body&.data
        return decode_body(payload.body.data)
      end

      if payload.parts
        payload.parts.each do |part|
          result = extract_body(part)
          return result unless result.empty?
        end
      end

      ""
    end

    def self.decode_body(data)
      return "" unless data
      Base64.urlsafe_decode64(data).force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    rescue ArgumentError
      ""
    end

    private

    def build_authorization
      auth_config = AppConfig.auth
      mode = auth_config["mode"]

      case mode
      when "personal_oauth"
        build_personal_oauth(auth_config)
      when "service_account"
        build_service_account(auth_config)
      else
        raise "Unknown auth mode: #{mode}"
      end
    end

    def build_personal_oauth(config)
      credentials_file = Rails.root.join(config["credentials_file"])
      token_file = Rails.root.join(config["token_file"])
      scopes = config["scopes"]

      client_id = Google::Auth::ClientId.from_file(credentials_file)
      token_store = Google::Auth::Stores::FileTokenStore.new(file: token_file.to_s)
      authorizer = Google::Auth::UserAuthorizer.new(client_id, scopes, token_store)

      credentials = authorizer.get_credentials("default")
      raise "No cached credentials found. Run the OAuth flow first." unless credentials

      credentials
    end

    def build_service_account(config)
      key_file = Rails.root.join(config["service_account_file"])
      scopes = config["scopes"]

      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: File.open(key_file),
        scope: scopes,
        target_audience: nil
      ).tap { |c| c.sub = @user_email if @user_email != "me" }
    end

    def build_mime_message(from:, to:, subject:, body:, in_reply_to: nil, references: nil)
      subject = "Re: #{subject}" unless subject&.start_with?("Re: ")

      lines = []
      lines << "From: #{from}"
      lines << "To: #{to}"
      lines << "Subject: #{subject}"
      lines << "In-Reply-To: #{in_reply_to}" if in_reply_to
      lines << "References: #{references || in_reply_to}" if in_reply_to
      lines << "Content-Type: text/plain; charset=UTF-8"
      lines << ""
      lines << body

      Base64.urlsafe_encode64(lines.join("\r\n")).tr("=", "")
    end

    def with_retry(&block)
      attempts = 0
      begin
        attempts += 1
        yield
      rescue Google::Apis::RateLimitError, Google::Apis::ServerError => e
        raise unless attempts <= MAX_RETRIES
        sleep(BASE_DELAY * (2**(attempts - 1)))
        retry
      rescue *RETRYABLE_ERRORS => e
        raise unless attempts <= MAX_RETRIES
        sleep(BASE_DELAY * (2**(attempts - 1)))
        retry
      rescue Google::Apis::ClientError
        raise # Don't retry 4xx errors (except 429 handled above as RateLimitError)
      end
    end
  end
end
