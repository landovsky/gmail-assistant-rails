# Sandbox Overseer - Operational Gotchas

Lessons learned from running `claude-sandbox local` agents via the `/oversee` command.

## Launcher Issues

### No `script` wrapper needed
**Problem**: `script -q /dev/null claude-sandbox local "..."` was recommended for pseudo-TTY, but it swallows all output and causes the container to exit immediately when run in background mode from Claude Code.
**Fix**: Just use `claude-sandbox local "..." 2>&1` directly. The launcher auto-detects non-interactive mode and uses `docker compose run -T` instead of `-it`.

### SSH vs HTTPS URL mismatch
**Problem**: `.ruby-version` detection failed because the local git remote is SSH (`git@github.com:...`) while the auto-detected REPO_URL is HTTPS (`https://github.com/...`). The string comparison fails, so the local `.ruby-version` is skipped, defaulting to wrong Ruby version (3.4 instead of 3.2).
**Fix**: Normalize both URLs before comparison (strip `git@github.com:` → `https://github.com/`, strip `.git` suffix).

### `git archive` doesn't work over HTTPS
**Problem**: Fallback detection via `git archive --remote=<HTTPS_URL>` silently fails because GitHub doesn't support `git archive` over HTTPS.
**Impact**: If local `.ruby-version` detection also fails (see above), defaults to wrong Ruby version.

## Docker / Infrastructure Issues

### PostgreSQL host hardcoded to `localhost`
**Problem**: The entrypoint `pg_isready` check used `POSTGRES_HOST="localhost"` instead of parsing the hostname from `DATABASE_URL`. In Docker Compose, PG runs as a separate container on hostname `postgres`, not `localhost`.
**Fix**: Parse host from `DATABASE_URL` using sed: `echo "$DATABASE_URL" | sed -E 's|.*@([^:/]+).*|\1|'`. Same fix needed for Redis.

### Dependency services not auto-started
**Problem**: `docker compose run claude` only starts services listed in `depends_on`, which was `{}` (empty). PG and Redis containers never started alongside Claude.
**Fix**: Explicitly run `docker compose up -d postgres redis` before `docker compose run claude`.

### PostGIS image is amd64-only on Apple Silicon
**Problem**: `postgis/postgis:16-3.4-alpine` runs under Rosetta emulation on arm64 Macs. Slower startup but works. Not the cause of the PG readiness failure (that was the hostname bug).
**Impact**: Minor performance hit. Could switch to `postgres:16-alpine` if PostGIS isn't needed.

### Stale database state from previous runs
**Problem**: `postgres_data` volume persists between sandbox runs. If a previous run created partial schema, the next `db:prepare` fails with `PG::DuplicateTable`.
**Fix**: Added fallback in entrypoint: if `db:prepare` fails, try `db:drop db:create db:migrate`. Also clean volumes between runs: `docker compose ... down -v`.

### `DATABASE_URL` used `postgis://` adapter
**Problem**: Docker Compose set `DATABASE_URL: postgis://...` but Rails expects `postgresql://`.
**Fix**: Changed to `postgresql://` in `docker-compose.yml`.

## Workspace / Concurrency Issues

### Shared workspace volume prevents parallel agents
**Problem**: All local sandbox instances share `claude_workspace` Docker volume. Two agents writing to the same `/workspace` directory causes file conflicts, git push failures, and merged commits containing unrelated work.
**Recommendation**: Run only 1 sandbox agent at a time locally. Clean volumes between runs. For parallel execution, would need unique project names per sandbox instance.

### Work from one agent leaks to the next
**Problem**: Because the workspace volume persists, untracked files from Agent A's session are visible to Agent B. Agent B may commit Agent A's uncommitted work alongside its own.
**Impact**: Commits contain mixed changes from multiple tasks. Not harmful but messy.

## Beads / Task Tracking Issues

### Beads database not available in sandbox
**Problem**: The sandbox container initializes a fresh beads database. The overseer's beads state (which issues are open, in_progress, etc.) isn't synced into the container. Agents can't run `bd close` or `bd update` effectively.
**Workaround**: Don't rely on agents closing beads. Close them from the overseer after verifying work was pushed.

## Bootstrap Catch-22

### First project needs local bootstrap
**Problem**: Sandbox auto-detects services from project files (`Gemfile`, `database.yml`). On a brand-new project with no Rails scaffold, there's nothing to detect. PG/Redis may or may not be provisioned correctly.
**Fix**: Do the initial `rails new` locally, commit and push, then use sandboxes for all subsequent work.
