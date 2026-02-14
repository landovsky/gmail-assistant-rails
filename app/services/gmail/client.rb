# frozen_string_literal: true

require "google/apis/gmail_v1"
require "googleauth"

module Gmail
  # Gmail API client wrapper with automatic token refresh and retry logic
  class Client
    MAX_RETRIES = 3
    BASE_DELAY = 1 # seconds

    RETRYABLE_ERRORS = [
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      Errno::ETIMEDOUT,
      Errno::EPIPE,
      SocketError,
      OpenSSL::SSL::SSLError,
      Google::Apis::ServerError,
      Google::Apis::RateLimitError
    ].freeze

    attr_reader :user

    def initialize(user)
      @user = user
      @service = Google::Apis::GmailV1::GmailService.new
      authorize!
    end

    # Messages

    def list_messages(query: nil, label_ids: nil, max_results: 100, page_token: nil)
      with_retry do
        @service.list_user_messages(
          "me",
          q: query,
          label_ids: label_ids,
          max_results: max_results,
          page_token: page_token
        )
      end
    end

    def get_message(message_id, format: "full")
      with_retry do
        @service.get_user_message("me", message_id, format: format)
      end
    end

    def modify_message(message_id, add_label_ids: [], remove_label_ids: [])
      with_retry do
        modify_request = Google::Apis::GmailV1::ModifyMessageRequest.new(
          add_label_ids: add_label_ids,
          remove_label_ids: remove_label_ids
        )
        @service.modify_message("me", message_id, modify_request)
      end
    end

    def batch_modify_messages(message_ids, add_label_ids: [], remove_label_ids: [])
      with_retry do
        batch_request = Google::Apis::GmailV1::BatchModifyMessagesRequest.new(
          ids: message_ids,
          add_label_ids: add_label_ids,
          remove_label_ids: remove_label_ids
        )
        @service.batch_modify_messages("me", batch_request)
      end
    end

    # Threads

    def get_thread(thread_id, format: "full")
      with_retry do
        @service.get_user_thread("me", thread_id, format: format)
      end
    end

    # Drafts

    def list_drafts(max_results: 100, page_token: nil)
      with_retry do
        @service.list_user_drafts("me", max_results: max_results, page_token: page_token)
      end
    end

    def get_draft(draft_id)
      with_retry do
        @service.get_user_draft("me", draft_id)
      end
    end

    def create_draft(message_object)
      with_retry do
        draft = Google::Apis::GmailV1::Draft.new(message: message_object)
        @service.create_user_draft("me", draft)
      end
    end

    def delete_draft(draft_id)
      with_retry do
        @service.delete_user_draft("me", draft_id)
      end
    end

    # History

    def list_history(start_history_id, max_results: 100, page_token: nil, label_id: nil)
      with_retry do
        @service.list_user_histories(
          "me",
          start_history_id: start_history_id,
          max_results: max_results,
          page_token: page_token,
          label_id: label_id
        )
      end
    end

    # Labels

    def list_labels
      with_retry do
        @service.list_user_labels("me")
      end
    end

    def create_label(name, label_list_visibility: "labelShow", message_list_visibility: "show")
      with_retry do
        label = Google::Apis::GmailV1::Label.new(
          name: name,
          label_list_visibility: label_list_visibility,
          message_list_visibility: message_list_visibility
        )
        @service.create_user_label("me", label)
      end
    end

    # Profile

    def get_profile
      with_retry do
        @service.get_user_profile("me")
      end
    end

    # Watch (Pub/Sub)

    def watch(topic_name, label_ids: nil, label_filter_behavior: "include")
      with_retry do
        watch_request = Google::Apis::GmailV1::WatchRequest.new(
          topic_name: topic_name,
          label_ids: label_ids,
          label_filter_behavior: label_filter_behavior
        )
        @service.watch_user("me", watch_request)
      end
    end

    def stop_watch
      with_retry do
        @service.stop_user("me")
      end
    end

    private

    def authorize!
      refresh_token_if_needed!

      credentials = Signet::OAuth2::Client.new(
        client_id: Rails.application.config.google_oauth[:client_id],
        client_secret: Rails.application.config.google_oauth[:client_secret],
        token_credential_uri: "https://oauth2.googleapis.com/token",
        access_token: user.google_access_token,
        refresh_token: user.google_refresh_token,
        expires_at: user.google_token_expires_at&.to_i
      )

      @service.authorization = credentials
    end

    def refresh_token_if_needed!
      return unless user.google_token_expired?
      return unless user.google_refresh_token.present?

      client = Signet::OAuth2::Client.new(
        client_id: Rails.application.config.google_oauth[:client_id],
        client_secret: Rails.application.config.google_oauth[:client_secret],
        token_credential_uri: "https://oauth2.googleapis.com/token",
        refresh_token: user.google_refresh_token
      )

      client.fetch_access_token!

      user.store_google_tokens(
        access_token: client.access_token,
        expires_at: Time.at(client.expires_at)
      )
    end

    def with_retry
      attempts = 0
      begin
        attempts += 1
        yield
      rescue *RETRYABLE_ERRORS => e
        if attempts < MAX_RETRIES
          delay = BASE_DELAY * (2**(attempts - 1))
          Rails.logger.warn "Gmail API error (attempt #{attempts}/#{MAX_RETRIES}): #{e.class} - #{e.message}. Retrying in #{delay}s..."
          sleep delay
          retry
        else
          Rails.logger.error "Gmail API error after #{MAX_RETRIES} attempts: #{e.class} - #{e.message}"
          raise
        end
      rescue Google::Apis::ClientError => e
        # Don't retry 4xx errors except 429 (rate limit)
        if e.status_code == 429 && attempts < MAX_RETRIES
          delay = BASE_DELAY * (2**(attempts - 1))
          Rails.logger.warn "Gmail API rate limit (attempt #{attempts}/#{MAX_RETRIES}). Retrying in #{delay}s..."
          sleep delay
          retry
        else
          Rails.logger.error "Gmail API client error: #{e.status_code} - #{e.message}"
          raise
        end
      end
    end
  end
end
