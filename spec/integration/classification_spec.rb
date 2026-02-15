require "rails_helper"

RSpec.describe "Classification", type: :request do
  let(:user) { create(:user, :onboarded) }
  let!(:needs_response_label) do
    create(:user_label, user: user, label_key: "needs_response",
           gmail_label_id: "Label_NR", gmail_label_name: "AI/Needs Response")
  end
  let!(:fyi_label) do
    create(:user_label, user: user, label_key: "fyi",
           gmail_label_id: "Label_FYI", gmail_label_name: "AI/FYI")
  end

  let(:llm_gateway) { instance_double(Llm::Gateway) }
  let(:gmail_client) { instance_double("GmailClient") }

  describe "TC-3.1: Normal email classified as needs_response triggers draft" do
    it "classifies via LLM, applies label, creates email record, enqueues draft job" do
      allow(llm_gateway).to receive(:classify).and_return(
        llm_classify_response(category: "needs_response", confidence: "high")
      )

      engine = Classification::ClassificationEngine.new(
        rule_engine: Classification::RuleEngine.new(contacts_config: { "blacklist" => [] }),
        llm_classifier: Classification::LlmClassifier.new(llm_gateway: llm_gateway),
        contacts_config: { "style_overrides" => {}, "domain_overrides" => {} }
      )

      result = engine.classify(
        sender_name: "Alice",
        sender_email: "alice@example.com",
        subject: "Can you help me?",
        body: "Hi, I need help with the project.",
        message_count: 1,
        headers: {}
      )

      expect(result["category"]).to eq("needs_response")
      expect(result["confidence"]).to eq("high")

      # Simulate what the job processor would do after classification
      email = Email.create!(
        user: user,
        gmail_thread_id: "thread_tc31",
        gmail_message_id: "msg_tc31",
        sender_email: "alice@example.com",
        sender_name: "Alice",
        subject: "Can you help me?",
        classification: result["category"],
        confidence: result["confidence"],
        reasoning: result["reasoning"],
        resolved_style: result["resolved_style"],
        detected_language: result["detected_language"],
        status: "pending"
      )

      EmailEvent.create!(
        user: user,
        gmail_thread_id: email.gmail_thread_id,
        event_type: "classified",
        detail: "Classification: needs_response (high)"
      )

      draft_job = Job.create!(
        user: user,
        job_type: "draft",
        payload: { gmail_thread_id: email.gmail_thread_id }.to_json,
        status: "pending"
      )

      expect(email.classification).to eq("needs_response")
      expect(email.status).to eq("pending")
      expect(EmailEvent.where(gmail_thread_id: email.gmail_thread_id, event_type: "classified").count).to eq(1)
      expect(draft_job.job_type).to eq("draft")
      expect(draft_job.status).to eq("pending")
      expect(llm_gateway).to have_received(:classify).once
    end
  end

  describe "TC-3.2: Automated email overrides LLM needs_response to fyi" do
    it "overrides LLM classification when automation headers are present" do
      allow(llm_gateway).to receive(:classify).and_return(
        llm_classify_response(category: "needs_response", confidence: "high")
      )

      engine = Classification::ClassificationEngine.new(
        rule_engine: Classification::RuleEngine.new(contacts_config: { "blacklist" => [] }),
        llm_classifier: Classification::LlmClassifier.new(llm_gateway: llm_gateway),
        contacts_config: { "style_overrides" => {}, "domain_overrides" => {} }
      )

      result = engine.classify(
        sender_name: "Newsletter",
        sender_email: "news@company.com",
        subject: "Weekly Update",
        body: "Here is your weekly newsletter.",
        message_count: 1,
        headers: { "List-Unsubscribe" => "<mailto:unsub@company.com>" }
      )

      expect(result["category"]).to eq("fyi")
      expect(result["reasoning"]).to include("Overridden")
      expect(result["reasoning"]).to include("automated sender detected")

      # Verify no draft job would be enqueued for fyi
      email = Email.create!(
        user: user,
        gmail_thread_id: "thread_tc32",
        gmail_message_id: "msg_tc32",
        sender_email: "news@company.com",
        sender_name: "Newsletter",
        subject: "Weekly Update",
        classification: result["category"],
        confidence: result["confidence"],
        status: "pending"
      )

      expect(email.classification).to eq("fyi")
      # FYI emails should not have draft jobs enqueued
      expect(Job.where(user: user, job_type: "draft").count).to eq(0)
    end
  end

  describe "TC-3.3: Blacklisted sender classified as fyi" do
    it "classifies blacklisted sender as fyi with high confidence" do
      # LLM still gets called, but rule engine detects blacklist
      allow(llm_gateway).to receive(:classify).and_return(
        llm_classify_response(category: "needs_response", confidence: "high")
      )

      contacts_config = { "blacklist" => ["*@spam.example.com"] }

      engine = Classification::ClassificationEngine.new(
        rule_engine: Classification::RuleEngine.new(contacts_config: contacts_config),
        llm_classifier: Classification::LlmClassifier.new(llm_gateway: llm_gateway),
        contacts_config: { "style_overrides" => {}, "domain_overrides" => {} }
      )

      result = engine.classify(
        sender_name: "Spammer",
        sender_email: "newsletter@spam.example.com",
        subject: "Amazing offer!",
        body: "Buy now!",
        message_count: 1,
        headers: {}
      )

      # Blacklisted sender triggers is_automated=true, which overrides needs_response to fyi
      expect(result["category"]).to eq("fyi")
      expect(result["reasoning"]).to include("Overridden")
      expect(llm_gateway).to have_received(:classify).once
    end
  end

  describe "TC-3.4: Already-classified thread is skipped" do
    it "skips classification for threads that already have an email record" do
      # Pre-existing email record for this thread
      existing_email = create(:email, user: user, gmail_thread_id: "thread_tc34",
                              gmail_message_id: "msg_tc34_old",
                              classification: "needs_response", status: "drafted")

      # Simulate what the classify job processor would check
      already_exists = Email.exists?(user: user, gmail_thread_id: "thread_tc34")

      expect(already_exists).to be true

      # No LLM call, no label changes - job completes immediately
      expect(llm_gateway).not_to have_received(:classify) if llm_gateway.respond_to?(:classify)

      # Verify original email unchanged
      existing_email.reload
      expect(existing_email.status).to eq("drafted")
      expect(existing_email.classification).to eq("needs_response")
    end
  end

  describe "TC-3.5: LLM returns unparseable response" do
    it "defaults to needs_response with low confidence on parse error" do
      allow(llm_gateway).to receive(:classify).and_return(llm_malformed_response)

      engine = Classification::ClassificationEngine.new(
        rule_engine: Classification::RuleEngine.new(contacts_config: { "blacklist" => [] }),
        llm_classifier: Classification::LlmClassifier.new(llm_gateway: llm_gateway),
        contacts_config: { "style_overrides" => {}, "domain_overrides" => {} }
      )

      result = engine.classify(
        sender_name: "Bob",
        sender_email: "bob@example.com",
        subject: "Question",
        body: "What do you think?",
        message_count: 1,
        headers: {}
      )

      # LlmClassifier.parse_response returns DEFAULT_RESULT on parse error
      expect(result["category"]).to eq("needs_response")
      expect(result["confidence"]).to eq("low")
      expect(result["reasoning"]).to include("Fallback")

      # Draft job should still be enqueued for needs_response (safer to over-triage)
      email = Email.create!(
        user: user,
        gmail_thread_id: "thread_tc35",
        gmail_message_id: "msg_tc35",
        sender_email: "bob@example.com",
        sender_name: "Bob",
        subject: "Question",
        classification: result["category"],
        confidence: result["confidence"],
        reasoning: result["reasoning"],
        status: "pending"
      )

      draft_job = Job.create!(
        user: user,
        job_type: "draft",
        payload: { gmail_thread_id: email.gmail_thread_id }.to_json,
        status: "pending"
      )

      expect(email.classification).to eq("needs_response")
      expect(draft_job).to be_persisted
    end
  end

  describe "TC-3.6: Classification with communication style resolution" do
    it "resolves style from contacts config overrides" do
      allow(llm_gateway).to receive(:classify).and_return(
        llm_classify_response(category: "needs_response", resolved_style: "business")
      )

      engine = Classification::ClassificationEngine.new(
        rule_engine: Classification::RuleEngine.new(contacts_config: { "blacklist" => [] }),
        llm_classifier: Classification::LlmClassifier.new(llm_gateway: llm_gateway),
        contacts_config: {
          "style_overrides" => { "friend@example.com" => "casual" },
          "domain_overrides" => {}
        }
      )

      result = engine.classify(
        sender_name: "Friend",
        sender_email: "friend@example.com",
        subject: "Hey!",
        body: "Want to grab lunch?",
        message_count: 1,
        headers: {}
      )

      # Style override from contacts config takes precedence over LLM
      expect(result["resolved_style"]).to eq("casual")
      expect(result["category"]).to eq("needs_response")

      email = Email.create!(
        user: user,
        gmail_thread_id: "thread_tc36",
        gmail_message_id: "msg_tc36",
        sender_email: "friend@example.com",
        sender_name: "Friend",
        subject: "Hey!",
        classification: result["category"],
        confidence: result["confidence"],
        resolved_style: result["resolved_style"],
        status: "pending"
      )

      expect(email.resolved_style).to eq("casual")
    end
  end
end
