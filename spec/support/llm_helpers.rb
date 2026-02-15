module LlmHelpers
  # --- Classification responses ---

  # Valid classification response from LLM
  def llm_classify_response(
    category: "needs_response",
    confidence: "high",
    reasoning: "Direct question requiring a reply",
    detected_language: "en",
    resolved_style: "business"
  )
    {
      "category" => category,
      "confidence" => confidence,
      "reasoning" => reasoning,
      "detected_language" => detected_language,
      "resolved_style" => resolved_style
    }.to_json
  end

  # Classification response for FYI
  def llm_classify_fyi_response
    llm_classify_response(
      category: "fyi",
      confidence: "high",
      reasoning: "Automated notification, no response needed"
    )
  end

  # Classification response for action_required
  def llm_classify_action_response
    llm_classify_response(
      category: "action_required",
      confidence: "high",
      reasoning: "Meeting invitation requiring confirmation"
    )
  end

  # Classification response for payment_request
  def llm_classify_payment_response
    llm_classify_response(
      category: "payment_request",
      confidence: "high",
      reasoning: "Invoice with amount due"
    )
  end

  # Classification response for waiting
  def llm_classify_waiting_response
    llm_classify_response(
      category: "waiting",
      confidence: "medium",
      reasoning: "User sent the last message, awaiting reply"
    )
  end

  # Malformed LLM response (not valid JSON)
  def llm_malformed_response
    "I think this email is about a meeting. Category: action_required"
  end

  # LLM response with unknown category
  def llm_unknown_category_response
    { "category" => "urgent", "confidence" => "high", "reasoning" => "Seems urgent" }.to_json
  end

  # --- Draft responses ---

  # Valid draft response from LLM
  def llm_draft_response(body: nil)
    body || "Thank you for your message. I will look into this and get back to you shortly.\n\nBest regards,\nJohn"
  end

  # Draft response with error marker (simulating LLM failure fallback)
  def llm_draft_error_response(error: "API rate limit exceeded")
    "[ERROR: Draft generation failed — #{error}]"
  end

  # Rework draft response
  def llm_rework_response(body: nil)
    body || "Thanks for reaching out. I'll handle this right away.\n\nCheers,\nJohn"
  end

  # --- Context gathering responses ---

  # LLM response for context query generation
  def llm_context_queries_response(queries: nil)
    queries ||= [
      "from:sender@example.com subject:project",
      "thread about quarterly review",
      "sender@example.com invoice"
    ]
    queries.to_json
  end

  # Malformed context queries response
  def llm_context_queries_malformed
    "Search for emails about the project update"
  end

  # --- Agent responses ---

  # Agent LLM response with tool calls
  def llm_agent_tool_call_response(tool_name:, arguments:, call_id: nil)
    {
      role: "assistant",
      content: nil,
      tool_calls: [
        {
          id: call_id || "call_#{SecureRandom.hex(6)}",
          type: "function",
          function: {
            name: tool_name,
            arguments: arguments.is_a?(String) ? arguments : arguments.to_json
          }
        }
      ]
    }
  end

  # Agent LLM response with multiple tool calls
  def llm_agent_multi_tool_response(calls)
    {
      role: "assistant",
      content: nil,
      tool_calls: calls.map do |call|
        {
          id: call[:id] || "call_#{SecureRandom.hex(6)}",
          type: "function",
          function: {
            name: call[:name],
            arguments: call[:arguments].is_a?(String) ? call[:arguments] : call[:arguments].to_json
          }
        }
      end
    }
  end

  # Agent LLM final response (no tool calls, just text)
  def llm_agent_final_response(content: "I've completed the task.")
    {
      role: "assistant",
      content: content
    }
  end

  # --- Mock LLM client ---

  # Create a mock LLM client that returns predetermined responses
  def mock_llm_client(responses: [])
    client = double("LlmClient")
    call_index = 0

    allow(client).to receive(:chat) do |**_args|
      response = responses[call_index] || responses.last
      call_index += 1
      response
    end

    client
  end

  # Create a mock LLM client that raises an error
  def mock_llm_client_error(error_class: RuntimeError, message: "LLM API error")
    client = double("LlmClient")
    allow(client).to receive(:chat).and_raise(error_class, message)
    client
  end

  # Create a mock LLM client that returns raw text (for classify/draft)
  def mock_llm_text_client(text)
    client = double("LlmClient")
    allow(client).to receive(:chat).and_return(text)
    client
  end
end

RSpec.configure do |config|
  config.include LlmHelpers
end
