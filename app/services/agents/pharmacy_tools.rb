module Agents
  class PharmacyTools
    def self.register_all(registry)
      register_search_drugs(registry)
      register_manage_reservation(registry)
      register_web_search(registry)
      register_send_reply(registry)
      register_create_draft(registry)
      register_escalate(registry)
    end

    def self.register_search_drugs(registry)
      registry.register(
        name: "search_drugs",
        description: "Search drug availability database",
        parameters: {
          type: "object",
          properties: {
            query: { type: "string", description: "Drug name or search query" },
            limit: { type: "integer", description: "Maximum results to return", default: 5 }
          },
          required: [ "query" ]
        },
        handler: ->(query:, limit: 5) {
          {
            drugs: [
              { name: "Ibuprofen 400mg", available: true, pharmacy_count: 3 },
              { name: "Ibuprofen 200mg", available: true, pharmacy_count: 5 }
            ].first(limit),
            query: query,
            total_results: 2
          }
        }
      )
    end

    def self.register_manage_reservation(registry)
      registry.register(
        name: "manage_reservation",
        description: "Create, check, or cancel drug reservations",
        parameters: {
          type: "object",
          properties: {
            action: { type: "string", description: "Action: create, check, or cancel" },
            drug_name: { type: "string", description: "Name of the drug" },
            pharmacy_id: { type: "string", description: "Pharmacy identifier" }
          },
          required: [ "action", "drug_name" ]
        },
        handler: ->(action:, drug_name:, pharmacy_id: nil) {
          case action
          when "create"
            { status: "reserved", drug_name: drug_name, reservation_id: "RES-#{SecureRandom.hex(4)}" }
          when "check"
            { status: "active", drug_name: drug_name, expires_at: 1.day.from_now.iso8601 }
          when "cancel"
            { status: "cancelled", drug_name: drug_name }
          else
            { error: "Unknown action: #{action}" }
          end
        }
      )
    end

    def self.register_web_search(registry)
      registry.register(
        name: "web_search",
        description: "General web search for drug information",
        parameters: {
          type: "object",
          properties: {
            query: { type: "string", description: "Search query" }
          },
          required: [ "query" ]
        },
        handler: ->(query:) {
          {
            results: [
              { title: "Drug Information - #{query}", url: "https://example.com/drugs", snippet: "Information about #{query}..." }
            ]
          }
        }
      )
    end

    def self.register_send_reply(registry)
      registry.register(
        name: "send_reply",
        description: "Send an email reply",
        parameters: {
          type: "object",
          properties: {
            to: { type: "string", description: "Recipient email" },
            subject: { type: "string", description: "Email subject" },
            body: { type: "string", description: "Email body" }
          },
          required: [ "to", "subject", "body" ]
        },
        handler: ->(to:, subject:, body:) {
          { status: "sent", to: to, subject: subject }
        }
      )
    end

    def self.register_create_draft(registry)
      registry.register(
        name: "create_draft",
        description: "Create a draft for human review",
        parameters: {
          type: "object",
          properties: {
            to: { type: "string", description: "Recipient email" },
            subject: { type: "string", description: "Email subject" },
            body: { type: "string", description: "Email body" }
          },
          required: [ "to", "subject", "body" ]
        },
        handler: ->(to:, subject:, body:) {
          { status: "created", draft_id: "draft_#{SecureRandom.hex(4)}", to: to, subject: subject }
        }
      )
    end

    def self.register_escalate(registry)
      registry.register(
        name: "escalate",
        description: "Flag conversation for human review",
        parameters: {
          type: "object",
          properties: {
            reason: { type: "string", description: "Reason for escalation" }
          },
          required: [ "reason" ]
        },
        handler: ->(reason:) {
          { status: "escalated", reason: reason }
        }
      )
    end
  end
end
