module Jobs
  class ClassifyHandler < BaseHandler
    def perform
      thread_id = @payload["thread_id"]
      message_id = @payload["message_id"]
      force = @payload["force"] == true

      # Skip if already classified (unless force reclassification)
      existing = Email.find_by(user: @user, gmail_thread_id: thread_id)
      if existing && !force
        Rails.logger.info("ClassifyHandler: thread #{thread_id} already classified, skipping")
        return
      end

      # Fetch message from Gmail
      message = @gmail_client.get_message(message_id)
      headers = Gmail::Client.parse_headers(message)
      sender = Gmail::Client.parse_sender(headers["From"])
      body = Gmail::Client.extract_body(message.payload)
      subject = headers["Subject"] || ""
      snippet = message.snippet

      # Run classification engine
      llm_gateway = Llm::Gateway.new(user: @user)
      rule_engine = Classification::RuleEngine.new
      llm_classifier = Classification::LlmClassifier.new(llm_gateway: llm_gateway)
      engine = Classification::ClassificationEngine.new(
        rule_engine: rule_engine,
        llm_classifier: llm_classifier
      )

      result = engine.classify(
        sender_name: sender[:name],
        sender_email: sender[:email],
        subject: subject,
        body: body,
        message_count: 1,
        snippet: snippet,
        headers: headers
      )

      category = result["category"]
      confidence = result["confidence"]
      resolved_style = result["resolved_style"]
      detected_language = result["detected_language"]

      # Apply classification label in Gmail
      label_key = category
      label = @user.user_labels.find_by(label_key: label_key)

      if label
        if force && existing
          # Remove old classification label on reclassification
          old_label = @user.user_labels.find_by(label_key: existing.classification)
          remove_ids = old_label ? [old_label.gmail_label_id] : []
          @gmail_client.modify_message(message_id, add_label_ids: [label.gmail_label_id], remove_label_ids: remove_ids)
        else
          @gmail_client.modify_message(message_id, add_label_ids: [label.gmail_label_id])
        end
      end

      # Determine status
      status = category == "needs_response" ? "pending" : "skipped"

      # Store/update email record
      if existing
        existing.update!(
          classification: category,
          confidence: confidence,
          resolved_style: resolved_style,
          detected_language: detected_language,
          status: status
        )
      else
        existing = Email.create!(
          user: @user,
          gmail_thread_id: thread_id,
          gmail_message_id: message_id,
          sender_email: sender[:email],
          sender_name: sender[:name],
          subject: subject,
          classification: category,
          confidence: confidence,
          resolved_style: resolved_style,
          detected_language: detected_language,
          status: status,
          message_count: 1
        )
      end

      # Log event
      EmailEvent.create!(
        user: @user,
        gmail_thread_id: thread_id,
        event_type: "classified",
        detail: "#{category} (#{confidence}): #{result['reasoning'].to_s.truncate(200)}"
      )

      # Enqueue draft job if needs_response
      if category == "needs_response"
        Job.create!(
          user: @user,
          job_type: "draft",
          payload: { thread_id: thread_id, message_id: message_id }.to_json,
          status: "pending"
        )
      end

      # On reclassification away from needs_response, trash dangling drafts
      if force && category != "needs_response" && existing.draft_id.present?
        begin
          @gmail_client.trash_draft(draft_id: existing.draft_id)
        rescue StandardError => e
          Rails.logger.warn("ClassifyHandler: failed to trash draft: #{e.message}")
        end
      end
    end
  end
end
