# System Architecture

## Overview

Gmail Assistant is a Rails 8.1 API-only application. It processes incoming Gmail messages through a classification pipeline, generates AI draft replies, and manages workflow state via Gmail labels. There is no HTML frontend -- Gmail itself is the UI.

## Runtime Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Rails Server (Puma)                                             │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐  │
│  │ Middleware    │  │ Controllers  │  │ Background Threads     │  │
│  │              │  │              │  │                        │  │
│  │ BasicAuth    │  │ Webhook::    │  │ Jobs::WorkerPool (3x)  │  │
│  │ (conditional)│→ │   Gmail      │  │   └─ poll Job.claim    │  │
│  │              │  │ Api::*       │  │   └─ dispatch handler  │  │
│  │              │  │ Admin::*     │  │                        │  │
│  │              │  │              │  │ Jobs::Scheduler         │  │
│  │              │  │              │  │   └─ watch renewal 24h │  │
│  │              │  │              │  │   └─ fallback sync 15m │  │
│  │              │  │              │  │   └─ full sync 1h      │  │
│  └──────────────┘  └──────────────┘  └────────────────────────┘  │
│                           │                      │               │
│                           ▼                      ▼               │
│                    ┌─────────────┐        ┌─────────────┐        │
│                    │  SQLite DB  │◄──────▶│  Services   │        │
│                    └─────────────┘        └─────────────┘        │
│                                                  │               │
│                                          ┌───────┴───────┐      │
│                                          ▼               ▼      │
│                                   ┌───────────┐   ┌──────────┐  │
│                                   │ Gmail API │   │ LLM API  │  │
│                                   └───────────┘   └──────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## Startup Sequence

Defined in `config/initializers/gmail_assistant.rb`. On server boot (skipped in console/test/rake):

1. `Jobs::WorkerPool.new.start` -- spawns N concurrent threads that poll for jobs
2. `Jobs::Scheduler.new.start` -- starts rufus-scheduler with recurring tasks
3. `at_exit` hook registered for graceful shutdown

## Request Flow

### Incoming Email (Push)
```
Google Pub/Sub POST /webhook/gmail
  → Webhook::GmailController#create
    → Decode Base64 payload (email_address, history_id)
    → Find user by email
    → Create Job(type: "sync", payload: {history_id})
    → Return 200 immediately
```

### Job Processing
```
WorkerPool thread wakes up
  → Job.claim_next (atomic SQLite UPDATE ... WHERE status=pending)
  → Jobs::Dispatcher routes to handler by job_type
  → Handler executes (Gmail API calls, LLM calls, DB writes)
  → Job marked complete or failed
```

## Database Schema

9 tables, all using SQLite:

| Table | Purpose | Key Constraints |
|-------|---------|-----------------|
| `users` | User accounts | `email` UNIQUE NOT NULL |
| `user_labels` | Gmail label mapping | Composite PK `(user_id, label_key)` |
| `user_settings` | Per-user config | Composite PK `(user_id, setting_key)` |
| `sync_states` | Gmail sync cursors | `user_id` UNIQUE, 1:1 with users |
| `emails` | Processed email records | UNIQUE `(user_id, gmail_thread_id)` |
| `email_events` | Immutable audit log | FK to emails, append-only |
| `jobs` | Persistent job queue | Index on `(status, created_at)` for claiming |
| `llm_calls` | LLM API audit trail | FK to users, optional gmail_thread_id |
| `agent_runs` | Agent execution log | FK to users and emails |

### Job Queue Design

No external queue (no Redis, no Sidekiq). The `jobs` table is the queue. Workers claim jobs atomically:

```ruby
# Optimistic locking fallback for SQLite (no FOR UPDATE)
Job.where(id: job.id, status: "pending")
   .update_all(status: "running", attempts: job.attempts + 1)
```

Jobs retry up to `max_attempts` (default 3). Failed jobs stay in DB for inspection.

## Service Layer

All business logic lives in `app/services/`, organized by domain:

