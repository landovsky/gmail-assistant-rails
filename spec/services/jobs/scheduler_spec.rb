require "rails_helper"

RSpec.describe Jobs::Scheduler do
  let(:scheduler) { described_class.new }

  before do
    allow(AppConfig).to receive(:sync).and_return({
      "fallback_interval_minutes" => 15,
      "full_sync_interval_hours" => 1,
      "pubsub_topic" => "projects/test/topics/gmail"
    })
  end

  after do
    scheduler.stop
  end

  describe "#start" do
    it "schedules watch renewal, fallback sync, and full sync" do
      # Stub the watch manager to avoid real API calls
      allow(Gmail::WatchManager).to receive(:renew_all_watches)

      scheduler.start

      # Rufus scheduler should have 3 jobs scheduled
      expect(scheduler.scheduler.jobs.size).to eq(3)
    end
  end

  describe "sync job creation" do
    it "creates sync jobs for active onboarded users" do
      user = create(:user, :onboarded, is_active: true)
      create(:user, is_active: false) # inactive user

      # Directly test the private method's behavior
      scheduler.send(:enqueue_sync_for_all_users, force_full: false)

      expect(Job.count).to eq(1)
      job = Job.last
      expect(job.user).to eq(user)
      expect(job.job_type).to eq("sync")
      expect(JSON.parse(job.payload)["history_id"]).to eq("")
    end

    it "creates full sync jobs with force_full flag" do
      create(:user, :onboarded, is_active: true)

      scheduler.send(:enqueue_sync_for_all_users, force_full: true)

      job = Job.last
      payload = JSON.parse(job.payload)
      expect(payload["force_full"]).to eq(true)
    end
  end
end
