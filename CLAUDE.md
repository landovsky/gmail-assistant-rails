# Agent Instructions

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
