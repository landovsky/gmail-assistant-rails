class AgentRun < ApplicationRecord
  belongs_to :user

  STATUSES = %w[running completed error max_iterations].freeze

  validates :gmail_thread_id, presence: true
  validates :profile, presence: true
  validates :status, inclusion: { in: STATUSES }

  def parsed_tool_calls
    JSON.parse(tool_calls_log || "[]")
  rescue JSON::ParserError
    []
  end
end
