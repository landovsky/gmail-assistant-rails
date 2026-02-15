module Jobs
  class Dispatcher
    HANDLER_MAP = {
      "sync" => Jobs::SyncHandler,
      "classify" => Jobs::ClassifyHandler,
      "draft" => Jobs::DraftHandler,
      "cleanup" => Jobs::CleanupHandler,
      "rework" => Jobs::ReworkHandler,
      "manual_draft" => Jobs::ManualDraftHandler,
      "agent_process" => Jobs::AgentProcessHandler
    }.freeze

    def self.handler_for(job_type)
      HANDLER_MAP[job_type] || raise("Unknown job type: #{job_type}")
    end
  end
end
