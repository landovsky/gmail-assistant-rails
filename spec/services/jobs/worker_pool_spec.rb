require "rails_helper"

RSpec.describe Jobs::WorkerPool do
  let(:pool) { described_class.new(concurrency: 1) }

  before do
    # Stub Gmail::Client to avoid real auth
    allow(Gmail::Client).to receive(:new).and_return(instance_double(Gmail::Client))
  end

  describe "#start and #stop" do
    it "starts and stops workers" do
      pool.start
      expect(pool.running).to be true

      pool.stop
      expect(pool.running).to be false
    end
  end

  describe "job processing" do
    it "processes a pending job to completion" do
      user = create(:user, :onboarded)
      job = create(:job, user: user, job_type: "classify", payload: { thread_id: "t1" }.to_json)

      allow_any_instance_of(Jobs::ClassifyHandler).to receive(:perform)

      pool.start
      # Give worker time to pick up the job
      sleep(0.5)
      pool.stop

      job.reload
      expect(job.status).to eq("completed")
    end

    it "fails a job when handler raises" do
      user = create(:user, :onboarded)
      job = create(:job, user: user, job_type: "classify", payload: { thread_id: "t1" }.to_json, max_attempts: 1)

      allow_any_instance_of(Jobs::ClassifyHandler).to receive(:perform).and_raise("Something broke")

      pool.start
      sleep(0.5)
      pool.stop

      job.reload
      expect(job.status).to eq("failed")
      expect(job.error_message).to include("Something broke")
    end

    it "retries a job when attempts remain" do
      user = create(:user, :onboarded)
      job = create(:job, user: user, job_type: "classify", payload: { thread_id: "t1" }.to_json, max_attempts: 3)

      call_count = 0
      allow_any_instance_of(Jobs::ClassifyHandler).to receive(:perform) do
        call_count += 1
        raise "Transient error" if call_count == 1
      end

      pool.start
      sleep(1.5) # Need enough time for retry cycle
      pool.stop

      job.reload
      expect(job.status).to eq("completed")
      expect(job.attempts).to eq(2)
    end
  end
end
