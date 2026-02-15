require "rails_helper"

RSpec.describe Lifecycle::ReworkHandler do
  subject(:handler) do
    described_class.new(
      draft_generator: draft_generator,
      context_gatherer: context_gatherer,
      gmail_client: gmail_client
    )
  end

  let(:draft_generator) { instance_double(Drafting::DraftGenerator) }
  let(:context_gatherer) { instance_double(Drafting::ContextGatherer) }
  let(:gmail_client) { double("GmailClient") }
  let(:user) { create(:user) }
  let(:email) do
    create(:email,
      user: user,
      rework_count: 0,
      draft_id: "draft_123",
      status: "drafted",
      resolved_style: "business",
      detected_language: "en"
    )
  end

  before do
    create(:user_label, user: user, label_key: "rework", gmail_label_id: "Label_rework", gmail_label_name: "AI/Rework")
    create(:user_label, user: user, label_key: "outbox", gmail_label_id: "Label_outbox", gmail_label_name: "AI/Outbox")
    create(:user_label, user: user, label_key: "action_required", gmail_label_id: "Label_ar", gmail_label_name: "AI/Action Required")

    allow(gmail_client).to receive(:get_draft_body).and_return("Fix the tone\n\n\u2702\uFE0F\n\nOld draft text")
    allow(gmail_client).to receive(:get_thread_data).and_return({ body: "Original thread body" })
    allow(gmail_client).to receive(:trash_draft)
    allow(gmail_client).to receive(:create_draft).and_return(double(id: "new_draft_456"))
    allow(gmail_client).to receive(:modify_thread)
    allow(context_gatherer).to receive(:gather).and_return("")
    allow(draft_generator).to receive(:generate).and_return("\n\n\u2702\uFE0F\n\nNew draft text")
  end

  describe "#handle" do
    context "first rework (count 0 -> 1)" do
      it "generates new draft with extracted instructions" do
        expect(draft_generator).to receive(:generate).with(
          hash_including(user_instructions: "Fix the tone")
        ).and_return("\n\n\u2702\uFE0F\n\nNew draft text")

        handler.handle(email: email, user: user)
      end

      it "trashes old draft and creates new one" do
        expect(gmail_client).to receive(:trash_draft).with(draft_id: "draft_123")
        expect(gmail_client).to receive(:create_draft)

        handler.handle(email: email, user: user)
      end

      it "moves labels from rework to outbox" do
        expect(gmail_client).to receive(:modify_thread).with(
          thread_id: email.gmail_thread_id,
          add_label_ids: ["Label_outbox"],
          remove_label_ids: ["Label_rework"]
        )

        handler.handle(email: email, user: user)
      end

      it "increments rework count and stores new draft_id" do
        handler.handle(email: email, user: user)

        email.reload
        expect(email.rework_count).to eq(1)
        expect(email.draft_id).to eq("new_draft_456")
        expect(email.last_rework_instruction).to eq("Fix the tone")
        expect(email.status).to eq("drafted")
      end

      it "logs draft_reworked event" do
        handler.handle(email: email, user: user)

        event = EmailEvent.last
        expect(event.event_type).to eq("draft_reworked")
        expect(event.detail).to include("Rework #1")
      end
    end

    context "third rework (count 2 -> 3) - last automatic rework" do
      before { email.update!(rework_count: 2) }

      it "prepends warning to draft" do
        expect(draft_generator).to receive(:generate).and_return("\n\n\u2702\uFE0F\n\nFinal draft")

        handler.handle(email: email, user: user)

        expect(gmail_client).to have_received(:create_draft).with(
          hash_including(body: start_with("\u26A0\uFE0F This is the last automatic rework"))
        )
      end

      it "moves labels from rework to action_required" do
        expect(gmail_client).to receive(:modify_thread).with(
          thread_id: email.gmail_thread_id,
          add_label_ids: ["Label_ar"],
          remove_label_ids: ["Label_rework"]
        )

        handler.handle(email: email, user: user)
      end

      it "sets status to skipped" do
        handler.handle(email: email, user: user)

        email.reload
        expect(email.rework_count).to eq(3)
        expect(email.status).to eq("skipped")
      end
    end

    context "fourth rework attempt (count >= 3) - limit reached" do
      before { email.update!(rework_count: 3) }

      it "does not generate a new draft" do
        expect(draft_generator).not_to receive(:generate)

        handler.handle(email: email, user: user)
      end

      it "moves labels from rework to action_required" do
        expect(gmail_client).to receive(:modify_thread).with(
          thread_id: email.gmail_thread_id,
          add_label_ids: ["Label_ar"],
          remove_label_ids: ["Label_rework"]
        )

        handler.handle(email: email, user: user)
      end

      it "sets status to skipped" do
        handler.handle(email: email, user: user)

        email.reload
        expect(email.status).to eq("skipped")
      end

      it "logs rework_limit_reached event" do
        handler.handle(email: email, user: user)

        event = EmailEvent.last
        expect(event.event_type).to eq("rework_limit_reached")
      end
    end

    context "no instructions above scissors marker" do
      before do
        allow(gmail_client).to receive(:get_draft_body).and_return("\n\n\u2702\uFE0F\n\nJust the draft")
      end

      it "uses default instruction text" do
        expect(draft_generator).to receive(:generate).with(
          hash_including(user_instructions: "(no specific instruction provided)")
        ).and_return("\n\n\u2702\uFE0F\n\nNew draft")

        handler.handle(email: email, user: user)
      end
    end
  end
end
