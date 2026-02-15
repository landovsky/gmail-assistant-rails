require "rails_helper"

RSpec.describe "Classification", type: :request do
  describe "TC-3.1: Normal email classified as needs_response triggers draft" do
    xit "classifies via LLM, applies label, creates email record, enqueues draft job" do
      # Preconditions: User onboarded. Gmail returns a personal email with a question.
      # Actions: Process a classify job for this email
      # Expected:
      # - LLM called with classification prompt
      # - Email record created with classification=needs_response
      # - "Needs Response" label applied to message in Gmail
      # - classified event logged
      # - draft job enqueued
      # - Email status=pending
    end
  end

  describe "TC-3.2: Automated email overrides LLM needs_response to fyi" do
    xit "overrides LLM classification when automation headers are present" do
      # Preconditions: Email has List-Unsubscribe header. LLM returns needs_response.
      # Actions: Process a classify job
      # Expected:
      # - Rule engine detects is_automated=true
      # - LLM classification of needs_response is overridden to fyi
      # - "FYI" label applied (not "Needs Response")
      # - No draft job enqueued
    end
  end

  describe "TC-3.3: Blacklisted sender classified as fyi" do
    xit "classifies blacklisted sender as fyi with high confidence" do
      # Preconditions: User settings include blacklist pattern *@spam.example.com.
      #   Email is from newsletter@spam.example.com.
      # Actions: Process a classify job
      # Expected:
      # - Rule engine matches blacklist
      # - Classified as fyi with high confidence
      # - LLM still called (rule shortcut disabled), but safety net applies
      # - No draft job enqueued
    end
  end

  describe "TC-3.4: Already-classified thread is skipped" do
    xit "skips classification for threads that already have an email record" do
      # Preconditions: Thread already has an email record in the database.
      # Actions: Process a classify job for a new message in the same thread
      # Expected:
      # - Job completes immediately with no changes
      # - No LLM call made
      # - No label changes
    end
  end

  describe "TC-3.5: LLM returns unparseable response" do
    xit "defaults to needs_response with low confidence on parse error" do
      # Preconditions: LLM returns non-JSON text.
      # Actions: Process a classify job
      # Expected:
      # - Defaults to needs_response with low confidence
      # - Reasoning contains parse error info
      # - Draft job is still enqueued (safer to over-triage)
    end
  end

  describe "TC-3.6: Classification with communication style resolution" do
    xit "resolves style from contacts config overrides" do
      # Preconditions: Contacts config has style_overrides:
      #   {"friend@example.com": "casual"}.
      # Actions: Process a classify job for email from friend@example.com
      # Expected:
      # - resolved_style set to casual on the email record
    end
  end
end
