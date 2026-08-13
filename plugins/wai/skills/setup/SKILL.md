---
name: setup
description: One-time per-repo setup for the wai workflow. Detects repo state, writes `.claude/wai.json` config, opt-in scaffolds `CONTEXT.md` and `docs/adr/`, writes a pointer block into `CLAUDE.local.md` and excludes wai personal files via `.git/info/exclude`. Re-run with `--update` to refresh the pointer and clear legacy blocks.
---

# Setup

Bootstrap a repo for the wai workflow. Idempotent, safe to re-run; `--update` refreshes the pointer only.

> **INVARIANT, no code here.** This skill does not modify source files. It writes config and scaffolds optional docs only. See `plugins/wai/WORKFLOW.md`.

## What it produces

- `.claude/wai.json`, per-repo config (paths, parallel cap).
- Marker-comment pointer block in `CLAUDE.local.md` at the repo root.
- wai personal-file patterns appended to `.git/info/exclude`.
- (Opt-in) `CONTEXT.md` (or user-chosen path), project domain glossary scaffold.
- (Opt-in) `docs/adr/0000-template.md`, ADR template scaffold.

## Process

### 1. Detect state

- Look for existing `.claude/wai.json`. If present → update flow (offer to re-prompt each field with current value as default).
- Look for existing `CLAUDE.local.md` at repo root.
- Look for a legacy `<!-- wai-workflow-start -->` block in `CLAUDE.md`. If present, it must be removed (see step 4).
- Look for existing `CONTEXT.md`, `docs/CONTEXT.md`, `CONTEXT-MAP.md`.
- Look for existing `docs/adr/`.

### 2. Walk the user through choices

Present detected defaults; let them override. One question at a time.

- **CONTEXT.md path**, default `docs/CONTEXT.md`. Skip with `none` if user doesn't want one.
- **ADR directory**, default `docs/adr`. Skip with `none`.
- **`parallel_cap`**, default `3`. Used by `/implement-plan` DAG walker.

That is the whole questionnaire. wai does not integrate with an issue tracker, so nothing about issues is asked or stored.

### 3. Write `.claude/wai.json` atomically

Build the JSON in memory, write to `.claude/wai.json.tmp`, then rename. Never leave a half-written file.

Shape:

```json
{
  "context_md": "docs/CONTEXT.md",
  "adr_dir": "docs/adr",
  "parallel_cap": 3
}
```

Those three fields are the entire schema. Drop fields the user opted out of (e.g., `context_md: null` if they said skip).

### 4. Write the pointer block into `CLAUDE.local.md`

Target is `CLAUDE.local.md` in the repo root, **not** `CLAUDE.md`. `CLAUDE.md` is shared with everyone who clones the repo; the wai pointer is personal.

Look for the markers:

```
<!-- wai-workflow-start -->
...
<!-- wai-workflow-end -->
```

- **Markers exist in `CLAUDE.local.md`** → replace the block in place.
- **Markers missing** → append the block at the end of `CLAUDE.local.md`.
- **File absent** → create it containing the block.

Block content:

```markdown
<!-- wai-workflow-start -->
## wai workflow

This repo uses the wai workflow.
Per-repo config lives in `.claude/wai.json`.
The canonical spine, side paths, and invariants live in the wai plugin's `WORKFLOW.md`.
<!-- wai-workflow-end -->
```

The pointer names zero commands on purpose. The old block enumerated an 11-step spine, which meant every adopting repo carried a byte-identical copy that went stale the moment a command was renamed or cut. A pointer cannot rot. See `docs/adr/0004-spine-is-a-pointer-in-claude-local-md.md`.

Atomic rename for `CLAUDE.local.md` too.

**Remove the legacy block from `CLAUDE.md`.** If `CLAUDE.md` still contains a `<!-- wai-workflow-start -->` / `<!-- wai-workflow-end -->` pair, delete the markers and everything between them, plus the blank line the block left behind. A repo carrying both the old enumerated block and the new pointer is worse off than one carrying neither, because the stale command list still reads as authoritative. Do this in both the fresh run and `--update`.

