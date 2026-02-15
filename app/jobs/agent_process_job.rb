# frozen_string_literal: true

# Background job for agent-based email processing
#
# Runs an LLM agent with registered tools to process an email.
# The agent can use multiple tools in a multi-turn conversation loop.
class AgentProcessJob < ApplicationJob
  queue_as :default

  # Process an email with the specified agent profile
  #
  # @param user_id [Integer] User ID
  # @param gmail_thread_id [String] Gmail thread ID
  # @param gmail_message_id [String] Gmail message ID
  # @param profile_name [String] Agent profile name from config
  def perform(user_id, gmail_thread_id, gmail_message_id, profile_name)
    user = User.find(user_id)
    email = Email.find_by!(user: user, gmail_thread_id: gmail_thread_id)

    # Load agent configuration
    config = load_agent_config

    # Fetch the message from Gmail
    gmail_client = Gmail::Client.new(user)
    message = gmail_client.get_message(gmail_message_id)

    # Preprocess the email (extract structured data)
    preprocessor = Agent::Preprocessor.for_profile(profile_name, config)
    initial_message = preprocessor.preprocess(message)

    # Create agent run record
    agent_run = AgentRun.create!(
      user: user,
      gmail_thread_id: gmail_thread_id,
      profile: profile_name,
      status: "running",
      tool_calls_log: [],
      iterations: 0
    )

    begin
      # Run the agent
      runner = Agent::Runner.new(
        profile_name: profile_name,
        config: config,
        initial_message: initial_message
      )

      result = runner.run

      # Update agent run with results
      agent_run.update!(
        status: result[:status],
        final_message: result[:final_message],
        tool_calls_log: result[:tool_calls],
        iterations: result[:iterations],
        error: result[:error]
      )

      # Log email event
      email.events.create!(
        event_type: "agent_processed",
        metadata: {
          profile: profile_name,
          status: result[:status],
          iterations: result[:iterations],
          tool_calls_count: result[:tool_calls].size
        }
      )

      Rails.logger.info "Agent processing completed for #{gmail_thread_id}: #{result[:status]}"

    rescue StandardError => e
      # Update agent run with error status
      agent_run.update!(
        status: "error",
        error: "#{e.class}: #{e.message}"
      )

      Rails.logger.error "AgentProcessJob failed for thread #{gmail_thread_id}: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise
    end
  end

  private

  def load_agent_config
    config_path = Rails.root.join("config", "agent.yml")
    unless File.exist?(config_path)
      raise "Agent configuration not found at #{config_path}"
    end

    YAML.load_file(config_path)
  end
end
