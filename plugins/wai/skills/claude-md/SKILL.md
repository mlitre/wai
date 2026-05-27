---
name: claude-md
description: Manage CLAUDE.md files, two modes. **Audit mode**: scan every CLAUDE.md across the codebase, score against a 6-criterion rubric, print quality report, propose targeted updates. **Revise mode**: reflect on the current session, capture missing context, add concise lines to the right CLAUDE.md / `.claude.local.md`. Use when user says "audit CLAUDE.md", "check CLAUDE.md files", "improve CLAUDE.md", "fix CLAUDE.md", "CLAUDE.md maintenance", "project memory optimization" (audit), or "revise CLAUDE.md", "update CLAUDE.md with what we learned", "add this session's learnings to CLAUDE.md", "/revise-claude-md" (revise).
tools: Read, Glob, Grep, Bash, Edit
inspired-by: |
  anthropic/claude-md-management/skills/claude-md-improver (audit mode)
  anthropic/claude-md-management/commands/revise-claude-md (revise mode)
---

# CLAUDE.md

Manage CLAUDE.md files so Claude Code gets the best possible project context. **This skill writes to CLAUDE.md files**, always after showing diffs and getting approval.

## Mode selection

- **Audit mode**, sweep the whole repo. Triggered by "audit", "check all", "improve", "fix CLAUDE.md", "maintenance". Output: per-file quality report → targeted updates.
- **Revise mode**, capture this session's learnings. Triggered by "revise", "update with what we learned", "/revise-claude-md". Output: short list of additions → diffs → apply.

If the request is ambiguous, ask once which mode the user wants.

---

# Mode A, Audit

Audit, evaluate, improve every CLAUDE.md in the repo.

## Workflow

### Phase 1, discovery

```bash
find . -name "CLAUDE.md" -o -name ".claude.md" -o -name ".claude.local.md" 2>/dev/null | head -50
```

File types and their roles:

| Location | Purpose |
|----------|---------|
| `./CLAUDE.md` | Primary project context, checked into git, shared with team |
| `./.claude.local.md` | Personal / local settings, gitignored, not shared |
| `~/.claude/CLAUDE.md` | User-wide defaults across every project |
| `./packages/*/CLAUDE.md` | Module-level context in monorepos |
| nested `CLAUDE.md` | Feature- or domain-specific context |

Claude auto-discovers CLAUDE.md files in parent directories, monorepo setups work automatically.

### Phase 2, quality assessment

For each file, score against this rubric (see [references/quality-criteria.md](references/quality-criteria.md) for full breakdown):

| Criterion | Weight | Check |
|-----------|--------|-------|
| Commands / workflows documented | High (20) | Build / test / deploy / dev commands present? |
| Architecture clarity | High (20) | Can Claude understand the codebase structure? |
| Non-obvious patterns | Medium (15) | Are gotchas and quirks documented? |
| Conciseness | Medium (15) | No verbose explanations or obvious info? |
| Currency | High (15) | Reflects current codebase state? |
| Actionability | High (15) | Are instructions executable, not vague? |

**Grades:**

- **A (90-100)**, current and actionable.
- **B (70-89)**, good coverage, minor gaps.
- **C (50-69)**, basic info, missing key sections.
- **D (30-49)**, sparse or outdated.
- **F (0-29)**, missing or severely outdated.

### Phase 3, output the quality report

**Always print the report before making any updates.**

```
## CLAUDE.md Quality Report

### Summary
- Files found: X
- Average score: X/100
- Files needing update: X

### File-by-file

#### 1. ./CLAUDE.md (project root)
**Score: XX/100 (Grade: X)**

| Criterion | Score | Notes |
|-----------|-------|-------|
| Commands / workflows | X/20 | ... |
| Architecture clarity | X/20 | ... |
| Non-obvious patterns | X/15 | ... |
| Conciseness | X/15 | ... |
| Currency | X/15 | ... |
| Actionability | X/15 | ... |

**Issues:**
- [specific problems]

**Recommended additions:**
- [what should be added]

#### 2. ./packages/api/CLAUDE.md (package-specific)
...
```

