# Gmail Assistant

A self-hosted service that automatically processes incoming Gmail messages — classifying them, generating AI draft replies, and managing the entire workflow through Gmail labels. Your Gmail client **is** the UI.

## Why?

Email takes too much time. Most messages fall into predictable categories: things that need a reply, things that need action, invoices, FYI notifications, and threads where you're waiting for a response. This system handles the triage automatically and drafts replies for you, so you only review and send.

**No new app to learn.** Everything happens through Gmail labels you already know how to use.

## How It Works

```
New email arrives in Gmail
    ↓
Google Pub/Sub sends push notification → your server
    ↓
Email is classified into one of 5 categories:
  • Needs Response  → AI draft reply is generated
  • Action Required → labeled, you handle manually
  • Payment Request → labeled for tracking
  • FYI             → labeled, no action needed
  • Waiting         → you sent last message, monitoring for reply
    ↓
For "Needs Response" emails:
  1. Draft appears in your Gmail thread
  2. Review it, edit if needed, send
  3. Or request a rework: type instructions above the ✂️ marker,
     apply the "Rework" label, and a new draft is generated
  4. Or mark "Done" to archive without responding
```

## Features

- **Two-tier classification** — Rule-based automation detection (catches newsletters, noreply senders) + LLM classification for everything else
- **Smart drafting** — Configurable communication styles per contact/domain, language matching (Czech, English, German), context-aware replies using prior correspondence
- **Rework loop** — Not happy with a draft? Write instructions above the ✂️ marker, apply "Rework" label, get a new version (up to 3 times)
- **Agent framework** — Route specific emails (by sender, domain, subject) to LLM agents with tool access instead of the standard pipeline
- **Lifecycle management** — Automatic sent detection, archiving, waiting-thread retriage
- **Multi-user support** — Each user gets their own labels, settings, and sync state
- **Fail-safe defaults** — On any LLM error, emails default to "Needs Response" (safer to over-triage than miss something)

## Setup

### Prerequisites

- Ruby 3.2+
- SQLite 3
- A Google Cloud project with Gmail API enabled
- An LLM API key (any OpenAI-compatible provider — OpenRouter, Gemini, etc.)

### 1. Clone and install

```bash
git clone git@github.com:landovsky/gmail-assistant-rails.git
cd gmail-assistant-rails
bundle install
bin/rails db:migrate
```

### 2. Google OAuth credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a project (or use existing)
3. Enable the **Gmail API**
4. Create OAuth 2.0 credentials (Desktop application)
5. Download as `config/credentials.json`
6. On first run, a browser window opens for consent. Tokens are cached in `config/token.json`

**Required OAuth scope:** `https://www.googleapis.com/auth/gmail.modify`

### 3. Configure

Edit `config/app.yml`:

```yaml
# LLM models (any OpenAI-compatible API)
llm:
  classify_model: gemini/gemini-2.0-flash    # fast, cheap
  draft_model: gemini/gemini-2.5-pro         # higher quality
  context_model: gemini/gemini-2.0-flash

# Server
server:
  admin_user: admin          # set for Basic Auth (leave empty to disable)
  admin_password: changeme
  worker_concurrency: 3      # concurrent job workers

# Gmail sync
sync:
  pubsub_topic: projects/YOUR_PROJECT/topics/gmail-push  # optional
  fallback_interval_minutes: 15
```

Set your LLM API key:
```bash
export OPENAI_API_KEY=your-key-here
# or for Gemini via OpenRouter:
export OPENAI_API_BASE=https://openrouter.ai/api/v1
```

All settings can be overridden with environment variables (prefix `GMA_`):
```bash
export GMA_SERVER_ADMIN_USER=admin
export GMA_SERVER_ADMIN_PASSWORD=secret
export GMA_LLM_CLASSIFY_MODEL=gpt-4o-mini
```

### 4. Customize communication styles

Edit `config/communication_styles.yml` to define how drafts should sound:

