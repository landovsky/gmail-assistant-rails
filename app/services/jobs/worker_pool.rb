module Jobs
  class WorkerPool
    SLEEP_INTERVAL = 1 # seconds to sleep when no jobs available

    attr_reader :concurrency, :running

    def initialize(concurrency: nil)
      @concurrency = concurrency || AppConfig.server["worker_concurrency"] || 3
      @running = false
      @threads = []
    end

    def start
      @running = true
      Rails.logger.info("WorkerPool starting with #{@concurrency} workers")

      @concurrency.times do |i|
        @threads << Thread.new { worker_loop(i) }
      end
    end

    def stop
      Rails.logger.info("WorkerPool shutting down...")
      @running = false
      @threads.each(&:join)
      @threads.clear
      Rails.logger.info("WorkerPool stopped")
    end

    private

    def worker_loop(worker_id)
      Rails.logger.info("Worker #{worker_id} started")

      while @running
        job = Job.claim_next
        if job
          process_job(job, worker_id)
        else
          sleep(SLEEP_INTERVAL)
        end
      end

      Rails.logger.info("Worker #{worker_id} stopped")
    rescue StandardError => e
      Rails.logger.error("Worker #{worker_id} crashed: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    end

    def process_job(job, worker_id)
      Rails.logger.info("Worker #{worker_id} processing job #{job.id} (#{job.job_type})")

      user = User.find_by(id: job.user_id)
      unless user
        job.fail!("User #{job.user_id} not found")
        return
      end

      gmail_client = Gmail::Client.new(user_email: user.email)
      handler_class = Jobs::Dispatcher.handler_for(job.job_type)
      handler = handler_class.new(job: job, user: user, gmail_client: gmail_client)
      handler.perform
      job.complete!

      Rails.logger.info("Worker #{worker_id} completed job #{job.id}")
    rescue StandardError => e
      Rails.logger.error("Worker #{worker_id} job #{job.id} failed: #{e.message}")
      job.fail!(e.message)
    end
  end
end
