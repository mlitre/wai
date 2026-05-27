---
name: setup
description: One-time per-repo setup for the wai workflow. Detects repo state, writes `.claude/wai.json` config, opt-in scaffolds `CONTEXT.md` and `docs/adr/`, injects the WORKFLOW spine into the project `CLAUDE.md` between marker comments. Re-run with `--update` to re-inject only.
---

# Setup

Bootstrap a repo for the wai workflow. Idempotent, safe to re-run; `--update` re-injects only.

> **INVARIANT, no code here.** This skill does not modify source files. It writes config and scaffolds optional docs only. See `plugins/wai/WORKFLOW.md`.

## What it produces

- `.claude/wai.json`, per-repo config (tracker, labels, paths, parallel cap).
- Marker-comment block in project `CLAUDE.md` containing the WORKFLOW spine.
- (Opt-in) `CONTEXT.md` (or user-chosen path), project domain glossary scaffold.
- (Opt-in) `docs/adr/0000-template.md`, ADR template scaffold.

## Process

### 1. Detect state

- Look for existing `.claude/wai.json`. If present → update flow (offer to re-prompt each field with current value as default).
- Look for existing `CLAUDE.md` at repo root.
- Look for existing `CONTEXT.md`, `docs/CONTEXT.md`, `CONTEXT-MAP.md`.
- Look for existing `docs/adr/`.
- Detect tracker by checking for `gh` auth + `origin` remote pointing at GitHub.

### 2. Walk the user through choices

Present detected defaults; let them override. One question at a time.

- **Tracker**, `github` (detected default) or `none` (local-only).
- **Tracker repo**, auto-derived from `origin`; let user override.
- **Label vocabulary**, `prd` label, `task` label. Defaults `type:prd` / `type:task`.
- **CONTEXT.md path**, default `docs/CONTEXT.md`. Skip with `none` if user doesn't want one.
- **ADR directory**, default `docs/adr`. Skip with `none`.
- **`parallel_cap`**, default `3`. Used by `/implement-plan` DAG walker.

### 3. Write `.claude/wai.json` atomically

Build the JSON in memory, write to `.claude/wai.json.tmp`, then rename. Never leave a half-written file.

Shape:

```json
{
  "tracker": "github",
  "tracker_repo": "owner/repo",
  "labels": {
    "prd": "type:prd",
    "task": "type:task"
  },
  "context_md": "docs/CONTEXT.md",
  "adr_dir": "docs/adr",
  "parallel_cap": 3
}
```

Drop fields the user opted out of (e.g., `context_md: null` if they said skip).

### 4. Inject WORKFLOW spine into `CLAUDE.md`

Look for the markers:

```
<!-- wai-workflow-start -->
...
<!-- wai-workflow-end -->
```

- **Markers exist** → replace the block in place.
- **Markers missing** → append the block at the end of `CLAUDE.md` (or create `CLAUDE.md` if absent).

Block content:

```markdown
<!-- wai-workflow-start -->
## wai workflow

This project follows the wai workflow:

`/setup → /research-codebase → to-spec → /create-plan → to-issues → /implement-plan → /validate-plan → /review-pr → /ds → /describe-pr → manual push → cleanup-worktrees`

See `plugins/wai/WORKFLOW.md` for side paths, invariants, and per-step detail.

Pre-implementation steps (`/research-codebase`, `to-spec`, `/create-plan`, `/iterate-plan`, `/diagnose`) do not modify source files. Code lands only via `/implement-plan` (or `cavecrew-builder` for surgical 1-2 file edits).
<!-- wai-workflow-end -->
```

Atomic rename for `CLAUDE.md` too.

### 5. Opt-in scaffolds

If user said yes to `CONTEXT.md` and the path doesn't exist:

- Create with a minimal scaffold (one-paragraph project summary header + Domain Terms table + Boundaries section).

If user said yes to `docs/adr/` and the directory doesn't exist:

- Create `docs/adr/0000-template.md` with the standard ADR template (Status / Context / Decision / Consequences).

### 6. Suggest next steps

End the run with both suggestions:

> Setup complete. `.claude/wai.json` written. WORKFLOW spine injected into `CLAUDE.md`.
>
> Suggested next steps:
>
> 1. **`claude-automation-recommender`** skill, surfaces MCP servers, hooks, and other automations specific to this repo's stack.
> 2. **`create-standards-checker`** skill, if this repo audits code against a written spec (protocol specs like OCPP / ISO 15118 / HTTP / OAuth, internal RFCs, design docs, regulatory documents, ...), generate a domain-specialized `<domain>-standards-compliance-checker` agent now. The skill walks you through the registry seed + writes `.claude/agents/<domain>-standards-compliance-checker.md` + `.claude/compliance-specs.json`.

Detection hint for the second suggestion: look for `specs/`, `docs/rfc/`, `contracts/`, or `*.pdf` files in the repo. If present, lead with it; if not, still offer it but note the user may not need it. Do **not** invoke `create-standards-checker` inline, the skill has its own interactive prompts and the user owns the run decision.

## `--update` mode

```
/setup --update
```

Skips all prompts. Re-injects only the WORKFLOW block in `CLAUDE.md`. Does not touch `.claude/wai.json`. Use after editing `WORKFLOW.md`.

## Atomic rename pattern

For any config write:

```bash
# pseudocode, adapt to actual write
cat > "$PATH.tmp" <<EOF
...content...
EOF
mv "$PATH.tmp" "$PATH"
```

Half-written config breaks every downstream skill that reads it.

## Detection helpers

```bash
# tracker
gh auth status >/dev/null 2>&1 && echo github || echo none

# tracker repo
git remote get-url origin 2>/dev/null | sed -E 's#.*github\.com[/:]##; s/\.git$//'

# existing config
test -f .claude/wai.json && echo update || echo fresh
```

## Hard rules

- **Idempotent.** Running twice with the same answers leaves the same on-disk state.
- **Atomic writes.** Always temp-file rename.
- **Markers exact.** `<!-- wai-workflow-start -->` / `<!-- wai-workflow-end -->`, downstream tooling greps for these.
- **Don't overwrite existing `CONTEXT.md` / ADR template content.** Only create if absent.
- **No code edits.** Config files and marker-block injection only.
