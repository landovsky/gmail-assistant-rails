require "rails_helper"

RSpec.describe "Job Queue" do
  describe "TC-8.1: Concurrent workers don't process same job" do
    it "ensures exactly one worker claims a pending job" do
      job = create(:job, status: "pending", job_type: "classify", max_attempts: 3)

      # First worker claims the job
      claimed1 = Job.claim_next
      expect(claimed1).to be_present
      expect(claimed1.id).to eq(job.id)

      # Second worker tries to claim - no pending jobs left
      claimed2 = Job.claim_next
      expect(claimed2).to be_nil

      # The job should be in running state with 1 attempt
      job.reload
      expect(job.status).to eq("running")
      expect(job.attempts).to eq(1)
    end
  end

  describe "TC-8.2: Failed job retries up to max_attempts" do
    it "retries failed jobs and marks as failed after max attempts" do
      job = create(:job, status: "pending", job_type: "classify", max_attempts: 3)

      # Attempt 1: claim and fail
      claimed = Job.claim_next
      expect(claimed).to be_present
      expect(claimed.attempts).to eq(1)
      claimed.fail!("API error attempt 1")

      # Job should be back to pending for retry
      job.reload
      expect(job.status).to eq("pending")
      expect(job.error_message).to eq("API error attempt 1")

      # Attempt 2: claim and fail
      claimed = Job.claim_next
      expect(claimed).to be_present
      expect(claimed.attempts).to eq(2)
      claimed.fail!("API error attempt 2")

      job.reload
      expect(job.status).to eq("pending")

      # Attempt 3: claim and fail (max_attempts reached)
      claimed = Job.claim_next
      expect(claimed).to be_present
      expect(claimed.attempts).to eq(3)
      claimed.fail!("API error attempt 3")

      # After max attempts, job should be permanently failed
      job.reload
      expect(job.status).to eq("failed")
      expect(job.error_message).to eq("API error attempt 3")
      expect(job.completed_at).to be_present

      # No more retries - claim_next should return nil
      expect(Job.claim_next).to be_nil
    end
  end

  describe "TC-8.3: Successful retry after transient failure" do
    it "completes job on second attempt after transient failure" do
      job = create(:job, status: "pending", job_type: "classify", max_attempts: 3)

      # Attempt 1: claim and fail (transient error)
      claimed = Job.claim_next
      expect(claimed).to be_present
      expect(claimed.attempts).to eq(1)
      claimed.fail!("Transient network error")

      job.reload
      expect(job.status).to eq("pending")

      # Attempt 2: claim and succeed
      claimed = Job.claim_next
      expect(claimed).to be_present
      expect(claimed.attempts).to eq(2)
      claimed.complete!

      # Job should be completed
      job.reload
      expect(job.status).to eq("completed")
      expect(job.attempts).to eq(2)
      expect(job.completed_at).to be_present
    end
  end
end
