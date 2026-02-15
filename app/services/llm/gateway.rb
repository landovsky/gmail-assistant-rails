module Llm
  class Gateway
    def initialize(user: nil)
      @user = user
      @client = OpenAI::Client.new(
        uri_base: ENV.fetch("OPENAI_API_BASE", "https://openrouter.ai/api/v1"),
        access_token: ENV.fetch("OPENAI_API_KEY", "")
      )
    end

    def classify(prompt, system_prompt: nil)
      call_llm(
        call_type: "classify",
        model: config["classify_model"],
        max_tokens: config["max_classify_tokens"],
        system_prompt: system_prompt,
        user_message: prompt
      )
    end

    def draft(prompt, system_prompt: nil)
      call_llm(
        call_type: "draft",
        model: config["draft_model"],
        max_tokens: config["max_draft_tokens"],
        system_prompt: system_prompt,
        user_message: prompt
      )
    end

    def context_query(prompt, system_prompt: nil)
      call_llm(
        call_type: "context",
        model: config["context_model"],
        max_tokens: config["max_context_tokens"],
        system_prompt: system_prompt,
        user_message: prompt
      )
    end

    private

    def config
      AppConfig.llm
    end

    def call_llm(call_type:, model:, max_tokens:, system_prompt:, user_message:, gmail_thread_id: nil)
      messages = []
      messages << { role: "system", content: system_prompt } if system_prompt
      messages << { role: "user", content: user_message }

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      response = @client.chat(
        parameters: {
          model: model,
          messages: messages,
          max_tokens: max_tokens,
          temperature: 0.3
        }
      )

      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

      content = response.dig("choices", 0, "message", "content")
      usage = response["usage"] || {}

      log_call(
        call_type: call_type,
        model: model,
        system_prompt: system_prompt,
        user_message: user_message,
        response_text: content,
        prompt_tokens: usage["prompt_tokens"] || 0,
        completion_tokens: usage["completion_tokens"] || 0,
        total_tokens: usage["total_tokens"] || 0,
        latency_ms: latency_ms,
        gmail_thread_id: gmail_thread_id
      )

      content
    rescue StandardError => e
      latency_ms = if start_time
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
      else
        0
      end

      log_call(
        call_type: call_type,
        model: model,
        system_prompt: system_prompt,
        user_message: user_message,
        response_text: nil,
        prompt_tokens: 0,
        completion_tokens: 0,
        total_tokens: 0,
        latency_ms: latency_ms,
        error: e.message,
        gmail_thread_id: gmail_thread_id
      )

      Rails.logger.error("LLM call failed (#{call_type}): #{e.message}")
      nil
    end

    def log_call(call_type:, model:, system_prompt:, user_message:, response_text:, prompt_tokens:, completion_tokens:, total_tokens:, latency_ms:, error: nil, gmail_thread_id: nil)
      LlmCall.create!(
        user: @user,
        gmail_thread_id: gmail_thread_id,
        call_type: call_type,
        model: model,
        system_prompt: system_prompt,
        user_message: user_message,
        response_text: response_text,
        prompt_tokens: prompt_tokens,
        completion_tokens: completion_tokens,
        total_tokens: total_tokens,
        latency_ms: latency_ms,
        error: error
      )
    rescue StandardError => e
      Rails.logger.error("Failed to log LLM call: #{e.message}")
    end
  end
end
