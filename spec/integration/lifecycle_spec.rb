require "rails_helper"

RSpec.describe "Lifecycle Management", type: :request do
  let(:user) { create(:user, :onboarded) }
  let!(:needs_response_label) do
    create(:user_label, user: user, label_key: "needs_response",
           gmail_label_id: "Label_NR", gmail_label_name: "AI/Needs Response")
  end
  let!(:outbox_label) do
    create(:user_label, user: user, label_key: "outbox",
           gmail_label_id: "Label_OB", gmail_label_name: "AI/Outbox")
  end
  let!(:rework_label) do
    create(:user_label, user: user, label_key: "rework",
           gmail_label_id: "Label_RW", gmail_label_name: "AI/Rework")
  end
  let!(:action_required_label) do
    create(:user_label, user: user, label_key: "action_required",
           gmail_label_id: "Label_AR", gmail_label_name: "AI/Action Required")
  end
  let!(:fyi_label) do
    create(:user_label, user: user, label_key: "fyi",
           gmail_label_id: "Label_FYI", gmail_label_name: "AI/FYI")
  end
  let!(:waiting_label) do
    create(:user_label, user: user, label_key: "waiting",
           gmail_label_id: "Label_W", gmail_label_name: "AI/Waiting")
  end
  let!(:payment_request_label) do
    create(:user_label, user: user, label_key: "payment_request",
           gmail_label_id: "Label_PR", gmail_label_name: "AI/Payment Requests")
  end
  let!(:done_label) do
    create(:user_label, user: user, label_key: "done",
           gmail_label_id: "Label_DONE", gmail_label_name: "AI/Done")
  end

  let(:gmail_client) { instance_double("GmailClient") }
  let(:llm_gateway) { instance_double(Llm::Gateway) }

  describe "TC-6.1: Done handler archives thread" do
    it "removes all AI labels and INBOX, updates status to archived" do
      email = create(:email, user: user, gmail_thread_id: "thread_tc61",
                     classification: "needs_response", status: "drafted",
                     draft_id: "draft_tc61")

      allow(gmail_client).to receive(:modify_thread)

      handler = Lifecycle::DoneHandler.new(gmail_client: gmail_client)
      handler.handle(email: email, user: user)

      email.reload
      expect(email.status).to eq("archived")
      expect(email.acted_at).to be_present

      # All AI labels + INBOX removed
      expect(gmail_client).to have_received(:modify_thread) do |**args|
        expect(args[:thread_id]).to eq(email.gmail_thread_id)
        expect(args[:add_label_ids]).to eq([])
        expect(args[:remove_label_ids]).to match_array([
          needs_response_label.gmail_label_id,
          outbox_label.gmail_label_id,
          rework_label.gmail_label_id,
          action_required_label.gmail_label_id,
          payment_request_label.gmail_label_id,
          fyi_label.gmail_label_id,
          waiting_label.gmail_label_id,
          "INBOX"
        ])
      end

      # archived event logged
      event = EmailEvent.find_by(gmail_thread_id: email.gmail_thread_id, event_type: "archived")
      expect(event).to be_present
      expect(event.detail).to include("Done handler")
    end
  end

  describe "TC-6.2: Sent detection when draft disappears" do
    it "detects sent draft and updates status" do
      email = create(:email, user: user, gmail_thread_id: "thread_tc62",
                     classification: "needs_response", status: "drafted",
                     draft_id: "draft_tc62")

      # Draft no longer exists (user sent it)
      allow(gmail_client).to receive(:draft_exists?).with(draft_id: "draft_tc62").and_return(false)
      allow(gmail_client).to receive(:modify_thread)

      detector = Lifecycle::SentDetector.new(gmail_client: gmail_client)
      detector.handle(email: email, user: user)

      email.reload
      expect(email.status).to eq("sent")
      expect(email.acted_at).to be_present

      # Outbox label removed
      expect(gmail_client).to have_received(:modify_thread).with(
        thread_id: email.gmail_thread_id,
        add_label_ids: [],
        remove_label_ids: [outbox_label.gmail_label_id]
      )

      # sent_detected event logged
      event = EmailEvent.find_by(gmail_thread_id: email.gmail_thread_id, event_type: "sent_detected")
      expect(event).to be_present
      expect(event.detail).to include("draft_tc62")
    end
  end

  describe "TC-6.3: Sent detection when draft still exists" do
    it "makes no changes when draft is still present" do
      email = create(:email, user: user, gmail_thread_id: "thread_tc63",
                     classification: "needs_response", status: "drafted",
                     draft_id: "draft_tc63")

      # Draft still exists
      allow(gmail_client).to receive(:draft_exists?).with(draft_id: "draft_tc63").and_return(true)

      detector = Lifecycle::SentDetector.new(gmail_client: gmail_client)
      detector.handle(email: email, user: user)

      email.reload
      expect(email.status).to eq("drafted")
      expect(email.acted_at).to be_nil

      # No label modifications
      expect(gmail_client).not_to have_received(:modify_thread) if gmail_client.respond_to?(:modify_thread)

      # No events logged
      expect(EmailEvent.where(gmail_thread_id: email.gmail_thread_id, event_type: "sent_detected").count).to eq(0)
    end
  end

  describe "TC-6.4: Manual draft triggered by user label" do
    it "creates email record and generates draft for manually labeled thread" do
      # User applies "Needs Response" label to an unclassified thread
      # This simulates what would happen after sync detects the label change

      allow(llm_gateway).to receive(:draft).and_return(llm_draft_response)
      allow(llm_gateway).to receive(:context_query).and_return("[]")

      allow(gmail_client).to receive(:get_thread).and_return({
        body: "Hi, I wanted to discuss the proposal.",
        subject: "Proposal discussion"
      })
      allow(gmail_client).to receive(:search_threads).and_return([])
      allow(gmail_client).to receive(:create_draft).and_return("draft_tc64")
      allow(gmail_client).to receive(:modify_thread)

      # Step 1: Create email record for manually labeled thread
      email = Email.create!(
        user: user,
        gmail_thread_id: "thread_tc64",
        gmail_message_id: "msg_tc64",
        sender_email: "partner@example.com",
        sender_name: "Partner",
        subject: "Proposal discussion",
        classification: "needs_response",
        confidence: "high",
        reasoning: "Manually requested by user",
        status: "pending",
        resolved_style: "business",
        detected_language: "en"
      )

      expect(email.reasoning).to eq("Manually requested by user")

      # Step 2: Generate draft
      context_gatherer = Drafting::ContextGatherer.new(
        llm_gateway: llm_gateway,
        gmail_client: gmail_client
      )
      draft_generator = Drafting::DraftGenerator.new(
        llm_gateway: llm_gateway,
        styles_config: { "styles" => { "business" => { "rules" => [], "sign_off" => "" } } }
      )

      related_context = context_gatherer.gather(
        sender_email: email.sender_email,
        subject: email.subject,
        body: "Hi, I wanted to discuss the proposal.",
        gmail_thread_id: email.gmail_thread_id
      )

      draft_body = draft_generator.generate(
        sender_name: email.sender_name,
        sender_email: email.sender_email,
        subject: email.subject,
        thread_body: "Hi, I wanted to discuss the proposal.",
        resolved_style: email.resolved_style,
        detected_language: email.detected_language,
        related_context: related_context
      )

      # Create Gmail draft
      new_draft_id = gmail_client.create_draft(
        thread_id: email.gmail_thread_id,
        body: draft_body,
        subject: "Re: #{email.subject}"
      )

      # Transition labels: Needs Response -> Outbox
      gmail_client.modify_thread(
        thread_id: email.gmail_thread_id,
        add_label_ids: [outbox_label.gmail_label_id],
        remove_label_ids: [needs_response_label.gmail_label_id]
      )

      email.update!(status: "drafted", draft_id: new_draft_id)

      EmailEvent.create!(
        user: user,
        gmail_thread_id: email.gmail_thread_id,
        event_type: "draft_created",
        detail: "Draft created for manually labeled thread",
        draft_id: new_draft_id
      )

      email.reload
      expect(email.classification).to eq("needs_response")
      expect(email.status).to eq("drafted")
      expect(email.draft_id).to eq("draft_tc64")
      expect(email.reasoning).to eq("Manually requested by user")

      event = EmailEvent.find_by(gmail_thread_id: email.gmail_thread_id, event_type: "draft_created")
      expect(event).to be_present

      expect(gmail_client).to have_received(:create_draft).once
      expect(gmail_client).to have_received(:modify_thread).with(
        thread_id: email.gmail_thread_id,
        add_label_ids: [outbox_label.gmail_label_id],
        remove_label_ids: [needs_response_label.gmail_label_id]
      )
    end
  end
end
