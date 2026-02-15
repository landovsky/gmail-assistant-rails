require "rails_helper"

RSpec.describe Classification::RuleEngine do
  subject(:engine) { described_class.new(contacts_config: contacts_config) }

  let(:contacts_config) do
    {
      "blacklist" => ["*@marketing.spam.com", "noreply@*"],
      "style_overrides" => {},
      "domain_overrides" => {}
    }
  end

  describe "#evaluate" do
    context "blacklist matching" do
      it "flags emails matching blacklist glob patterns" do
        result = engine.evaluate(sender_email: "promo@marketing.spam.com")
        expect(result[:is_automated]).to be true
      end

      it "does not flag emails not in blacklist" do
        result = engine.evaluate(sender_email: "person@example.com")
        expect(result[:is_automated]).to be false
      end
    end

    context "automated sender detection" do
      %w[noreply@example.com no-reply@example.com mailer-daemon@example.com
         postmaster@example.com notifications@example.com bounce@example.com].each do |email|
        it "flags #{email} as automated" do
          result = engine.evaluate(sender_email: email)
          expect(result[:is_automated]).to be true
        end
      end

      it "does not flag normal senders" do
        result = engine.evaluate(sender_email: "john@example.com")
        expect(result[:is_automated]).to be false
      end
    end

    context "header-based detection" do
      it "flags Auto-Submitted header (not 'no')" do
        result = engine.evaluate(sender_email: "a@b.com", headers: { "Auto-Submitted" => "auto-generated" })
        expect(result[:is_automated]).to be true
      end

      it "does not flag Auto-Submitted: no" do
        result = engine.evaluate(sender_email: "a@b.com", headers: { "Auto-Submitted" => "no" })
        expect(result[:is_automated]).to be false
      end

      it "flags Precedence: bulk" do
        result = engine.evaluate(sender_email: "a@b.com", headers: { "Precedence" => "bulk" })
        expect(result[:is_automated]).to be true
      end

      it "flags Precedence: list" do
        result = engine.evaluate(sender_email: "a@b.com", headers: { "Precedence" => "list" })
        expect(result[:is_automated]).to be true
      end

      it "does not flag Precedence with non-matching value" do
        result = engine.evaluate(sender_email: "a@b.com", headers: { "Precedence" => "normal" })
        expect(result[:is_automated]).to be false
      end

      %w[List-Id List-Unsubscribe X-Auto-Response-Suppress Feedback-ID X-Autoreply X-Autorespond].each do |header|
        it "flags presence of #{header}" do
          result = engine.evaluate(sender_email: "a@b.com", headers: { header => "some-value" })
          expect(result[:is_automated]).to be true
        end
      end

      it "does not flag empty headers" do
        result = engine.evaluate(sender_email: "a@b.com", headers: {})
        expect(result[:is_automated]).to be false
      end

      it "handles nil headers gracefully" do
        result = engine.evaluate(sender_email: "a@b.com", headers: nil)
        expect(result[:is_automated]).to be false
      end
    end

    context "with empty contacts config" do
      let(:contacts_config) { {} }

      it "still detects automated senders" do
        result = engine.evaluate(sender_email: "noreply@example.com")
        expect(result[:is_automated]).to be true
      end
    end
  end
end
