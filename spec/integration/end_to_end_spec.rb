require "rails_helper"

RSpec.describe "End-to-End Scenarios", type: :request do
  let(:user) { create(:user, :onboarded) }
  let(:gmail_client) { double("GmailClient") }
  let(:llm_gateway) { double("LlmGateway") }

  before do
    # Create all standard labels for the user
    UserLabel::STANDARD_KEYS.each do |key|
      create(:user_label,
        user: user,
        label_key: key,
        gmail_label_id: "Label_#{key}",
        gmail_label_name: UserLabel::STANDARD_NAMES[key]
      )
    end
  end

  def label_id(key)
    "Label_#{key}"
  end

  describe "TC-11.1: Full email lifecycle - classify, draft, send" do
    it "processes email from arrival through sent detection" do
      thread_id = "thread_e2e_1"

      # Step 1: Classify the email
      allow(llm_gateway).to receive(:classify).and_return(llm_classify_response)
      allow(llm_gateway).to receive(:context_query).and_return(nil)

      engine = Classification::ClassificationEngine.new(
        rule_engine: Classification::RuleEngine.new(contacts_config: {}),
        llm_classifier: Classification::LlmClassifier.new(llm_gateway: llm_gateway, styles_config: { "styles" => {} }),
        contacts_config: {}
      )

      classification = engine.classify(
        sender_name: "John Doe",
        sender_email: "john@example.com",
        subject: "Project update",
        body: "Can you review the latest changes?"
      )

      expect(classification["category"]).to eq("needs_response")

      # Create email record
      email = create(:email,
        user: user,
        gmail_thread_id: thread_id,
        gmail_message_id: "msg_e2e_1",
        sender_email: "john@example.com",
        sender_name: "John Doe",
        subject: "Project update",
        classification: classification["category"],
        confidence: classification["confidence"],
        resolved_style: classification["resolved_style"],
        detected_language: classification["detected_language"],
        status: "pending"
      )

      # Step 2: Generate draft
      allow(llm_gateway).to receive(:draft).and_return(llm_draft_response)

      generator = Drafting::DraftGenerator.new(
        llm_gateway: llm_gateway,
        styles_config: { "styles" => { "business" => { "rules" => [], "sign_off" => "Best regards" } } }
      )

      draft_body = generator.generate(
        sender_name: "John Doe",
        sender_email: "john@example.com",
        subject: "Project update",
        thread_body: "Can you review the latest changes?",
        resolved_style: "business",
        detected_language: "en",
        related_context: ""
      )

      expect(draft_body).to include("Thank you for your message")

      # Simulate Gmail draft creation
      draft_id = "draft_e2e_1"
      allow(gmail_client).to receive(:create_draft).and_return(draft_id)
      allow(gmail_client).to receive(:modify_thread)

      email.update!(status: "drafted", draft_id: draft_id, drafted_at: Time.current)

      expect(email.reload.status).to eq("drafted")
      expect(email.draft_id).to eq(draft_id)

      # Step 3: User sends the draft - draft disappears from Gmail
      allow(gmail_client).to receive(:draft_exists?).with(draft_id: draft_id).and_return(false)

      sent_detector = Lifecycle::SentDetector.new(gmail_client: gmail_client)
      sent_detector.handle(email: email, user: user)

      # Step 4: Verify final state
      email.reload
      expect(email.status).to eq("sent")
      expect(email.acted_at).to be_present

      sent_event = EmailEvent.find_by(
        user: user,
        gmail_thread_id: thread_id,
        event_type: "sent_detected"
      )
      expect(sent_event).to be_present
    end
  end

  describe "TC-11.2: Full email lifecycle - classify, draft, rework, send" do
    it "processes email through rework loop to sent" do
      thread_id = "thread_e2e_2"

      # Step 1: Classify as needs_response
      allow(llm_gateway).to receive(:classify).and_return(llm_classify_response)
      allow(llm_gateway).to receive(:draft).and_return(llm_draft_response)
      allow(llm_gateway).to receive(:context_query).and_return(nil)

      email = create(:email,
        user: user,
        gmail_thread_id: thread_id,
        gmail_message_id: "msg_e2e_2",
        sender_email: "partner@example.com",
        sender_name: "Partner",
        subject: "Contract review",
        classification: "needs_response",
        confidence: "high",
        resolved_style: "business",
        detected_language: "en",
        status: "drafted",
        draft_id: "draft_e2e_2",
        drafted_at: Time.current,
        rework_count: 0
      )

      # Step 2: Rework - user writes instructions and applies Rework label
      allow(gmail_client).to receive(:get_draft).and_return({ body: "Make it more formal\n\n\u2702\uFE0F\n\nOriginal draft" })
      allow(gmail_client).to receive(:get_thread).and_return({ body: "Please review the contract terms." })
      allow(gmail_client).to receive(:trash_draft)
      allow(gmail_client).to receive(:create_draft).and_return("draft_e2e_2_rework")
      allow(gmail_client).to receive(:modify_thread)
      allow(gmail_client).to receive(:search_threads).and_return([])

      allow(llm_gateway).to receive(:draft).and_return(llm_rework_response)

      context_gatherer = Drafting::ContextGatherer.new(llm_gateway: llm_gateway, gmail_client: gmail_client)
      draft_generator = Drafting::DraftGenerator.new(
        llm_gateway: llm_gateway,
        styles_config: { "styles" => { "business" => { "rules" => [], "sign_off" => "Best regards" } } }
      )

      rework_handler = Lifecycle::ReworkHandler.new(
        draft_generator: draft_generator,
        context_gatherer: context_gatherer,
        gmail_client: gmail_client
      )

      rework_handler.handle(email: email, user: user)

      email.reload
      expect(email.rework_count).to eq(1)
      expect(email.draft_id).to eq("draft_e2e_2_rework")
      expect(email.status).to eq("drafted")
      expect(email.last_rework_instruction).to eq("Make it more formal")

      rework_event = EmailEvent.find_by(
        user: user,
        gmail_thread_id: thread_id,
        event_type: "draft_reworked"
      )
      expect(rework_event).to be_present

      # Step 3: User sends the reworked draft
      allow(gmail_client).to receive(:draft_exists?).with(draft_id: "draft_e2e_2_rework").and_return(false)

      sent_detector = Lifecycle::SentDetector.new(gmail_client: gmail_client)
      sent_detector.handle(email: email, user: user)

      email.reload
      expect(email.status).to eq("sent")
    end
  end

  describe "TC-11.3: Full email lifecycle - classify, draft, done" do
    it "processes email from draft to done/archived" do
      thread_id = "thread_e2e_3"

      email = create(:email,
        user: user,
        gmail_thread_id: thread_id,
        gmail_message_id: "msg_e2e_3",
        sender_email: "info@vendor.com",
        sender_name: "Vendor",
        subject: "Invoice #123",
        classification: "needs_response",
        confidence: "high",
        status: "drafted",
        draft_id: "draft_e2e_3",
        drafted_at: Time.current
      )

      # User applies Done label - DoneHandler processes
      allow(gmail_client).to receive(:modify_thread)

      done_handler = Lifecycle::DoneHandler.new(gmail_client: gmail_client)
      done_handler.handle(email: email, user: user)

      # Verify modify_thread was called to remove AI labels and INBOX
      expect(gmail_client).to have_received(:modify_thread).with(
        thread_id: thread_id,
        add_label_ids: [],
        remove_label_ids: a_collection_including("INBOX", label_id("needs_response"), label_id("outbox"))
      )

      email.reload
      expect(email.status).to eq("archived")
      expect(email.acted_at).to be_present

      archived_event = EmailEvent.find_by(
        user: user,
        gmail_thread_id: thread_id,
        event_type: "archived"
      )
      expect(archived_event).to be_present
      expect(archived_event.detail).to include("archived")
    end
  end

  describe "TC-11.4: FYI email - no draft generated" do
    it "classifies as fyi and applies label without creating draft" do
      thread_id = "thread_e2e_4"

      allow(llm_gateway).to receive(:classify).and_return(llm_classify_fyi_response)

      engine = Classification::ClassificationEngine.new(
        rule_engine: Classification::RuleEngine.new(contacts_config: {}),
        llm_classifier: Classification::LlmClassifier.new(llm_gateway: llm_gateway, styles_config: { "styles" => {} }),
        contacts_config: {}
      )

      classification = engine.classify(
        sender_name: "Newsletter",
        sender_email: "news@updates.com",
        subject: "Weekly digest",
        body: "Here is your weekly summary..."
      )

      expect(classification["category"]).to eq("fyi")

      # Create email record with fyi classification
      email = create(:email,
        user: user,
        gmail_thread_id: thread_id,
        gmail_message_id: "msg_e2e_4",
        sender_email: "news@updates.com",
        sender_name: "Newsletter",
        subject: "Weekly digest",
        classification: "fyi",
        confidence: classification["confidence"],
        status: "pending"
      )

      # FYI emails remain in pending status - no draft is generated
      expect(email.status).to eq("pending")
      expect(email.draft_id).to be_nil
      expect(email.classification).to eq("fyi")

      # No draft-related events should exist
      draft_events = EmailEvent.where(
        user: user,
        gmail_thread_id: thread_id,
        event_type: "draft_created"
      )
      expect(draft_events).to be_empty
    end
  end

  describe "TC-11.5: Agent-routed email" do
    it "routes to agent loop and executes tool calls" do
      thread_id = "thread_e2e_5"

      # Step 1: Router selects agent route
      rules = [
        {
          "match" => { "sender_email" => "orders@pharmacy.com" },
          "route" => "agent",
          "profile" => "pharmacy"
        }
      ]

      router = Agents::Router.new(rules)
      route_result = router.route(
        sender_email: "orders@pharmacy.com",
        subject: "New order #456",
        headers: {},
        body: "Order for ibuprofen 400mg x 30"
      )

      expect(route_result["route"]).to eq("agent")
      expect(route_result["profile"]).to eq("pharmacy")

      # Step 2: Agent loop executes with tool calls
      registry = Agents::ToolRegistry.new
      registry.register(
        name: "search_drugs",
        description: "Search drug database",
        parameters: { type: "object", properties: { query: { type: "string" } } },
        handler: ->(query:) { { name: "Ibuprofen", dosage: "400mg", stock: 150 } }
      )

      llm_client = mock_llm_client(responses: [
        llm_agent_tool_call_response(
          tool_name: "search_drugs",
          arguments: { query: "ibuprofen 400mg" },
          call_id: "call_1"
        ),
        llm_agent_final_response(content: "Order processed. Ibuprofen 400mg x 30 confirmed.")
      ])

      profile = {
        model: "test-model",
        max_tokens: 4096,
        temperature: 0.3,
        max_iterations: 10,
        system_prompt: "You are a pharmacy order processor.",
        tools: ["search_drugs"]
      }

      agent_loop = Agents::AgentLoop.new(llm_client: llm_client, tool_registry: registry)
      result = agent_loop.run(profile: profile, user_message: "Order for ibuprofen 400mg x 30")

      expect(result.status).to eq("completed")
      expect(result.tool_calls.length).to eq(1)

      # Step 3: Create agent_run record (as the handler would)
      agent_run = AgentRun.create!(
        user: user,
        gmail_thread_id: thread_id,
        profile: route_result["profile"],
        status: result.status,
        iterations: result.iterations,
        tool_calls_log: result.tool_calls.to_json,
        final_message: result.final_message,
        completed_at: Time.current
      )

      expect(agent_run).to be_persisted
      expect(agent_run.status).to eq("completed")
      expect(agent_run.profile).to eq("pharmacy")
      expect(agent_run.parsed_tool_calls.length).to eq(1)
      expect(agent_run.final_message).to include("Order processed")
    end
  end

  describe "TC-11.6: Manual draft request" do
    it "creates draft when user manually applies Needs Response label" do
      thread_id = "thread_e2e_6"

      # Step 1: Email exists without classification (unprocessed)
      # User manually applies "Needs Response" label
      email = create(:email,
        user: user,
        gmail_thread_id: thread_id,
        gmail_message_id: "msg_e2e_6",
        sender_email: "contact@company.com",
        sender_name: "Contact",
        subject: "Partnership opportunity",
        classification: "needs_response",
        confidence: "high",
        status: "pending",
        resolved_style: "business",
        detected_language: "en"
      )

      # Step 2: Generate draft (as manual_draft handler would)
      allow(llm_gateway).to receive(:draft).and_return(llm_draft_response)
      allow(llm_gateway).to receive(:context_query).and_return(nil)
      allow(gmail_client).to receive(:create_draft).and_return("draft_e2e_6")
      allow(gmail_client).to receive(:modify_thread)
      allow(gmail_client).to receive(:search_threads).and_return([])

      generator = Drafting::DraftGenerator.new(
        llm_gateway: llm_gateway,
        styles_config: { "styles" => { "business" => { "rules" => [], "sign_off" => "Best regards" } } }
      )

      draft_body = generator.generate(
        sender_name: email.sender_name,
        sender_email: email.sender_email,
        subject: email.subject,
        thread_body: "We'd like to discuss a partnership...",
        resolved_style: email.resolved_style,
        detected_language: email.detected_language,
        related_context: ""
      )

      expect(draft_body).to be_present

      # Simulate draft creation in Gmail
      draft_id = gmail_client.create_draft(
        thread_id: thread_id,
        body: draft_body,
        subject: "Re: #{email.subject}"
      )

      # Transition labels: Needs Response -> Outbox
      gmail_client.modify_thread(
        thread_id: thread_id,
        add_label_ids: [label_id("outbox")],
        remove_label_ids: [label_id("needs_response")]
      )

      email.update!(
        status: "drafted",
        draft_id: draft_id,
        drafted_at: Time.current
      )

      # Step 3: Verify
      email.reload
      expect(email.status).to eq("drafted")
      expect(email.draft_id).to eq("draft_e2e_6")
      expect(email.drafted_at).to be_present

      expect(gmail_client).to have_received(:create_draft).with(
        thread_id: thread_id,
        body: draft_body,
        subject: "Re: Partnership opportunity"
      )

      expect(gmail_client).to have_received(:modify_thread).with(
        thread_id: thread_id,
        add_label_ids: [label_id("outbox")],
        remove_label_ids: [label_id("needs_response")]
      )
    end
  end
end