```
app/services/
├── agents/                 # Agent framework
│   ├── router.rb          # Config-driven email → agent routing
│   ├── agent_loop.rb      # LLM tool-use conversation loop
│   ├── tool_registry.rb   # Tool registration and dispatch
│   ├── pharmacy_tools.rb  # Domain-specific tool implementations
│   └── crisp_preprocessor.rb  # Crisp helpdesk email parser
│
├── classification/         # Email triage
│   ├── classification_engine.rb  # Orchestrator (rules + LLM + style)
│   ├── rule_engine.rb           # Header-based automation detection
│   └── llm_classifier.rb       # LLM-based category assignment
│
├── drafting/              # Reply generation
│   ├── draft_generator.rb    # Style-aware draft with ✂️ marker
│   └── context_gatherer.rb   # Related email context via LLM queries
│
├── gmail/                 # Google API
│   ├── client.rb          # Gmail API wrapper (labels, messages, drafts, history)
│   └── watch_manager.rb   # Pub/Sub watch registration/renewal
│
├── jobs/                  # Background processing
│   ├── worker_pool.rb     # Concurrent worker threads
│   ├── scheduler.rb       # Recurring tasks (rufus-scheduler)
│   ├── dispatcher.rb      # Job type → handler routing
│   ├── sync_handler.rb    # Gmail sync execution
│   ├── classify_handler.rb     # Email classification (PLACEHOLDER)
│   ├── draft_handler.rb        # Draft generation (PLACEHOLDER)
│   ├── cleanup_handler.rb      # Done/sent detection (PLACEHOLDER)
│   ├── rework_handler.rb       # Draft rework (PLACEHOLDER)
│   ├── manual_draft_handler.rb # Manual NR label → draft (PLACEHOLDER)
│   └── agent_process_handler.rb # Agent routing (PLACEHOLDER)
│
├── lifecycle/             # Post-draft workflow
│   ├── done_handler.rb        # Archive: remove AI labels + INBOX
│   ├── rework_handler.rb      # Extract instructions, regenerate draft
│   ├── sent_detector.rb       # Detect draft sent → mark done
│   └── waiting_retriager.rb   # New message on waiting thread → retriage
│
├── llm/                   # LLM abstraction
│   └── gateway.rb         # Model-agnostic client with call logging
│
└── sync/                  # Gmail sync
    └── engine.rb          # Incremental (history) + full sync
```

### Dependency Injection

All services accept dependencies as constructor args. This enables testing with mocks:

```ruby
# Production
engine = Classification::ClassificationEngine.new(
  rule_engine: Classification::RuleEngine.new,
  llm_classifier: Classification::LlmClassifier.new(llm_gateway: Llm::Gateway.new(user: user))
)

# Test
engine = Classification::ClassificationEngine.new(
  rule_engine: Classification::RuleEngine.new,
  llm_classifier: Classification::LlmClassifier.new(llm_gateway: mock_gateway)
)
```

## Email Processing Pipeline

```
New email in INBOX
  │
  ├─ Sync::Engine detects via history API
  │   └─ Creates Job(type: classify | agent_process)
  │
  ├─ ClassifyHandler runs
  │   ├─ RuleEngine: check automation headers (List-Unsubscribe, Auto-Submitted, etc.)
  │   ├─ LlmClassifier: JSON response with category + confidence + style
  │   ├─ ClassificationEngine: safety net (automated + needs_response → fyi)
  │   ├─ Apply Gmail label (🤖 AI/Needs Response, FYI, etc.)
  │   └─ If needs_response → enqueue Job(type: draft)
  │
  ├─ DraftHandler runs
  │   ├─ ContextGatherer: find related emails via LLM-generated search queries
  │   ├─ DraftGenerator: style-aware reply with ✂️ rework marker
  │   ├─ Create Gmail draft in thread
  │   └─ Move labels: Needs Response → Outbox
  │
  └─ User reviews in Gmail
      ├─ Send draft → SentDetector detects → mark Done
      ├─ Apply "Rework" label → ReworkHandler → new draft (up to 3x)
      └─ Apply "Done" label → DoneHandler → archive
```

## Classification Categories

| Category | Label | Draft? | Description |
|----------|-------|--------|-------------|
| `needs_response` | 🤖 AI/Needs Response | Yes | Direct question or request |
| `action_required` | 🤖 AI/Action Required | No | Needs manual action |
| `payment_request` | 🤖 AI/Payment Requests | No | Invoice or billing |
| `fyi` | 🤖 AI/FYI | No | Informational only |
| `waiting` | 🤖 AI/Waiting | No | User sent last, awaiting reply |

