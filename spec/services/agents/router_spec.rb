require "rails_helper"

RSpec.describe Agents::Router do
  describe "#route" do
    it "returns pipeline by default when no rules match" do
      router = described_class.new([])
      result = router.route(sender_email: "test@example.com", subject: "Hello")
      expect(result["route"]).to eq("pipeline")
    end

    it "matches all: true catch-all" do
      rules = [ { "match" => { "all" => true }, "route" => "pipeline" } ]
      router = described_class.new(rules)
      result = router.route(sender_email: "test@example.com", subject: "Hello")
      expect(result["route"]).to eq("pipeline")
    end

    it "matches sender_email" do
      rules = [
        { "match" => { "sender_email" => "vip@example.com" }, "route" => "agent", "profile" => "vip" }
      ]
      router = described_class.new(rules)

      result = router.route(sender_email: "vip@example.com", subject: "Hello")
      expect(result["route"]).to eq("agent")
      expect(result["profile"]).to eq("vip")

      result = router.route(sender_email: "other@example.com", subject: "Hello")
      expect(result["route"]).to eq("pipeline")
    end

    it "matches sender_domain" do
      rules = [
        { "match" => { "sender_domain" => "pharmacy.cz" }, "route" => "agent", "profile" => "pharmacy" }
      ]
      router = described_class.new(rules)

      result = router.route(sender_email: "info@pharmacy.cz", subject: "Order")
      expect(result["route"]).to eq("agent")
    end

    it "matches subject_contains case-insensitively" do
      rules = [
        { "match" => { "subject_contains" => "URGENT" }, "route" => "agent", "profile" => "urgent" }
      ]
      router = described_class.new(rules)

      result = router.route(sender_email: "a@b.com", subject: "This is urgent please help")
      expect(result["route"]).to eq("agent")
    end

    it "matches header_match with regex" do
      rules = [
        { "match" => { "header_match" => { "X-Priority" => "^1$" } }, "route" => "agent", "profile" => "priority" }
      ]
      router = described_class.new(rules)

      result = router.route(sender_email: "a@b.com", subject: "Hi", headers: { "X-Priority" => "1" })
      expect(result["route"]).to eq("agent")

      result = router.route(sender_email: "a@b.com", subject: "Hi", headers: { "X-Priority" => "3" })
      expect(result["route"]).to eq("pipeline")
    end

    it "matches forwarded_from" do
      rules = [
        { "match" => { "forwarded_from" => "info@dostupnost-leku.cz" }, "route" => "agent", "profile" => "pharmacy" }
      ]
      router = described_class.new(rules)

      result = router.route(
        sender_email: "noreply@crisp.chat",
        subject: "New message",
        headers: { "Reply-To" => "info@dostupnost-leku.cz" }
      )
      expect(result["route"]).to eq("agent")
    end

    it "requires all conditions to match (AND logic)" do
      rules = [
        {
          "match" => { "sender_domain" => "example.com", "subject_contains" => "invoice" },
          "route" => "agent",
          "profile" => "billing"
        }
      ]
      router = described_class.new(rules)

      # Both match
      result = router.route(sender_email: "billing@example.com", subject: "Your invoice")
      expect(result["route"]).to eq("agent")

      # Only domain matches
      result = router.route(sender_email: "billing@example.com", subject: "Hello")
      expect(result["route"]).to eq("pipeline")
    end

    it "returns first matching rule" do
      rules = [
        { "match" => { "sender_email" => "vip@example.com" }, "route" => "agent", "profile" => "vip" },
        { "match" => { "all" => true }, "route" => "pipeline" }
      ]
      router = described_class.new(rules)

      result = router.route(sender_email: "vip@example.com", subject: "Hi")
      expect(result["route"]).to eq("agent")
      expect(result["profile"]).to eq("vip")
    end
  end
end
