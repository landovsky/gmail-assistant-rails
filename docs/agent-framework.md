# Agent Framework

The agent framework provides an alternative processing path for emails that match specific routing rules. Instead of the standard classify→draft pipeline, matched emails are processed by an LLM agent that can use registered tools in a multi-turn conversation loop.

## Architecture

The framework consists of four main components:

### 1. Router (`app/services/agent/router.rb`)

Config-driven router that matches emails to processing paths based on:
- Sender email address
- Sender domain
- Subject keywords
- Header patterns
- Forwarding detection

**Route outcomes:**
- `pipeline` - Standard classify→draft flow
- `agent` - Agent processing with specified profile

### 2. Tool Registry (`app/services/agent/tool_registry.rb`)

Manages available tools for agents:
- Registration with name, description, parameters, and handler
- Spec generation in OpenAI function-calling format
- Tool execution with error handling
- Filtering by tool name list for different agent profiles

**Default tools:**
- `search_mailbox` - Search user's mailbox
- `apply_label` - Apply Gmail labels
- `create_draft` - Create draft replies

### 3. Agent Runner (`app/services/agent/runner.rb`)

Executes the multi-turn agent loop:
1. Loads system prompt from profile config
2. Calls LLM with messages + tool specifications
3. Processes tool calls from LLM response
4. Appends results and continues
5. Repeats until agent completes or max_iterations reached

**Result statuses:**
- `completed` - Agent finished voluntarily
- `max_iterations` - Hit iteration limit
- `error` - LLM call or execution failed

### 4. Background Job (`app/jobs/agent_process_job.rb`)

Handles async agent execution:
- Creates `AgentRun` record
- Preprocesses email (extracts structured data)
- Runs agent loop
- Stores results and tool calls
- Logs email event

## Configuration

### Config File: `config/agent.yml`

See `config/agent.yml.example` for full example.

**Routing rules:**
```yaml
routing:
  rules:
    - name: pharmacy_support
      match:
        forwarded_from: "info@dostupnost-leku.cz"
      route: agent
      profile: pharmacy
    - name: default
      match:
        all: true
      route: pipeline
```

**Agent profiles:**
```yaml
agent:
  profiles:
    pharmacy:
      model: gemini/gemini-2.0-flash-exp
      max_tokens: 4096
      temperature: 0.3
      max_iterations: 10
      preprocessor: crisp  # Optional: default, crisp
      system_prompt_file: config/prompts/pharmacy.txt
      tools:
        - search_drugs
        - manage_reservation
        - create_draft
```

### Routing Conditions

| Condition | Type | Behavior |
|-----------|------|----------|
| `all: true` | boolean | Matches every email |
| `sender_email` | string | Exact match on sender |
| `sender_domain` | string | Match on domain (after @) |
| `subject_contains` | string | Case-insensitive substring |
| `header_match` | object | Regex patterns for headers |
| `forwarded_from` | string | Detects forwarded emails |

Multiple conditions use AND logic (all must match).

## Preprocessors

Preprocessors extract structured data from emails before agent processing.

**Available preprocessors:**
- `default` - Pass-through (sender, subject, body)
- `crisp` - Extracts customer info from Crisp helpdesk emails

Configure in agent profile:
```yaml
preprocessor: crisp
```

## Registering Tools

Tools are registered in `config/initializers/agent_tools.rb`:

```ruby
Agent::ToolRegistry.register(
  "tool_name",
  description: "What the tool does",
  parameters: {
    type: "object",
    properties: {
      param1: { type: "string", description: "..." },
      param2: { type: "integer", default: 5 }
    },
    required: ["param1"]
  }
) do |param1:, param2: 5|
  # Tool implementation
  { result: "data" }
end
```

## Integration

The router is integrated into `Gmail::SyncEngine`. When a new INBOX message arrives:

1. Check if `config/agent.yml` exists
2. If yes, load config and check routing rules
3. If route is `agent`, enqueue `AgentProcessJob` with profile
4. If route is `pipeline` or no match, enqueue `ClassifyJob`

## Database

Agent executions are tracked in:
- `agent_runs` - One row per execution with status, tool calls, results
- `llm_calls` - One row per LLM turn (call_type='agent')
- `email_events` - Summary event (event_type='agent_processed')

## System Prompts

Store system prompts in `config/prompts/`:
- Plain text files
- Referenced by `system_prompt_file` in profile config
- Contains agent instructions and guidelines

See `config/prompts/example.txt` for template.

## Current Limitations

- Default tools (`search_mailbox`, `apply_label`, `create_draft`) are stubbed
- Pharmacy-domain tools are not implemented
- No built-in escalation workflow
- No human-in-the-loop approval for actions

## Future Enhancements

- Implement real tool handlers (Gmail search, label management, draft creation)
- Add more preprocessors (Zendesk, Intercom, etc.)
- Human approval workflow for sensitive actions
- Agent memory/context across conversations
- A/B testing framework for prompts and models
- Cost and latency monitoring
