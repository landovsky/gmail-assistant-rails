module GmailApiHelpers
  # Build a Gmail API message object matching the real format
  # https://developers.google.com/gmail/api/reference/rest/v1/users.messages
  def gmail_message(
    id: "msg_#{SecureRandom.hex(8)}",
    thread_id: "thread_#{SecureRandom.hex(8)}",
    from: "sender@example.com",
    from_name: "Sender Name",
    to: "user@example.com",
    subject: "Test Subject",
    body: "This is the email body.",
    date: "Thu, 13 Feb 2025 10:00:00 +0000",
    snippet: nil,
    label_ids: [ "INBOX" ],
    headers: {},
    internal_date: nil
  )
    all_headers = [
      { "name" => "From", "value" => from_name.present? ? "\"#{from_name}\" <#{from}>" : from },
      { "name" => "To", "value" => to },
      { "name" => "Subject", "value" => subject },
      { "name" => "Date", "value" => date },
      { "name" => "Message-ID", "value" => "<#{SecureRandom.hex(16)}@mail.gmail.com>" }
    ]

    headers.each do |name, value|
      all_headers << { "name" => name, "value" => value }
    end

    encoded_body = Base64.urlsafe_encode64(body)

    {
      "id" => id,
      "threadId" => thread_id,
      "labelIds" => label_ids,
      "snippet" => snippet || body.truncate(100),
      "internalDate" => internal_date || (Time.parse(date).to_i * 1000).to_s,
      "payload" => {
        "mimeType" => "text/plain",
        "headers" => all_headers,
        "body" => {
          "size" => body.length,
          "data" => encoded_body
        }
      },
      "sizeEstimate" => body.length + 500
    }
  end

  # Build a multipart message (common for real emails)
  def gmail_multipart_message(
    id: "msg_#{SecureRandom.hex(8)}",
    thread_id: "thread_#{SecureRandom.hex(8)}",
    from: "sender@example.com",
    subject: "Test Subject",
    text_body: "Plain text body",
    html_body: "<p>HTML body</p>",
    label_ids: [ "INBOX" ],
    headers: {}
  )
    msg = gmail_message(
      id: id, thread_id: thread_id, from: from,
      subject: subject, body: "", label_ids: label_ids, headers: headers
    )

    msg["payload"] = {
      "mimeType" => "multipart/alternative",
      "headers" => msg["payload"]["headers"],
      "parts" => [
        {
          "mimeType" => "text/plain",
          "body" => {
            "size" => text_body.length,
            "data" => Base64.urlsafe_encode64(text_body)
          }
        },
        {
          "mimeType" => "text/html",
          "body" => {
            "size" => html_body.length,
            "data" => Base64.urlsafe_encode64(html_body)
          }
        }
      ]
    }

    msg
  end

  # Build a Gmail API thread object
  def gmail_thread(id: "thread_#{SecureRandom.hex(8)}", messages: nil)
    messages ||= [ gmail_message(thread_id: id) ]

    {
      "id" => id,
      "historyId" => "#{rand(100_000..999_999)}",
      "messages" => messages
    }
  end

  # Build a Gmail API history record
  def gmail_history_record(
    id: rand(10_000..99_999),
    messages_added: [],
    labels_added: [],
    labels_removed: [],
    messages_deleted: []
  )
    record = { "id" => id.to_s }

    if messages_added.any?
      record["messagesAdded"] = messages_added.map do |msg|
        { "message" => msg.is_a?(Hash) ? msg : gmail_message(id: msg) }
      end
    end

    if labels_added.any?
      record["labelsAdded"] = labels_added.map do |entry|
        {
          "message" => entry[:message].is_a?(Hash) ? entry[:message] : gmail_message(id: entry[:message]),
          "labelIds" => entry[:label_ids]
        }
      end
    end

    if labels_removed.any?
      record["labelsRemoved"] = labels_removed.map do |entry|
        {
          "message" => entry[:message].is_a?(Hash) ? entry[:message] : gmail_message(id: entry[:message]),
          "labelIds" => entry[:label_ids]
        }
      end
    end

    if messages_deleted.any?
      record["messagesDeleted"] = messages_deleted.map do |msg|
        { "message" => msg.is_a?(Hash) ? msg : { "id" => msg } }
      end
    end

    record
  end

  # Build a Gmail history.list API response
  def gmail_history_response(records: [], next_page_token: nil, history_id: "999999")
    response = {
      "history" => records,
      "historyId" => history_id
    }
    response["nextPageToken"] = next_page_token if next_page_token
    response
  end

  # Build a Gmail API draft object
  def gmail_draft(
    id: "draft_#{SecureRandom.hex(8)}",
    message: nil,
    thread_id: nil
  )
    msg = message || gmail_message(thread_id: thread_id || "thread_#{SecureRandom.hex(8)}")

    {
      "id" => id,
      "message" => msg
    }
  end

  # Build a Gmail API label object
  def gmail_label(
    id: "Label_#{SecureRandom.hex(6)}",
    name: "Test Label",
    type: "user",
    label_list_visibility: "labelShow",
    message_list_visibility: "show"
  )
    {
      "id" => id,
      "name" => name,
      "type" => type,
      "labelListVisibility" => label_list_visibility,
      "messageListVisibility" => message_list_visibility
    }
  end

  # Build a Gmail API user profile response
  def gmail_profile(email: "user@example.com", history_id: "123456")
    {
      "emailAddress" => email,
      "messagesTotal" => 5000,
      "threadsTotal" => 3000,
      "historyId" => history_id
    }
  end

  # Build a Gmail watch response
  def gmail_watch_response(history_id: "123456", expiration: nil)
    {
      "historyId" => history_id,
      "expiration" => expiration || ((Time.current + 7.days).to_i * 1000).to_s
    }
  end

  # Build a Gmail messages.list response
  def gmail_messages_list(message_ids: [], next_page_token: nil)
    response = {
      "resultSizeEstimate" => message_ids.length,
      "messages" => message_ids.map { |id| { "id" => id, "threadId" => "thread_for_#{id}" } }
    }
    response["nextPageToken"] = next_page_token if next_page_token
    response
  end

  # Build a message with automated sender headers (for rule-based detection)
  def gmail_automated_message(header_type: :list_unsubscribe, **overrides)
    extra_headers = case header_type
    when :list_unsubscribe
      { "List-Unsubscribe" => "<mailto:unsub@example.com>" }
    when :auto_submitted
      { "Auto-Submitted" => "auto-generated" }
    when :precedence_bulk
      { "Precedence" => "bulk" }
    when :list_id
      { "List-Id" => "<list.example.com>" }
    when :feedback_id
      { "Feedback-ID" => "123:456:example" }
    when :x_autoreply
      { "X-Autoreply" => "yes" }
    else
      {}
    end

    gmail_message(headers: extra_headers, **overrides)
  end

  # Build a Pub/Sub webhook payload
  def gmail_pubsub_payload(email: "user@example.com", history_id: 12345)
    data = Base64.encode64({ emailAddress: email, historyId: history_id }.to_json)
    {
      message: {
        data: data,
        messageId: "pubsub_#{SecureRandom.hex(8)}",
        publishTime: Time.current.iso8601
      },
      subscription: "projects/test/subscriptions/gmail-push"
    }
  end
end

RSpec.configure do |config|
  config.include GmailApiHelpers
end