**Then ask the user to confirm the file loaded.** `CLAUDE.local.md` is verified loaded by Claude Code 2.1.231 with scope label `Local`, but it sits behind a `localSettings` capability check, so it is not guaranteed on every build or deployment. Do not assume it landed in context. Tell the user to run `/memory` (or `/context`) and check that `CLAUDE.local.md` appears with scope `Local`. If it does not, the pointer is inert and they should say so; the fallback is putting the same three lines in `CLAUDE.md` by hand.

### 5. Exclude wai personal files from git

Append the wai personal-file patterns to `.git/info/exclude`. At minimum:

```
CLAUDE.local.md
```

Be idempotent: read the file first and skip any pattern already present. Never rewrite lines you did not add.

**Why `.git/info/exclude` and not `.gitignore`.** These are personal files. Many target repos are upstream open-source repos the user sends PRs to. An untracked `CLAUDE.local.md` shows up as noise in every `git status` there, and a committed one is worse, it puts one person's local setup into a shared tree. `.gitignore` is itself tracked, so adding the pattern there is the same category of mistake. `.git/info/exclude` is local, untracked, and invisible to everyone else.

The tradeoff: `.git/info/exclude` is per-clone and does not survive a re-clone, so `/setup` has to run again on a fresh clone. It **is** shared across linked git worktrees, so one write covers every worktree of that repo.

### 6. Opt-in scaffolds

If user said yes to `CONTEXT.md` and the path doesn't exist:

- Create with a minimal scaffold (one-paragraph project summary header + Domain Terms table + Boundaries section).

If user said yes to `docs/adr/` and the directory doesn't exist:

- Create `docs/adr/0000-template.md` with the standard ADR template (Status / Context / Decision / Consequences).

### 7. Suggest next steps

End the run with:

> Setup complete. `.claude/wai.json` written. Pointer block written to `CLAUDE.local.md`, and `CLAUDE.local.md` added to `.git/info/exclude`.
>
> Confirm the pointer actually loaded: run `/memory` and check `CLAUDE.local.md` shows up with scope `Local`.
>
> Suggested next step:
>
> 1. **`create-standards-checker`** skill, if this repo audits code against a written spec (protocol specs like OCPP / ISO 15118 / HTTP / OAuth, internal RFCs, design docs, regulatory documents, ...), generate a domain-specialized `<domain>-standards-compliance-checker` agent now. The skill walks you through the registry seed + writes `.claude/agents/<domain>-standards-compliance-checker.md` + `.claude/compliance-specs.json`.

Detection hint for that suggestion: look for `specs/`, `docs/rfc/`, `contracts/`, or `*.pdf` files in the repo. If present, lead with it; if not, still offer it but note the user may not need it. Do **not** invoke `create-standards-checker` inline, the skill has its own interactive prompts and the user owns the run decision.

## `--update` mode

```
/setup --update
```

Skips all prompts. Does three things:

1. Rewrites the pointer block in `CLAUDE.local.md`.
2. Removes any legacy marker block left in `CLAUDE.md`.
3. Tops up `.git/info/exclude` with any missing wai pattern.

Does not touch `.claude/wai.json`. Use after the pointer format changes, or on any repo still carrying the old enumerated spine.

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
# existing config
test -f .claude/wai.json && echo update || echo fresh

# legacy block still in shared memory
grep -q 'wai-workflow-start' CLAUDE.md 2>/dev/null && echo legacy || echo clean

# pattern already excluded
grep -qxF 'CLAUDE.local.md' .git/info/exclude 2>/dev/null && echo present || echo missing
```

`.git/info/exclude` may not exist in a fresh clone. Create it (and `.git/info/`) if needed.

## Hard rules

- **Idempotent.** Running twice with the same answers leaves the same on-disk state.
- **Atomic writes.** Always temp-file rename.
- **Markers exact.** `<!-- wai-workflow-start -->` / `<!-- wai-workflow-end -->`, downstream tooling greps for these.
- **Pointer names no commands.** If you find yourself listing steps in the block, stop. That is the failure mode this design exists to prevent.
- **Never write personal patterns to `.gitignore`.** `.git/info/exclude` only.
- **Don't overwrite existing `CONTEXT.md` / ADR template content.** Only create if absent.
- **No code edits.** Config files and marker-block writes only.
