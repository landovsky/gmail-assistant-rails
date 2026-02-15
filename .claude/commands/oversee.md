---
description: Master overseer that coordinates sandboxed agents to complete project work
argument-hint: "<optional: specific focus area or task to prioritize>"
---

You are a master agent overseeing work on this project. You do not do any coding yourself. Your role is to:

1. Ensure work on the project is being done by maintaining at most 2 running sandboxed sessions via `claude-sandbox local`.
2. Ensure the project is completed, but not over-completed (see that the agents don't manufacture work just to comply).
3. Keep running until it's done so that there's always someone who keeps the lights on or turn them off.

## Running sandbox agents

**Command pattern** (no `script` wrapper needed — launcher auto-detects non-interactive mode):
```bash
claude-sandbox local "Your task description here" 2>&1
```

- Use `run_in_background: true` on the Bash tool and set `timeout: 600000` (10 min max).
- **Only run 1 sandbox at a time** — local mode shares a single workspace volume, so concurrent runs conflict.
- Monitor progress via `docker logs <container-name> 2>&1 | tail -50` (NOT the script output file, which buffers until exit).
- Find the container name with `docker ps --format "table {{.Names}}\t{{.Status}}"`.
- The sandbox output only shows final results (file reads, reasoning, etc. are not streamed mid-flight), so sparse output is normal — be patient.

## Session recovery

If starting a fresh session (after compaction, clear, or restart):

1. Run `bd prime` to reload beads context.
2. Run `bd stats` and `bd list --status=open` and `bd list --status=in_progress` to understand current project state.
3. Run `git log --oneline -20` to see what's been committed recently.
4. Check for any running Docker containers: `docker ps --format "table {{.Names}}\t{{.Status}}"`.
5. Resume oversight — launch new sandbox agents for any unfinished or ready work.

## Staying in sync with agent work

Sandbox agents push directly to `main`. To stay current:

- Run `git fetch && git pull --rebase` **before** checking `bd ready` or launching new agents.
- Run `bin/bd-sync` **after** pulling to pick up beads state changes made by agents.
- Do this every check cycle (~120s), not just at session start.

## Work tracking

- All tasks are tracked via beads (`bd ready`, `bd list`, `bd show <id>`).
- Sandbox agents are instructed to pick up beads, mark them in_progress, and close them when done.
- Use `bin/bd-sync` (not `bd sync`) to push beads state to remote.

## Known gotchas

- **No `script` wrapper**: The launcher auto-detects non-interactive mode and uses `docker compose run -T` instead of `-it`. Just call `claude-sandbox local "..."` directly.
- **Bootstrap catch-22**: If the project has no `Gemfile`/`database.yml` yet, sandboxes can't provision PG. Do the initial `rails new` locally, commit+push, then use sandboxes for everything after.
- **Sparse output is normal**: Sandbox output only shows final results. Don't panic if output looks stuck for 2-3 minutes — check `docker ps` to confirm the container is running.
- **Agent conflicts**: Two agents pushing to `main` simultaneously can cause push failures. Prefer giving agents independent files/directories when possible (e.g., data model vs LLM gateway).
- **One agent at a time (local)**: Local sandbox agents share a single Docker Compose project and workspace volume. Run only 1 sandbox agent at a time. Clean up volumes between runs: `docker compose -f ~/.claude/claude-sandbox/docker-compose.yml --profile with-postgres --profile with-redis down -v`
- **Beads not synced into sandbox**: The sandbox container doesn't have access to the local beads database. Don't rely on agents closing beads — close them from the overseer after verifying the work was pushed.
