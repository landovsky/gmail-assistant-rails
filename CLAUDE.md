# Agent Instructions

Git repository upstream: git@github.com:landovsky/gmail-assistant-rails.git

## Artifacts Registry

This project maintains a registry of documentation artifacts at **`artifacts/registry.json`**.

### How to Use the Registry

**ALWAYS check `artifacts/registry.json` when:**
- Starting work on a new feature or bug fix
- Working with unfamiliar parts of the codebase
- Debugging code issues
- Writing or modifying code (frontend, backend, database, tests)
- Making architectural decisions

### Registry Structure

Each artifact entry contains:
```json
{
  "filename": "path/to/artifact.md",
  "description": "Brief description of what the artifact covers",
  "usage": "always" | "decide"
}
```

**Usage field:**
- **`always`** - Must be read before any work (e.g., project overview, core conventions)
- **`decide`** - Read when the artifact is relevant to your current task (e.g., testing conventions when writing tests, API patterns when building endpoints)

## Beads Sync

**IMPORTANT:** Do NOT use `bd sync` to sync beads to remote. It does not properly push changes, which prevents other agents from seeing each other's work.

**Always use `bin/bd-sync`** instead. This script runs `bd sync --full`, commits any changes in the beads worktree, and pushes to the `beads-sync` remote branch.

## Beads Workflow for Sandboxed Agents

When working in a sandbox (claude-sandbox), follow this sequence:

1. **Claim the task**: `bd update <issue-id> --status=in_progress`
2. **Sync immediately after claiming**: `bin/bd-sync` — so the overseer and other agents see you've started
3. **Do the work**: implement, test, commit
4. **Push code**: `git push`
5. **Close the task**: `bd close <issue-id>`
6. **Sync after closing**: `bin/bd-sync` — so the task status is visible to others
