require "rails_helper"

RSpec.describe Job, type: :model do
  describe ".claim_next" do
    it "claims the oldest pending job" do
      user = create(:user)
      old_job = create(:job, user: user, created_at: 1.hour.ago)
      create(:job, user: user, created_at: 1.minute.ago)

      claimed = Job.claim_next
      expect(claimed.id).to eq(old_job.id)
      expect(claimed.status).to eq("running")
      expect(claimed.attempts).to eq(1)
    end

    it "returns nil when no pending jobs" do
      expect(Job.claim_next).to be_nil
    end

    it "skips jobs that exceeded max_attempts" do
      user = create(:user)
      create(:job, user: user, attempts: 3, max_attempts: 3)
      expect(Job.claim_next).to be_nil
    end
  end

  describe "#fail!" do
    it "retries when attempts remaining" do
      job = create(:job, user: create(:user), attempts: 1, max_attempts: 3, status: "running")
      job.fail!("transient error")
      expect(job.reload.status).to eq("pending")
    end

    it "permanently fails when no attempts remaining" do
      job = create(:job, user: create(:user), attempts: 3, max_attempts: 3, status: "running")
      job.fail!("permanent error")
      expect(job.reload.status).to eq("failed")
    end
  end
end