Two-tier detection: Rule engine catches obvious automation (newsletters, noreply, bulk mail) before the LLM runs. Safety net: if rule engine flags automated but LLM says needs_response, override to fyi.

## LLM Integration

All LLM calls go through `Llm::Gateway`, which:
- Uses the `ruby-openai` gem (OpenAI-compatible API)
- Routes to different models per task (classify=fast/cheap, draft=high quality)
- Logs every call to `llm_calls` table (tokens, latency, errors)
- Returns `nil` on error (callers handle gracefully)

Configured via `config/app.yml` or env vars:
```
OPENAI_API_BASE=https://openrouter.ai/api/v1
OPENAI_API_KEY=your-key
GMA_LLM_CLASSIFY_MODEL=gemini/gemini-2.0-flash
GMA_LLM_DRAFT_MODEL=gemini/gemini-2.5-pro
```

## Agent Framework

For emails matching routing rules (sender, domain, subject, headers), an agent loop replaces the standard pipeline:

```
Agents::Router.match?(message)
  → AgentProcessHandler
    → Agents::AgentLoop.new(profile, tools, llm_client)
      → LLM with tool_use
      → ToolRegistry.execute(tool_name, args)
      → Loop until LLM returns final text or max_iterations
    → AgentRun record persisted
```

Agent profiles are defined in `config/app.yml` under `agent.profiles`. Each profile specifies: model, system_prompt_file, tools, max_iterations.

## API Structure

### Public (no auth)
- `POST /webhook/gmail` -- Pub/Sub push endpoint
- `GET /api/health` -- liveness probe

### Protected (Basic Auth when configured)
- `POST /api/auth/init` -- onboard user
- `POST /api/sync` -- trigger sync
- `POST /api/watch` -- register Gmail watch
- `GET /api/users` -- list users
- `GET /api/users/:id/emails` -- user's emails
- `GET /api/briefing/:email` -- inbox summary
- `GET /api/debug/emails` -- searchable email list
- `POST /api/emails/:id/reclassify` -- force reclassification
- `POST /api/reset` -- clear transient data (dev)

### Admin (read-only JSON, same auth)
- `GET /admin/emails` -- paginated email list (default route)
- `GET /admin/jobs` -- job queue inspection
- `GET /admin/llm_calls` -- LLM call history
- `GET /admin/users`, `/user_labels`, `/user_settings`, `/sync_states`, `/email_events`

## Configuration

All config in `config/app.yml`, overridable with `GMA_` prefixed env vars.

| Section | Key Settings |
|---------|-------------|
| `auth` | OAuth mode, credential paths, scopes |
| `llm` | Model names, max tokens per task |
| `sync` | Pub/Sub topic, sync intervals |
| `server` | Port, Basic Auth credentials, worker count |
| `routing` | Email → pipeline/agent routing rules |
| `agent` | Agent profiles (model, tools, prompts) |

Communication styles (`config/communication_styles.yml`) and contact mappings (`config/contacts.yml`) control draft tone per sender/domain.

## Test Architecture

```
spec/
├── models/         # ActiveRecord validations, associations, scopes
├── services/       # Unit tests with mocked dependencies
├── requests/       # API endpoint tests
├── integration/    # Multi-service workflow tests (39 cases)
└── support/
    ├── gmail_api_helpers.rb  # Gmail API response builders
    └── llm_helpers.rb        # LLM mock response helpers
```

229 examples, 0 failures. Integration tests cover the full lifecycle from classification through draft to archive.

## Known Limitations (Current State)

1. **Job handlers are placeholders** -- ClassifyHandler, DraftHandler, CleanupHandler, ReworkHandler, ManualDraftHandler, AgentProcessHandler log and return without executing real logic. The service classes they should call (ClassificationEngine, DraftGenerator, lifecycle handlers) are fully implemented.
2. **Auth/onboarding is stubbed** -- `POST /api/auth/init` returns mock data, doesn't run OAuth or provision labels.
3. **Watch registration is stubbed** -- `POST /api/watch` returns mock response.
4. **Gmail::Client missing methods** -- `modify_thread`, `search_threads`, `draft_exists?`, `trash_draft` are called by services but not implemented on the client.
