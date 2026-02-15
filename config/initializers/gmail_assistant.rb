Rails.application.config.after_initialize do
  next if defined?(Rails::Console) || Rails.env.test? || File.basename($0) == "rake"

  # Start the background worker pool
  worker_pool = Jobs::WorkerPool.new
  worker_pool.start

  # Start the scheduler (watch renewal, fallback sync, full sync)
  scheduler = Jobs::Scheduler.new
  scheduler.start

  # Graceful shutdown
  at_exit do
    Rails.logger.info("Gmail Assistant shutting down...")
    scheduler.stop
    worker_pool.stop
  end
end