```yaml
styles:
  business:
    rules:
      - "Keep the tone professional and courteous"
    sign_off: "Best regards,\nYour Name"
    language: auto    # matches incoming email language
  casual:
    rules:
      - "Keep it relaxed and friendly"
    sign_off: "Cheers,\nYour Name"
```

Map contacts to styles in `config/contacts.yml`:

```yaml
style_overrides:
  friend@example.com: casual
  boss@company.com: business
domain_overrides:
  "*.gov.cz": business
blacklist:
  - "*@marketing.spam.com"
```

### 5. Start the server

```bash
bin/rails server
```

### 6. Initialize your account

```bash
curl -X POST http://localhost:3000/api/auth/init
```

This creates your user, provisions Gmail labels (🤖 AI/*), imports settings, and starts sync.

### 7. (Optional) Set up Pub/Sub for real-time processing

Without Pub/Sub, the system polls every 15 minutes. With Pub/Sub, emails are processed in near real-time.

1. Create a Pub/Sub topic in Google Cloud
2. Grant publish access to `gmail-api-push@system.gserviceaccount.com`
3. Create a push subscription pointing to `https://your-server/webhook/gmail`
4. Register the watch: `curl -X POST http://localhost:3000/api/watch`

## Gmail Labels

After setup, these labels appear in your Gmail:

| Label | Meaning |
|-------|---------|
| 🤖 AI/Needs Response | Email needs a reply (draft incoming) |
| 🤖 AI/Outbox | Draft ready for review |
| 🤖 AI/Rework | You requested a draft revision |
| 🤖 AI/Action Required | Needs your action (no auto-draft) |
| 🤖 AI/Payment Requests | Invoice or billing |
| 🤖 AI/FYI | Informational, no action needed |
| 🤖 AI/Waiting | You sent last, waiting for reply |
| 🤖 AI/Done | Processed and archived |

## API

All endpoints return JSON. Protected by Basic Auth when configured.

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/health` | Liveness probe |
| GET | `/api/users` | List users |
| POST | `/api/users` | Create user |
| GET | `/api/users/:id/emails` | List emails (filter by status/classification) |
| GET | `/api/briefing/:email` | Inbox summary by category |
| POST | `/api/sync` | Trigger manual sync |
| GET | `/api/debug/emails` | Debug email list with search |
| GET | `/api/emails/:id/debug` | Full debug data for one email |
| POST | `/api/emails/:id/reclassify` | Force reclassification |
| POST | `/api/reset` | Clear transient data (dev/testing) |

## Architecture

```
app/
├── controllers/        # API endpoints (webhook, admin, debug, briefing)
├── middleware/          # Basic Auth
├── models/             # 9 ActiveRecord models
├── services/
│   ├── agents/         # Router, AgentLoop, ToolRegistry, preprocessors
│   ├── classification/ # RuleEngine, LlmClassifier, ClassificationEngine
│   ├── drafting/       # DraftGenerator, ContextGatherer
│   ├── gmail/          # Gmail API client, WatchManager
│   ├── jobs/           # WorkerPool, Scheduler, 7 job handlers
│   ├── lifecycle/      # DoneHandler, SentDetector, ReworkHandler, WaitingRetriager
│   └── llm/            # LLM Gateway (model-agnostic)
└── lib/                # AppConfig
```

**Key patterns:**
- **Queue-driven**: All work flows through a persistent job queue with atomic claiming
- **Label-as-state**: Gmail labels represent email state; the system reads and writes them
- **Fail-safe**: LLM errors default to "Needs Response" (over-triage > missed email)
- **Dependency injection**: All services accept their dependencies as constructor args (testable)

## Testing

```bash
bundle exec rspec                           # full suite
bundle exec rspec spec/models/              # model tests
bundle exec rspec spec/services/            # service tests
bundle exec rspec spec/requests/            # API tests
bundle exec rspec spec/integration/         # integration tests
```

## License

Private — not open source.
