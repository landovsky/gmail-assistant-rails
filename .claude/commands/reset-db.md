Reset the local development database by clearing transient data.

## Steps

1. **Ensure the dev server is running** at http://localhost:3000

2. **Check server health:**
   ```bash
   curl http://localhost:3000/api/health
   ```

3. **Reset transient data via the API:**
   ```bash
   curl -X POST http://localhost:3000/api/reset
   ```
   This clears: jobs, emails, email_events, llm_calls, sync_state.
   Preserves: users, user_labels, user_settings.

4. **Verify the reset** by checking admin endpoints:
   ```bash
   curl http://localhost:3000/admin/jobs
   curl http://localhost:3000/admin/emails
   ```
   Both should return `{"total": 0, ...}`.

## Alternative: Full database reset

To completely recreate the database schema:
```bash
bin/rails db:drop db:create db:migrate
```

## Alternative: Use the bin script

```bash
bin/reset-db --env dev
```
