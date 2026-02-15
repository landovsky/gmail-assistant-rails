module Jobs
  class AgentProcessHandler < BaseHandler
    def perform
      thread_id = @payload["thread_id"]
      message_id = @payload["message_id"]
      profile_name = @payload["profile"] || "default"
      route_rule = @payload["route_rule"]

      # Load agent profile config
      profiles = AppConfig.agent["profiles"] || {}
      profile_config = profiles[profile_name]
      unless profile_config
        Rails.logger.warn("AgentProcessHandler: unknown profile '#{profile_name}', skipping")
        return
      end

      # Build profile hash expected by AgentLoop
      profile = {
        system_prompt: profile_config["system_prompt"],
        model: profile_config["model"],
        max_tokens: profile_config["max_tokens"] || 2048,
        temperature: profile_config["temperature"] || 0.3,
        max_iterations: profile_config["max_iterations"] || 10,
        tools: profile_config["tools"] || [],
        preprocessor: profile_config["preprocessor"]
      }

      # Fetch message and thread from Gmail
      message = @gmail_client.get_message(message_id)
      headers = Gmail::Client.parse_headers(message)
      sender = Gmail::Client.parse_sender(headers["From"])
      body = Gmail::Client.extract_body(message.payload)
      subject = headers["Subject"] || ""

      email_data = {
        sender_email: sender[:email],
        sender_name: sender[:name],
        subject: subject,
        body: body,
        headers: headers,
        thread_id: thread_id,
        message_id: message_id
      }

      # Preprocess email content
      preprocessor = build_preprocessor(profile[:preprocessor])
      processed = preprocessor.process(email_data)

      # Build user message from processed email
      user_message = build_user_message(processed)

      # Create agent_runs record
      agent_run = AgentRun.create!(
        user: @user,
        gmail_thread_id: thread_id,
        profile: profile_name,
        status: "running"
      )

      # Build tool registry and LLM client
      llm_client = build_llm_client
      tool_registry = build_tool_registry(profile_config)

      # Execute agent loop
      agent_loop = Agents::AgentLoop.new(llm_client: llm_client, tool_registry: tool_registry)
      result = agent_loop.run(profile: profile, user_message: user_message)

      # Update agent_runs record with results
      agent_run.update!(
        status: result.status,
        final_message: result.final_message,
        tool_calls_log: result.tool_calls.to_json,
        iterations: result.iterations,
        error: result.error
      )

      # Log event
      EmailEvent.create!(
        user: @user,
        gmail_thread_id: thread_id,
        event_type: "agent_processed",
        detail: "Agent '#{profile_name}' completed with status: #{result.status}, iterations: #{result.iterations}"
      )
    end

    private

    def build_preprocessor(preprocessor_name)
      case preprocessor_name
      when "crisp"
        Agents::CrispPreprocessor.new
      else
        Agents::DefaultPreprocessor.new
      end
    end

    def build_user_message(processed)
      parts = []
      parts << "From: #{processed[:sender_email]}" if processed[:sender_email]
      parts << "Subject: #{processed[:subject]}" if processed[:subject]
      parts << ""
      parts << processed[:body] if processed[:body]
      parts.join("\n")
    end

    def build_llm_client
      OpenAI::Client.new(
        uri_base: ENV.fetch("OPENAI_API_BASE", "https://openrouter.ai/api/v1"),
        access_token: ENV.fetch("OPENAI_API_KEY", "")
      )
    end

    def build_tool_registry(profile_config)
      registry = Agents::ToolRegistry.new

      tool_module = profile_config["tool_module"]
      if tool_module
        tool_class = tool_module.constantize
        tool_class.register_all(registry) if tool_class.respond_to?(:register_all)
      end

      registry
    end
  end
end
