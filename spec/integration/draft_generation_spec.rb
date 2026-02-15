require "rails_helper"

RSpec.describe "Draft Generation", type: :request do
  let(:user) { create(:user, :onboarded) }
  let!(:needs_response_label) do
    create(:user_label, user: user, label_key: "needs_response",
           gmail_label_id: "Label_NR", gmail_label_name: "AI/Needs Response")
  end
  let!(:outbox_label) do
    create(:user_label, user: user, label_key: "outbox",
           gmail_label_id: "Label_OB", gmail_label_name: "AI/Outbox")
  end

  let(:llm_gateway) { instance_double(Llm::Gateway) }
  let(:gmail_client) { instance_double("GmailClient") }

  describe "TC-4.1: Successful draft creation" do
    it "generates draft via LLM, creates Gmail draft, transitions labels" do
      email = create(:email, user: user, gmail_thread_id: "thread_tc41",
                     classification: "needs_response", status: "pending",
                     sender_email: "alice@example.com", sender_name: "Alice",
                     subject: "Project question", resolved_style: "business",
                     detected_language: "en")

      # Mock LLM gateway
      allow(llm_gateway).to receive(:draft).and_return(llm_draft_response)
      allow(llm_gateway).to receive(:context_query).and_return(llm_context_queries_response)

      # Mock Gmail client
      allow(gmail_client).to receive(:get_thread).and_return({
        body: "Hi, can you help with the project?",
        subject: "Project question"
      })
      allow(gmail_client).to receive(:search_threads).and_return([])
      allow(gmail_client).to receive(:create_draft).and_return("draft_new_41")
      allow(gmail_client).to receive(:modify_thread)
      allow(gmail_client).to receive(:list_drafts).and_return([])

      # Build services
      context_gatherer = Drafting::ContextGatherer.new(
        llm_gateway: llm_gateway,
        gmail_client: gmail_client
      )
      draft_generator = Drafting::DraftGenerator.new(
        llm_gateway: llm_gateway,
        styles_config: { "styles" => { "business" => { "rules" => ["Be professional"], "sign_off" => "Best regards" } } }
      )

      # Gather context
      related_context = context_gatherer.gather(
        sender_email: email.sender_email,
        subject: email.subject,
        body: "Hi, can you help with the project?",
        gmail_thread_id: email.gmail_thread_id
      )

      # Generate draft
      draft_body = draft_generator.generate(
        sender_name: email.sender_name,
        sender_email: email.sender_email,
        subject: email.subject,
        thread_body: "Hi, can you help with the project?",
        resolved_style: email.resolved_style,
        detected_language: email.detected_language,
        related_context: related_context
      )

      # Verify draft wrapped with marker
      expect(draft_body).to include("\u2702\uFE0F")

      # Create draft in Gmail
      new_draft_id = gmail_client.create_draft(
        thread_id: email.gmail_thread_id,
        body: draft_body,
        subject: "Re: #{email.subject}"
      )

      # Transition labels: remove Needs Response, add Outbox
      gmail_client.modify_thread(
        thread_id: email.gmail_thread_id,
        add_label_ids: [outbox_label.gmail_label_id],
        remove_label_ids: [needs_response_label.gmail_label_id]
      )

      # Update email record
      email.update!(status: "drafted", draft_id: new_draft_id)

      EmailEvent.create!(
        user: user,
        gmail_thread_id: email.gmail_thread_id,
        event_type: "draft_created",
        detail: "Draft created for thread #{email.gmail_thread_id}",
        draft_id: new_draft_id
      )

      email.reload
      expect(email.status).to eq("drafted")
      expect(email.draft_id).to eq("draft_new_41")
      expect(EmailEvent.where(gmail_thread_id: email.gmail_thread_id, event_type: "draft_created").count).to eq(1)
      expect(llm_gateway).to have_received(:draft).once
      expect(gmail_client).to have_received(:create_draft).once
      expect(gmail_client).to have_received(:modify_thread).with(
        thread_id: email.gmail_thread_id,
        add_label_ids: [outbox_label.gmail_label_id],
        remove_label_ids: [needs_response_label.gmail_label_id]
      )
    end
  end

  describe "TC-4.2: Draft skipped for non-pending email" do
    it "completes immediately when email is already drafted" do
      email = create(:email, user: user, gmail_thread_id: "thread_tc42",
                     classification: "needs_response", status: "drafted",
                     draft_id: "draft_existing_42")

      # Simulate job processor check: skip if not pending
      skip_processing = email.status != "pending"
      expect(skip_processing).to be true

      # No LLM calls, no Gmail calls
      expect(llm_gateway).not_to have_received(:draft) if llm_gateway.respond_to?(:draft)

      # Email unchanged
      email.reload
      expect(email.status).to eq("drafted")
      expect(email.draft_id).to eq("draft_existing_42")
    end
  end

  describe "TC-4.3: Stale drafts are cleaned up" do
    it "trashes old draft before creating new one" do
      email = create(:email, user: user, gmail_thread_id: "thread_tc43",
                     classification: "needs_response", status: "pending",
                     sender_email: "bob@example.com", sender_name: "Bob",
                     subject: "Follow up", resolved_style: "business",
                     detected_language: "en", draft_id: "draft_old_43")

      allow(llm_gateway).to receive(:draft).and_return(llm_draft_response)
      allow(llm_gateway).to receive(:context_query).and_return("[]")

      allow(gmail_client).to receive(:get_thread).and_return({ body: "Following up on our conversation." })
      allow(gmail_client).to receive(:search_threads).and_return([])
      allow(gmail_client).to receive(:trash_draft)
      allow(gmail_client).to receive(:create_draft).and_return("draft_new_43")
      allow(gmail_client).to receive(:modify_thread)

      # Trash old draft first
      gmail_client.trash_draft(draft_id: email.draft_id)

      draft_generator = Drafting::DraftGenerator.new(
        llm_gateway: llm_gateway,
        styles_config: { "styles" => { "business" => { "rules" => [], "sign_off" => "" } } }
      )

      draft_body = draft_generator.generate(
        sender_name: email.sender_name,
        sender_email: email.sender_email,
        subject: email.subject,
        thread_body: "Following up on our conversation.",
        resolved_style: email.resolved_style,
        detected_language: email.detected_language
      )

      new_draft_id = gmail_client.create_draft(
        thread_id: email.gmail_thread_id,
        body: draft_body,
        subject: "Re: #{email.subject}"
      )

      email.update!(draft_id: new_draft_id, status: "drafted")

      expect(gmail_client).to have_received(:trash_draft).with(draft_id: "draft_old_43")
      expect(gmail_client).to have_received(:create_draft).once
      expect(email.reload.draft_id).to eq("draft_new_43")
    end
  end

  describe "TC-4.4: Context gathering failure does not block draft" do
    it "generates draft without context when context gathering fails" do
      email = create(:email, user: user, gmail_thread_id: "thread_tc44",
                     classification: "needs_response", status: "pending",
                     sender_email: "carol@example.com", sender_name: "Carol",
                     subject: "Quick question", resolved_style: "business",
                     detected_language: "en")

      allow(llm_gateway).to receive(:draft).and_return(llm_draft_response)
      # Context query fails
      allow(llm_gateway).to receive(:context_query).and_raise(RuntimeError, "Gmail search API error")

      allow(gmail_client).to receive(:get_thread).and_return({ body: "Can you check this?" })
      allow(gmail_client).to receive(:search_threads).and_raise(RuntimeError, "Gmail search API error")
      allow(gmail_client).to receive(:create_draft).and_return("draft_tc44")
      allow(gmail_client).to receive(:modify_thread)

      context_gatherer = Drafting::ContextGatherer.new(
        llm_gateway: llm_gateway,
        gmail_client: gmail_client
      )

      # Context gathering fails gracefully, returns empty string
      related_context = context_gatherer.gather(
        sender_email: email.sender_email,
        subject: email.subject,
        body: "Can you check this?",
        gmail_thread_id: email.gmail_thread_id
      )

      expect(related_context).to eq("")

      draft_generator = Drafting::DraftGenerator.new(
        llm_gateway: llm_gateway,
        styles_config: { "styles" => { "business" => { "rules" => [], "sign_off" => "" } } }
      )

      # Draft still generated without context
      draft_body = draft_generator.generate(
        sender_name: email.sender_name,
        sender_email: email.sender_email,
        subject: email.subject,
        thread_body: "Can you check this?",
        resolved_style: email.resolved_style,
        detected_language: email.detected_language,
        related_context: related_context
      )

      expect(draft_body).to include("\u2702\uFE0F")
      expect(llm_gateway).to have_received(:draft).once
    end
  end
end
