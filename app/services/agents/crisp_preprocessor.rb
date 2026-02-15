module Agents
  class CrispPreprocessor
    # Regex patterns for Crisp helpdesk formatting
    CRISP_NAME_PATTERN = /(?:From|Od):\s*(.+?)(?:\n|\r|<)/i
    CRISP_EMAIL_PATTERN = /[\w.+-]+@[\w-]+\.[\w.]+/
    CRISP_MESSAGE_PATTERN = /(?:Message|Zpráva):\s*\n(.*)/mi

    def process(email_data)
      body = email_data[:body] || ""

      patient_name = extract_name(body)
      patient_email = extract_email(body) || email_data[:sender_email]
      original_message = extract_message(body) || body

      formatted = "New support inquiry from #{patient_name} (#{patient_email}):\n" \
                  "Subject: #{email_data[:subject]}\n\n" \
                  "#{original_message}"

      {
        sender_email: patient_email,
        subject: email_data[:subject],
        body: formatted,
        patient_name: patient_name,
        patient_email: patient_email,
        original_message: original_message
      }
    end

    private

    def extract_name(body)
      match = body.match(CRISP_NAME_PATTERN)
      match ? match[1].strip : "Unknown"
    end

    def extract_email(body)
      match = body.match(CRISP_EMAIL_PATTERN)
      match ? match[0] : nil
    end

    def extract_message(body)
      match = body.match(CRISP_MESSAGE_PATTERN)
      match ? match[1].strip : nil
    end
  end
end
