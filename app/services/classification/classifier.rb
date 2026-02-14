# frozen_string_literal: true

module Classification
  # Orchestrates the two-tier classification pipeline and applies Gmail labels
  #
  # 1. Runs rule-based automation detection
  # 2. Runs LLM classification
  # 3. Applies safety net (override needs_response → fyi for automated emails)
  # 4. Applies Gmail labels based on final classification
  class Classifier
    CATEGORY_TO_LABEL = {
      "needs_response" => "needs_response",
      "action_required" => "action_required",
      "payment_request" => "payment_request",
      "fyi" => "fyi",
      "waiting" => "waiting"
    }.freeze

    # Classify an email and apply labels
    #
    # @param email [Email] Email record to classify
    # @param message [Google::Apis::GmailV1::Message] Gmail message object
    # @return [Email] Updated email record
    def self.classify_and_label(email:, message:)
      new(email: email, message: message).classify_and_label
    end

    def initialize(email:, message:)
      @email = email
      @message = message
      @user = email.user
    end

    def classify_and_label
      # Parse message
      parser = Gmail::MessageParser.new(@message)
      headers = parser.headers
      body = parser.body

      # Step 1: Rule-based automation detection
      is_automated = Classification::RulesEngine.automated?(
        sender_email: @email.sender_email,
        headers: headers
      )

      # Step 2: LLM classification
      llm_result = Classification::LlmClassifier.classify(
        sender_name: @email.sender_name,
        sender_email: @email.sender_email,
        subject: @email.subject,
        body: body,
        snippet: @email.snippet,
        message_count: @email.message_count,
        user: @user,
        gmail_thread_id: @email.gmail_thread_id
      )

      # Step 3: Apply safety net
      final_category = apply_safety_net(
        llm_category: llm_result[:category],
        is_automated: is_automated
      )

      final_confidence = if final_category != llm_result[:category]
        "high" # High confidence in safety net override
      else
        llm_result[:confidence]
      end

      # Update email record
      @email.update!(
        classification: final_category,
        confidence: final_confidence,
        reasoning: llm_result[:reasoning],
        detected_language: llm_result[:detected_language],
        resolved_style: llm_result[:resolved_style],
        processed_at: Time.current
      )

      # Log classification event
      EmailEvent.create!(
        user: @user,
        gmail_thread_id: @email.gmail_thread_id,
        event_type: "classified",
        detail: "#{final_category} (#{final_confidence})"
      )

      # Apply Gmail label
      apply_classification_label(final_category)

      @email
    rescue => e
      Rails.logger.error "Classification failed for thread #{@email.gmail_thread_id}: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Log error event
      EmailEvent.create!(
        user: @user,
        gmail_thread_id: @email.gmail_thread_id,
        event_type: "error",
        detail: "Classification failed: #{e.message}"
      )

      raise
    end

    private

    def apply_safety_net(llm_category:, is_automated:)
      if is_automated && llm_category == "needs_response"
        Rails.logger.info "Safety net: overriding needs_response → fyi for automated email #{@email.gmail_thread_id}"
        "fyi"
      else
        llm_category
      end
    end

    def apply_classification_label(category)
      label_key = CATEGORY_TO_LABEL[category]
      return unless label_key

      # Get the label ID for this user
      user_label = UserLabel.find_by(user: @user, label_key: label_key)
      unless user_label
        Rails.logger.warn "Label '#{label_key}' not found for user #{@user.id}"
        return
      end

      # Get all messages in the thread
      thread = Gmail::Client.new(@user).get_thread(@email.gmail_thread_id, format: "minimal")
      message_ids = thread.messages.map(&:id)

      # Apply label to all messages in thread
      Gmail::Client.new(@user).batch_modify_messages(
        message_ids,
        add_label_ids: [user_label.gmail_label_id]
      )

      # Log label addition
      EmailEvent.create!(
        user: @user,
        gmail_thread_id: @email.gmail_thread_id,
        event_type: "label_added",
        label_id: user_label.gmail_label_id,
        detail: user_label.gmail_label_name
      )

      Rails.logger.info "Applied label '#{label_key}' to thread #{@email.gmail_thread_id}"
    rescue => e
      Rails.logger.error "Failed to apply label '#{label_key}' to thread #{@email.gmail_thread_id}: #{e.class} - #{e.message}"
      # Don't raise - label application is not critical
    end
  end
end
