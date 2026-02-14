# frozen_string_literal: true

module Drafting
  # Gathers related context from the user's mailbox to inform draft generation
  #
  # Uses a two-phase approach:
  # 1. Generate search queries via LLM
  # 2. Execute searches and fetch full thread content
  #
  # Fail-safe: all errors are caught and logged. Draft proceeds without context.
  class ContextGatherer
    MAX_RELATED_THREADS = 5
    MAX_THREAD_BODY_LENGTH = 2000
    MAX_SEARCH_QUERIES = 3

    QUERY_GENERATION_PROMPT = <<~PROMPT.freeze
      You are a search query generator. Given an email, generate up to 3 Gmail search queries
      to find related prior correspondence in the user's mailbox.

      Return ONLY a JSON array of search query strings, e.g.:
      ["from:sender@example.com subject:project", "is:sent to:sender@example.com"]

      Focus on:
      - Sender email
      - Subject keywords
      - Related topics or project names

      Return an empty array [] if no relevant searches are possible.
    PROMPT

    # Gather related context for draft generation
    #
    # @param sender_email [String] Sender's email address
    # @param subject [String] Email subject
    # @param body [String] Email body
    # @param current_thread_id [String] Current thread ID to exclude from results
    # @param user [User] User for LLM call tracking
    # @param gmail_client [Gmail::Client] Authenticated Gmail client
    # @return [String, nil] Formatted related context block, or nil if none found
    def self.gather(sender_email:, subject:, body:, current_thread_id:, user:, gmail_client:)
      new(
        sender_email: sender_email,
        subject: subject,
        body: body,
        current_thread_id: current_thread_id,
        user: user,
        gmail_client: gmail_client
      ).gather
    rescue => e
      Rails.logger.warn "Context gathering failed (continuing without context): #{e.class} - #{e.message}"
      nil
    end

    def initialize(sender_email:, subject:, body:, current_thread_id:, user:, gmail_client:)
      @sender_email = sender_email
      @subject = subject
      @body = body
      @current_thread_id = current_thread_id
      @user = user
      @gmail_client = gmail_client
    end

    def gather
      queries = generate_search_queries
      return nil if queries.empty?

      thread_ids = execute_searches(queries)
      return nil if thread_ids.empty?

      related_threads = fetch_thread_contents(thread_ids)
      return nil if related_threads.empty?

      format_context(related_threads)
    end

    private

    def generate_search_queries
      user_message = build_query_generation_message

      start_time = Time.current
      result = Llm::Gateway.complete(
        messages: [
          { role: "system", content: QUERY_GENERATION_PROMPT },
          { role: "user", content: user_message }
        ],
        model_tier: :fast,
        temperature: 0.3
      )
      latency_ms = ((Time.current - start_time) * 1000).to_i

      content = result.dig(:choices, 0, :message, :content)
      queries = JSON.parse(content)

      track_llm_success(user_message, result, latency_ms)

      Array(queries).take(MAX_SEARCH_QUERIES)
    rescue => e
      Rails.logger.warn "Query generation failed: #{e.class} - #{e.message}"
      track_llm_error(user_message, e)
      []
    end

    def build_query_generation_message
      <<~MESSAGE
        From: #{@sender_email}
        Subject: #{@subject}

        #{@body.to_s.truncate(500)}
      MESSAGE
    end

    def execute_searches(queries)
      thread_ids = Set.new

      queries.each do |query|
        begin
          response = @gmail_client.list_messages(query: query, max_results: 10)
          message_list = response.messages || []

          message_list.each do |msg|
            thread_ids.add(msg.thread_id) if msg.thread_id != @current_thread_id
          end
        rescue => e
          Rails.logger.warn "Search query failed (#{query}): #{e.class} - #{e.message}"
        end
      end

      thread_ids.to_a.take(MAX_RELATED_THREADS)
    end

    def fetch_thread_contents(thread_ids)
      related_threads = []

      thread_ids.each do |thread_id|
        begin
          thread = @gmail_client.get_thread(thread_id, format: "full")
          messages = thread.messages || []

          next if messages.empty?

          first_msg = messages.first
          parser = Gmail::MessageParser.new(first_msg)

          # Combine all message bodies in thread
          combined_body = messages.map do |msg|
            Gmail::MessageParser.new(msg).body
          end.join("\n\n")

          # Format sender (from returns hash with :name and :email)
          from_info = parser.from
          sender_display = from_info[:name].present? ? "#{from_info[:name]} <#{from_info[:email]}>" : from_info[:email]

          related_threads << {
            sender: sender_display,
            subject: parser.subject,
            body: combined_body.truncate(MAX_THREAD_BODY_LENGTH, omission: "...")
          }
        rescue => e
          Rails.logger.warn "Failed to fetch thread #{thread_id}: #{e.class} - #{e.message}"
        end
      end

      related_threads
    end

    def format_context(related_threads)
      lines = ["--- Related emails from your mailbox ---"]

      related_threads.each_with_index do |thread, index|
        lines << "#{index + 1}. From: #{thread[:sender]} | Subject: #{thread[:subject]}"
        lines << "   #{thread[:body]}"
      end

      lines << "--- End related emails ---"
      lines.join("\n")
    end

    def track_llm_success(user_message, result, latency_ms)
      content = result.dig(:choices, 0, :message, :content)
      usage = result[:usage] || {}

      LlmCall.create!(
        user: @user,
        gmail_thread_id: @current_thread_id,
        call_type: "context",
        model: extract_model(result),
        system_prompt: QUERY_GENERATION_PROMPT,
        user_message: user_message,
        response_text: content,
        prompt_tokens: usage[:prompt_tokens] || 0,
        completion_tokens: usage[:completion_tokens] || 0,
        total_tokens: usage[:total_tokens] || 0,
        latency_ms: latency_ms
      )
    rescue => e
      Rails.logger.error "Failed to track LLM call: #{e.class} - #{e.message}"
    end

    def track_llm_error(user_message, error)
      LlmCall.create!(
        user: @user,
        gmail_thread_id: @current_thread_id,
        call_type: "context",
        model: "unknown",
        system_prompt: QUERY_GENERATION_PROMPT,
        user_message: user_message,
        error: "#{error.class}: #{error.message}"
      )
    rescue => e
      Rails.logger.error "Failed to track LLM error: #{e.class} - #{e.message}"
    end

    def extract_model(result)
      result[:model] || ENV["LLM_FAST_MODEL"] || "unknown"
    end
  end
end
