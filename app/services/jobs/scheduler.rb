require "rufus-scheduler"

module Jobs
  class Scheduler
    attr_reader :scheduler

    def initialize
      @scheduler = Rufus::Scheduler.new
    end

    def start
      Rails.logger.info("Scheduler starting")

      schedule_watch_renewal
      schedule_fallback_sync
      schedule_full_sync

      Rails.logger.info("Scheduler started")
    end

    def stop
      Rails.logger.info("Scheduler shutting down")
      @scheduler.shutdown
      Rails.logger.info("Scheduler stopped")
    end

    private

    def schedule_watch_renewal
      @scheduler.every("24h", first: :now) do
        Rails.logger.info("Scheduler: renewing watches")
        Gmail::WatchManager.renew_all_watches
      rescue StandardError => e
        Rails.logger.error("Scheduler: watch renewal failed: #{e.message}")
      end
    end

    def schedule_fallback_sync
      interval = AppConfig.sync["fallback_interval_minutes"] || 15
      @scheduler.every("#{interval}m") do
        Rails.logger.info("Scheduler: enqueuing fallback sync jobs")
        enqueue_sync_for_all_users(force_full: false)
      rescue StandardError => e
        Rails.logger.error("Scheduler: fallback sync failed: #{e.message}")
      end
    end

    def schedule_full_sync
      interval = AppConfig.sync["full_sync_interval_hours"] || 1
      @scheduler.every("#{interval}h") do
        Rails.logger.info("Scheduler: enqueuing full sync jobs")
        enqueue_sync_for_all_users(force_full: true)
      rescue StandardError => e
        Rails.logger.error("Scheduler: full sync failed: #{e.message}")
      end
    end

    def enqueue_sync_for_all_users(force_full:)
      User.active.onboarded.find_each do |user|
        payload = { history_id: "" }
        payload[:force_full] = true if force_full

        Job.create!(
          user: user,
          job_type: "sync",
          payload: payload.to_json,
          status: "pending"
        )
      end
    end
  end
end