### Phase 4, targeted updates

After the report, ask the user for confirmation. Update guidelines (see [references/update-guidelines.md](references/update-guidelines.md) for full version):

**Propose only:**

- Commands or workflows discovered during analysis.
- Gotchas or non-obvious patterns found in the code.
- Package relationships that weren't clear.
- Testing approaches that work.
- Configuration quirks.

**Skip:**

- Restating what's obvious from the code.
- Generic best practices already covered everywhere.
- One-off fixes unlikely to recur.
- Verbose explanations when a one-liner suffices.

**Show diffs.** For each change:

```markdown
### Update: ./CLAUDE.md

**Why:** Build command was missing, confusion about how to run the project.

```diff
+ ## Quick Start
+
+ ```bash
+ npm install
+ npm run dev  # Start dev server on port 3000
+ ```
```
```

### Phase 5, apply

After approval, Edit each file. Preserve existing structure.

## Templates

See [references/templates.md](references/templates.md) for CLAUDE.md templates by project type (root minimal, root comprehensive, package, monorepo).

## Common issues to flag

1. **Stale commands**, build commands that no longer work.
2. **Missing dependencies**, required tools not mentioned.
3. **Outdated architecture**, file structure that's changed.
4. **Missing environment setup**, required env vars or config.
5. **Broken test commands**, test scripts that have changed.
6. **Undocumented gotchas**, non-obvious patterns not captured.

## Tips to share with the user

- **`#` shortcut**, during a session, press `#` to have Claude auto-incorporate learnings into CLAUDE.md.
- **Keep it concise**, CLAUDE.md should be human-readable. Dense beats verbose.
- **Actionable commands**, every documented command should be copy-paste ready.
- **Use `.claude.local.md`** for personal preferences not shared with the team (add to `.gitignore`).
- **Global defaults** belong in `~/.claude/CLAUDE.md`.

## What makes a great CLAUDE.md

- Concise and human-readable.
- Actionable, copy-paste-ready commands.
- Project-specific patterns, not generic advice.
- Non-obvious gotchas and warnings.

**Sections to consider** (use only what's relevant):

- Commands (build, test, dev, lint).
- Architecture (directory structure).
- Key files (entry points, config).
- Code style (project conventions).
- Environment (required vars, setup).
- Testing (commands, patterns).
- Gotchas (quirks, common mistakes).
- Workflow (when to do what).

---

# Mode B, Revise

Reflect on the current session, then add what would help future Claude sessions be more effective in this codebase. Scoped to *this session's* learnings, not a full repo sweep (use Mode A for that).

## Step 1, reflect

What context was missing that would have helped you work more effectively in this session?

- Bash commands used or discovered.
- Code-style patterns followed.
- Testing approaches that worked.
- Environment / configuration quirks.
- Warnings or gotchas encountered.

## Step 2, find existing CLAUDE.md files

```bash
find . -name "CLAUDE.md" -o -name ".claude.local.md" 2>/dev/null | head -20
```

Decide where each addition belongs:

- `CLAUDE.md`, team-shared, checked into git.
- `.claude.local.md`, personal/local, gitignored.

## Step 3, draft additions

Keep them concise. One line per concept. CLAUDE.md is part of the prompt, so brevity matters.

Format: `` `<command or pattern>`, `<brief description>` ``.

Avoid:

- Verbose explanations.
- Obvious information.
- One-off fixes unlikely to recur.

## Step 4, show proposed changes

For each addition:

```
### Update: ./CLAUDE.md

**Why:** [one-line reason]

```diff
+ [the addition, keep it brief]
```
```

## Step 5, apply with approval

Ask before editing. Only modify files the user approves.
