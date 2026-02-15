require "rails_helper"

RSpec.describe Gmail::Client do
  describe ".parse_headers" do
    it "extracts target headers from a message" do
      headers = [
        double(name: "From", value: "sender@example.com"),
        double(name: "To", value: "recipient@example.com"),
        double(name: "Subject", value: "Test Subject"),
        double(name: "Date", value: "Mon, 1 Jan 2024 00:00:00 +0000"),
        double(name: "Message-ID", value: "<abc123@mail.example.com>"),
        double(name: "X-Mailer", value: "SomeTool") # not a target header
      ]
      payload = double(headers: headers)
      message = double(payload: payload)

      result = described_class.parse_headers(message)

      expect(result["From"]).to eq("sender@example.com")
      expect(result["To"]).to eq("recipient@example.com")
      expect(result["Subject"]).to eq("Test Subject")
      expect(result["Date"]).to eq("Mon, 1 Jan 2024 00:00:00 +0000")
      expect(result["Message-ID"]).to eq("<abc123@mail.example.com>")
      expect(result).not_to have_key("X-Mailer")
    end

    it "returns empty hash when message has no payload" do
      message = double(payload: nil)
      expect(described_class.parse_headers(message)).to eq({})
    end

    it "extracts automation headers" do
      headers = [
        double(name: "Auto-Submitted", value: "auto-generated"),
        double(name: "Precedence", value: "bulk"),
        double(name: "List-Id", value: "list.example.com"),
        double(name: "Feedback-ID", value: "feedback123")
      ]
      payload = double(headers: headers)
      message = double(payload: payload)

      result = described_class.parse_headers(message)

      expect(result["Auto-Submitted"]).to eq("auto-generated")
      expect(result["Precedence"]).to eq("bulk")
      expect(result["List-Id"]).to eq("list.example.com")
      expect(result["Feedback-ID"]).to eq("feedback123")
    end
  end

  describe ".parse_sender" do
    it "parses name and email from full format" do
      result = described_class.parse_sender('"John Doe" <john@example.com>')
      expect(result[:name]).to eq("John Doe")
      expect(result[:email]).to eq("john@example.com")
    end

    it "parses name without quotes" do
      result = described_class.parse_sender("John Doe <john@example.com>")
      expect(result[:name]).to eq("John Doe")
      expect(result[:email]).to eq("john@example.com")
    end

    it "parses email-only format" do
      result = described_class.parse_sender("john@example.com")
      expect(result[:name]).to eq("")
      expect(result[:email]).to eq("john@example.com")
    end

    it "returns empty for nil" do
      result = described_class.parse_sender(nil)
      expect(result[:name]).to eq("")
      expect(result[:email]).to eq("")
    end

    it "returns empty for empty string" do
      result = described_class.parse_sender("")
      expect(result[:name]).to eq("")
      expect(result[:email]).to eq("")
    end

    it "downcases email" do
      result = described_class.parse_sender("User <User@Example.COM>")
      expect(result[:email]).to eq("user@example.com")
    end
  end

  describe ".extract_body" do
    it "extracts text/plain body from simple message" do
      encoded = Base64.urlsafe_encode64("Hello World")
      body = double(data: encoded)
      payload = double(mime_type: "text/plain", body: body, parts: nil)

      result = described_class.extract_body(payload)
      expect(result).to eq("Hello World")
    end

    it "extracts text/plain from multipart message" do
      encoded = Base64.urlsafe_encode64("Plain text part")
      text_body = double(data: encoded)
      text_part = double(mime_type: "text/plain", body: text_body, parts: nil)
      html_part = double(mime_type: "text/html", body: double(data: nil), parts: nil)

      payload = double(mime_type: "multipart/alternative", body: double(data: nil), parts: [text_part, html_part])

      result = described_class.extract_body(payload)
      expect(result).to eq("Plain text part")
    end

    it "returns empty string when no text/plain found" do
      html_body = double(data: Base64.urlsafe_encode64("<p>HTML</p>"))
      html_part = double(mime_type: "text/html", body: html_body, parts: nil)
      payload = double(mime_type: "multipart/alternative", body: double(data: nil), parts: [html_part])

      result = described_class.extract_body(payload)
      expect(result).to eq("")
    end

    it "returns empty string for nil payload" do
      expect(described_class.extract_body(nil)).to eq("")
    end

    it "recurses into nested parts" do
      encoded = Base64.urlsafe_encode64("Nested text")
      text_part = double(mime_type: "text/plain", body: double(data: encoded), parts: nil)
      inner_multi = double(mime_type: "multipart/alternative", body: double(data: nil), parts: [text_part])
      payload = double(mime_type: "multipart/mixed", body: double(data: nil), parts: [inner_multi])

      result = described_class.extract_body(payload)
      expect(result).to eq("Nested text")
    end
  end

  describe ".decode_body" do
    it "decodes base64url data" do
      encoded = Base64.urlsafe_encode64("Hello")
      expect(described_class.decode_body(encoded)).to eq("Hello")
    end

    it "returns empty string for nil" do
      expect(described_class.decode_body(nil)).to eq("")
    end

    it "handles invalid base64 gracefully" do
      expect(described_class.decode_body("!!!invalid!!!")).to eq("")
    end
  end

  describe "retry logic" do
    let(:client) do
      # Build a client without real auth
      instance = described_class.allocate
      instance.instance_variable_set(:@service, double("gmail_service"))
      instance.instance_variable_set(:@user_email, "test@example.com")
      instance
    end

    it "retries on server errors up to MAX_RETRIES times" do
      call_count = 0
      allow(client.service).to receive(:get_user_profile) do
        call_count += 1
        raise Google::Apis::ServerError, "500 Server Error" if call_count < 3
        double(history_id: "123", email_address: "test@example.com")
      end
      allow(client).to receive(:sleep) # Don't actually sleep in tests

      result = client.get_profile
      expect(result.history_id).to eq("123")
      expect(call_count).to eq(3)
    end

    it "does not retry on client errors" do
      call_count = 0
      allow(client.service).to receive(:get_user_profile) do
        call_count += 1
        raise Google::Apis::ClientError, "404 Not Found"
      end

      expect { client.get_profile }.to raise_error(Google::Apis::ClientError)
      expect(call_count).to eq(1)
    end
  end
end
