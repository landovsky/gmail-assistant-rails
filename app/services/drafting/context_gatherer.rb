module Drafting
  class ContextGatherer
    MAX_RELATED_THREADS = 5
    BODY_TRUNCATION = 2000

    SYSTEM_PROMPT = <<~PROMPT
      You are helping find related prior correspondence in a Gmail mailbox.
      Given the email details below, generate up to 3 Gmail search queries that would find related prior conversations.
      Return ONLY a JSON array of query strings, e.g.: ["from:person@example.com subject:project", "subject:invoice acme"]
    PROMPT

    def initialize(llm_gateway:, gmail_client: nil)
      @llm_gateway = llm_gateway
      @gmail_client = gmail_client
    end

    def gather(sender_email:, subject:, body:, gmail_thread_id:)
      return "" unless @gmail_client

      queries = generate_queries(sender_email: sender_email, subject: subject, body: body)
      return "" if queries.empty?

      threads = search_threads(queries, exclude_thread_id: gmail_thread_id)
      return "" if threads.empty?

      format_context(threads)
    rescue StandardError => e
      Rails.logger.warn("ContextGatherer failed: #{e.message}")
      ""
    end

    private

    def generate_queries(sender_email:, subject:, body:)
      user_message = <<~MSG
        From: #{sender_email}
        Subject: #{subject}

        #{body.to_s[0, 1000]}
      MSG

      response = @llm_gateway.context_query(user_message, system_prompt: SYSTEM_PROMPT)
      return [] if response.nil?

      json_match = response.match(/\[.*\]/m)
      return [] unless json_match

      JSON.parse(json_match[0])
    rescue JSON::ParserError, StandardError
      []
    end

    def search_threads(queries, exclude_thread_id:)
      seen_thread_ids = Set.new([exclude_thread_id])
      threads = []

      queries.each do |query|
        break if threads.size >= MAX_RELATED_THREADS

        results = @gmail_client.search_threads(query: query)
        next unless results

        results.each do |thread_info|
          thread_id = thread_info[:thread_id] || thread_info["thread_id"]
          next if seen_thread_ids.include?(thread_id)

          seen_thread_ids.add(thread_id)
          thread_data = @gmail_client.get_thread_data(thread_id)
          threads << thread_data if thread_data
          break if threads.size >= MAX_RELATED_THREADS
        end
      end

      threads
    rescue StandardError => e
      Rails.logger.warn("ContextGatherer search failed: #{e.message}")
      []
    end

    def format_context(threads)
      lines = ["--- Related emails from your mailbox ---"]

      threads.each_with_index do |thread, idx|
        sender = thread[:sender] || thread["sender"] || "Unknown"
        subject = thread[:subject] || thread["subject"] || "(no subject)"
        body = thread[:body] || thread["body"] || ""

        lines << "#{idx + 1}. From: #{sender} | Subject: #{subject}"
        lines << "   #{body.to_s[0, BODY_TRUNCATION]}"
      end

      lines << "--- End related emails ---"
      lines.join("\n")
    end
  end
end
