# Email Sync Engine

The email sync engine detects new and changed Gmail messages using three complementary mechanisms:

1. **Gmail History API** - Incremental sync that tracks changes since last sync
2. **Polling Fallback** - Periodic background jobs that ensure nothing is missed
3. **Pub/Sub Webhooks** - Real-time push notifications from Google

## Architecture

### Components

- **`Gmail::SyncEngine`** - Core service that performs incremental or full sync using History API
- **`Gmail::WatchManager`** - Manages Pub/Sub watch registration and renewal
- **`SyncJob`** - Background job for polling and processing sync requests
- **`WebhooksController`** - HTTP endpoint that receives Pub/Sub notifications

### Data Flow

```
Gmail Change Occurs
      |
      v
[Pub/Sub Push] ---> WebhooksController ---> SyncJob
                           |
                           v
      [Polling Job] ---> SyncJob ---> Gmail::SyncEngine
                                           |
                                           v
                                  History API / Full Sync
                                           |
                                           v
                                  Create Email Records
                                  Enqueue Processing Jobs
```

## Gmail History API

### Incremental Sync

The History API provides efficient change detection:

1. Start from `last_history_id` stored in `sync_states` table
2. Fetch history records in batches (100 per page)
3. Process each history record type:
   - **messagesAdded** - New INBOX messages → enqueue classify jobs
   - **labelsAdded** - User actions (Needs Response, Rework, Done) → enqueue corresponding jobs
   - **messagesDeleted** - Draft deletion → enqueue cleanup jobs
4. Update `last_history_id` to newest value
5. Deduplication by `(job_type, thread_id)` prevents duplicate processing

### Full Sync Fallback

Triggered when:
- User has no sync state (first run)
- `last_history_id` is too old (Gmail returns error)
- Last sync was more than 30 days ago

Process:
1. Search for recent INBOX messages (default: 10 days back)
2. Exclude AI-labeled, trash, and spam
3. Fetch up to 50 messages
4. Enqueue classify jobs
5. Store current `history_id` from user profile

## Pub/Sub Integration

### Watch Setup

To enable real-time notifications:

1. Create a Google Cloud Pub/Sub topic
2. Grant publish permission to `gmail-api-push@system.gserviceaccount.com`
3. Configure push subscription to POST to `/webhooks/gmail`
4. Set `Rails.application.config.gmail_pubsub_topic` (format: `projects/{project}/topics/{topic}`)
5. Run `rake gmail:watch:setup[user_id]` or `Gmail::WatchManager.new(user).setup_watch!`

### Watch Lifecycle

- **Expiration**: Gmail watches expire after 7 days
- **Renewal**: Automatically renews 24 hours before expiration
- **Renewal Job**: Run `rake gmail:watch:renew` daily (recommended: cron or scheduled job)

### Watched Labels

The watch monitors:
- `INBOX` - New message arrivals
- `🤖 AI/Needs Response` - Manual draft requests
- `🤖 AI/Rework` - Rework requests
- `🤖 AI/Done` - Archive/cleanup actions

## Polling Fallback

To ensure reliability even if Pub/Sub is disrupted:

```ruby
# Schedule this to run every 15 minutes
SyncJob.sync_all_users
```

Recommended setup with `whenever` gem or cron:

```ruby
# config/schedule.rb
every 15.minutes do
  runner "SyncJob.sync_all_users"
end
```

## Configuration

Add to `config/application.rb` or environment files:

```ruby
# Required for Pub/Sub webhooks
config.gmail_pubsub_topic = ENV["GMAIL_PUBSUB_TOPIC"] || "projects/my-project/topics/gmail-push"
```

## Usage

### Manual Sync

```bash
# Sync specific user
rake gmail:sync:user[123]

# Sync all users
rake gmail:sync:all

# Enqueue background jobs for all users
rake gmail:sync:poll
```

### Watch Management

```bash
# Setup watch for user
rake gmail:watch:setup[123]

# Stop watch for user
rake gmail:watch:stop[123]

# Setup watches for all users
rake gmail:watch:setup_all

# Renew expiring watches (run daily)
rake gmail:watch:renew
```

### Programmatic Usage

```ruby
# Sync a user
user = User.find(123)
Gmail::SyncEngine.new(user).sync!

# Setup watch
Gmail::WatchManager.new(user).setup_watch!

# Background job
SyncJob.perform_later(user.id)
```

## Database Schema

### sync_states

| Column | Type | Description |
|--------|------|-------------|
| `user_id` | bigint | Foreign key to users |
| `last_history_id` | text | Last processed Gmail history ID |
| `last_sync_at` | timestamp | Last successful sync timestamp |
| `watch_expiration` | timestamp | When Pub/Sub watch expires |
| `watch_resource_id` | text | Gmail watch resource identifier |

## Error Handling

### History API Errors

- **404 / historyId too old**: Automatically falls back to full sync
- **Network errors**: Retried up to 3 times with exponential backoff
- **Rate limits (429)**: Retried with backoff

### Watch Errors

- **Setup failures**: Logged and raised (should retry)
- **Missing topic**: Logged as error, watch not created
- **Expired watch**: Auto-renewed by scheduled task

### Webhook Errors

- **Invalid payload**: Returns 400 Bad Request
- **User not found**: Returns 404 Not Found
- **Processing errors**: Returns 500, logged

## Monitoring

### Key Metrics

- `sync_states.last_sync_at` - Detect stale syncs
- `sync_states.watch_expiration` - Detect expired watches
- Job queue depth - Detect processing backlog
- Webhook error rate - Detect Pub/Sub issues

### Health Checks

```ruby
# Check for users with stale syncs (> 1 hour old)
SyncState.where("last_sync_at < ?", 1.hour.ago).count

# Check for expired watches
SyncState.where("watch_expiration < ?", Time.current).count

# Check for users missing watches
User.left_joins(:sync_state)
    .where(sync_states: { watch_expiration: nil })
    .or(User.left_joins(:sync_state).where(sync_states: { id: nil }))
    .count
```

## Deployment Checklist

1. ✅ Create Google Cloud Pub/Sub topic
2. ✅ Grant permissions to Gmail push service account
3. ✅ Configure push subscription to webhook URL
4. ✅ Set `GMAIL_PUBSUB_TOPIC` environment variable
5. ✅ Deploy application with webhook endpoint
6. ✅ Run `rake gmail:watch:setup_all` for existing users
7. ✅ Schedule `rake gmail:watch:renew` to run daily
8. ✅ Schedule `SyncJob.sync_all_users` to run every 15 minutes
9. ✅ Set up monitoring for sync health

## Troubleshooting

### No new emails detected

1. Check `last_sync_at` - is sync running?
2. Check watch expiration - is watch active?
3. Check webhook logs - are notifications arriving?
4. Test webhook manually with curl
5. Run manual sync: `rake gmail:sync:user[id]`

### Duplicate processing

- Deduplication happens per sync run
- If sync runs overlap, may process same changes twice
- Ensure idempotent job handlers

### Missing notifications

- Pub/Sub delivery is best-effort, not guaranteed
- Polling fallback ensures eventual consistency
- Check Pub/Sub subscription configuration
- Verify webhook endpoint is publicly accessible
