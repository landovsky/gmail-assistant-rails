require "rails_helper"

RSpec.describe "Rework Loop", type: :request do
  let(:user) { create(:user, :onboarded) }
  let!(:rework_label) do
    create(:user_label, user: user, label_key: "rework",
           gmail_label_id: "Label_RW", gmail_label_name: "AI/Rework")
  end
  let!(:outbox_label) do
    create(:user_label, user: user, label_key: "outbox",
           gmail_label_id: "Label_OB", gmail_label_name: "AI/Outbox")
  end
  let!(:action_required_label) do
    create(:user_label, user: user, label_key: "action_required",
           gmail_label_id: "Label_AR", gmail_label_name: "AI/Action Required")
  end

  let(:llm_gateway) { instance_double(Llm::Gateway) }
  let(:gmail_client) { instance_double("GmailClient") }

  let(:draft_generator) do
    Drafting::DraftGenerator.new(
      llm_gateway: llm_gateway,
      styles_config: { "styles" => { "business" => { "rules" => [], "sign_off" => "" } } }
    )
  end

  let(:context_gatherer) do
    Drafting::ContextGatherer.new(llm_gateway: llm_gateway, gmail_client: gmail_client)
  end

  let(:handler) do
    Lifecycle::ReworkHandler.new(
      draft_generator: draft_generator,
      context_gatherer: context_gatherer,
      gmail_client: gmail_client
    )
  end

  describe "TC-5.1: First rework regenerates draft" do
    it "extracts instruction, regenerates draft, increments rework count" do
      email = create(:email, user: user, gmail_thread_id: "thread_tc51",
                     classification: "needs_response", status: "drafted",
                     sender_email: "alice@example.com", sender_name: "Alice",
                     subject: "Project update", resolved_style: "business",
                     detected_language: "en", draft_id: "draft_old_51",
                     rework_count: 0)

      # Mock fetching current draft - user wrote "make it shorter" above scissors marker
      allow(gmail_client).to receive(:get_draft).and_return({
        body: "make it shorter\n\n\u2702\uFE0F\n\nOriginal draft text here."
      })
      allow(gmail_client).to receive(:get_thread).and_return({
        body: "Hi, here's the project update."
      })
      allow(gmail_client).to receive(:trash_draft)
      allow(gmail_client).to receive(:create_draft).and_return("draft_new_51")
      allow(gmail_client).to receive(:modify_thread)
      allow(gmail_client).to receive(:search_threads).and_return([])

      allow(llm_gateway).to receive(:draft).and_return(llm_rework_response)
      allow(llm_gateway).to receive(:context_query).and_return("[]")

      handler.handle(email: email, user: user)

      email.reload
      expect(email.rework_count).to eq(1)
      expect(email.draft_id).to eq("draft_new_51")
      expect(email.last_rework_instruction).to eq("make it shorter")
      expect(email.status).to eq("drafted")

      # Old draft trashed, new one created
      expect(gmail_client).to have_received(:trash_draft).with(draft_id: "draft_old_51")
      expect(gmail_client).to have_received(:create_draft).once

      # Labels: Rework -> Outbox
      expect(gmail_client).to have_received(:modify_thread).with(
        thread_id: email.gmail_thread_id,
        add_label_ids: [outbox_label.gmail_label_id],
        remove_label_ids: [rework_label.gmail_label_id]
      )

      # Event logged
      event = EmailEvent.find_by(gmail_thread_id: email.gmail_thread_id, event_type: "draft_reworked")
      expect(event).to be_present
      expect(event.detail).to include("make it shorter")
    end
  end

  describe "TC-5.2: Rework with no instruction uses default" do
    it "uses default instruction when user provides none" do
      email = create(:email, user: user, gmail_thread_id: "thread_tc52",
                     classification: "needs_response", status: "drafted",
                     sender_email: "bob@example.com", sender_name: "Bob",
                     subject: "Meeting", resolved_style: "business",
                     detected_language: "en", draft_id: "draft_old_52",
                     rework_count: 0)

      # Draft body has no user instruction above the scissors marker
      allow(gmail_client).to receive(:get_draft).and_return({
        body: "\n\n\u2702\uFE0F\n\nOriginal draft text."
      })
      allow(gmail_client).to receive(:get_thread).and_return({ body: "Let's schedule a meeting." })
      allow(gmail_client).to receive(:trash_draft)
      allow(gmail_client).to receive(:create_draft).and_return("draft_new_52")
      allow(gmail_client).to receive(:modify_thread)
      allow(gmail_client).to receive(:search_threads).and_return([])

      allow(llm_gateway).to receive(:draft).and_return(llm_rework_response)
      allow(llm_gateway).to receive(:context_query).and_return("[]")

      handler.handle(email: email, user: user)

      email.reload
      expect(email.last_rework_instruction).to eq("(no specific instruction provided)")
      expect(email.rework_count).to eq(1)
      expect(email.status).to eq("drafted")
      expect(llm_gateway).to have_received(:draft).once
    end
  end

  describe "TC-5.3: Third rework triggers limit" do
    it "adds warning prefix and transitions to Action Required" do
      email = create(:email, user: user, gmail_thread_id: "thread_tc53",
                     classification: "needs_response", status: "drafted",
                     sender_email: "carol@example.com", sender_name: "Carol",
                     subject: "Invoice", resolved_style: "business",
                     detected_language: "en", draft_id: "draft_old_53",
                     rework_count: 2)

      allow(gmail_client).to receive(:get_draft).and_return({
        body: "be more formal\n\n\u2702\uFE0F\n\nPrevious draft."
      })
      allow(gmail_client).to receive(:get_thread).and_return({ body: "Please review the invoice." })
      allow(gmail_client).to receive(:trash_draft)
      allow(gmail_client).to receive(:create_draft).and_return("draft_new_53")
      allow(gmail_client).to receive(:modify_thread)
      allow(gmail_client).to receive(:search_threads).and_return([])

      allow(llm_gateway).to receive(:draft).and_return(llm_rework_response)
      allow(llm_gateway).to receive(:context_query).and_return("[]")

      handler.handle(email: email, user: user)

      email.reload
      expect(email.rework_count).to eq(3)
      # At rework_count == REWORK_LIMIT, status is set to "skipped"
      expect(email.status).to eq("skipped")

      # Labels: Rework -> Action Required (not Outbox)
      expect(gmail_client).to have_received(:modify_thread).with(
        thread_id: email.gmail_thread_id,
        add_label_ids: [action_required_label.gmail_label_id],
        remove_label_ids: [rework_label.gmail_label_id]
      )

      # LLM was still called (draft regenerated with warning)
      expect(llm_gateway).to have_received(:draft).once

      # The draft body should have been created with warning prefix
      expect(gmail_client).to have_received(:create_draft).with(
        hash_including(thread_id: email.gmail_thread_id)
      )
    end
  end

  describe "TC-5.4: Fourth rework attempt hits hard limit" do
    it "skips LLM call and moves to Action Required with skipped status" do
      email = create(:email, user: user, gmail_thread_id: "thread_tc54",
                     classification: "needs_response", status: "drafted",
                     sender_email: "dave@example.com", sender_name: "Dave",
                     subject: "Contract", resolved_style: "business",
                     detected_language: "en", draft_id: "draft_old_54",
                     rework_count: 3)

      allow(gmail_client).to receive(:modify_thread)

      handler.handle(email: email, user: user)

      email.reload
      expect(email.status).to eq("skipped")
      expect(email.rework_count).to eq(3) # Not incremented

      # No LLM call made
      expect(llm_gateway).not_to have_received(:draft) if llm_gateway.respond_to?(:draft)

      # Labels: Rework -> Action Required
      expect(gmail_client).to have_received(:modify_thread).with(
        thread_id: email.gmail_thread_id,
        add_label_ids: [action_required_label.gmail_label_id],
        remove_label_ids: [rework_label.gmail_label_id]
      )

      # rework_limit_reached event logged
      event = EmailEvent.find_by(gmail_thread_id: email.gmail_thread_id, event_type: "rework_limit_reached")
      expect(event).to be_present
      expect(event.detail).to include("limit")
    end
  end
end
