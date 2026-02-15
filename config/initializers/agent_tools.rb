# frozen_string_literal: true

# Register default agent tools
#
# These tools are available to agent profiles. Each tool is currently stubbed
# and returns mock data - real implementations pending.

Rails.application.config.after_initialize do
  registry = Agent::ToolRegistry

  # search_mailbox - Search through user's mailbox
  registry.register(
    "search_mailbox",
    description: "Search through the user's mailbox for emails matching a query. Returns subject, sender, and snippet for matching emails.",
    parameters: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Search query string (supports Gmail search operators)"
        },
        limit: {
          type: "integer",
          description: "Maximum number of results to return",
          default: 10
        }
      },
      required: ["query"]
    }
  ) do |query:, limit: 10|
    # TODO: Implement actual Gmail search via Gmail::Client
    Rails.logger.info "Tool called: search_mailbox(query=#{query}, limit=#{limit})"

    {
      results: [
        {
          subject: "Re: Previous conversation",
          sender: "user@example.com",
          snippet: "This is a mock result for query: #{query}"
        }
      ],
      count: 1
    }
  end

  # apply_label - Apply a Gmail label to an email
  registry.register(
    "apply_label",
    description: "Apply a Gmail label to the current email thread. Use this to categorize or mark emails.",
    parameters: {
      type: "object",
      properties: {
        label: {
          type: "string",
          description: "Label name to apply (e.g., 'Important', 'Follow-up', 'Processed')"
        }
      },
      required: ["label"]
    }
  ) do |label:|
    # TODO: Implement actual label application via Gmail::Client
    Rails.logger.info "Tool called: apply_label(label=#{label})"

    {
      status: "success",
      message: "Label '#{label}' would be applied (stubbed)"
    }
  end

  # create_draft - Create a draft email reply
  registry.register(
    "create_draft",
    description: "Create a draft email reply for human review. The draft will be saved but not sent automatically.",
    parameters: {
      type: "object",
      properties: {
        to: {
          type: "string",
          description: "Recipient email address"
        },
        subject: {
          type: "string",
          description: "Email subject line"
        },
        body: {
          type: "string",
          description: "Email body content (plain text or HTML)"
        }
      },
      required: ["to", "subject", "body"]
    }
  ) do |to:, subject:, body:|
    # TODO: Implement actual draft creation via Gmail::Client
    Rails.logger.info "Tool called: create_draft(to=#{to}, subject=#{subject})"

    {
      status: "created",
      message: "Draft created (stubbed)",
      draft: {
        to: to,
        subject: subject,
        body_preview: body[0..100]
      }
    }
  end
end
