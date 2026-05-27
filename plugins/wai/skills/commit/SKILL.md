---
name: commit
description: Commit the session's changes, survey, group, write tight Conventional Commits messages, then execute. Interactive by default (shows plan, waits for confirmation); non-interactive when running in CI / autonomous / agent-launched contexts. Always-on Conventional Commits style (`<type>(<scope>): <summary>`, ≤50 char subject, body only when "why" isn't obvious, no AI attribution). Use when the user says "commit", "commit these changes", "save my work", "wrap this up", "make a commit", "write a commit", "commit message", "generate commit", or any variation asking to land the current diff or produce a commit message. Pass `--message-only` (or say "just the message") to output the formatted message in a code block without staging or committing.
inspired-by: humanlayer/.claude/commands/commit.md + humanlayer/.claude/commands/ci_commit.md + JuliusBrussee/caveman/skills/caveman-commit (MIT, Julius Brussee)
---

# Commit

Commit the work from this session. Workflow + tight Conventional Commits message format in one skill.

Two modes:

- **Interactive**, show a plan, wait for the user to confirm, then commit.
- **Non-interactive**, group, message, and commit without asking. No human in the loop.

Plus one flag:

- **`--message-only`**, draft the formatted message(s), output as code blocks, **don't** stage, commit, or amend. For when the user has already staged manually or just wants preview text.

## Mode selection

Decide the mode in this order:

1. **Explicit arg wins.** When invoked with `args` (or the user types `/commit --ci` style):
   - `--ci` or `--yes` → non-interactive.
   - `--interactive` → interactive.
   - `--message-only` → message-only (overrides the above for execution; mode selection only matters if the user later asks to actually commit).
2. **Auto-detect.** If `$CI` is set, or there's no TTY (autonomous Claude run, scheduled job, agent-launched session), → non-interactive. Otherwise → interactive.

If unsure whether you're in a non-interactive context and no flag was passed, default to interactive. Surprise commits are worse than asking.

## Process

### 1. Survey

- `git status`, what's modified/added/deleted.
- `git diff`, what actually changed.
- `git diff --staged`, anything already staged.
- Decide: one commit, or split into logical groups?

### 2. Plan

- Group files by intent. Refactor commits separate from feature commits. Don't mix unrelated changes.
- Draft messages following the **Message format** section below.

### 3. Confirm (interactive mode only)

Show the user the plan before touching anything:

> I'll create N commit(s):
>
> 1. `<message>`, files: `...`
> 2. `<message>`, files: `...`
>
> Proceed?

Wait for explicit confirmation.

### 4. Execute

- `git add <specific files>`, never `git add -A` or `git add .`. Those scoop up uncommitted scratch work.
- `git commit -m "<message>"` per planned commit. Use a HEREDOC if the message has a body so newlines survive.
- After all commits land, show the result: `git log --oneline -n <N>`.

In non-interactive mode, do steps 1, 2, and 4 back-to-back without pausing. Report the result at the end.

In `--message-only` mode, do step 1, then output each planned message as a fenced code block. No `git add`, no `git commit`, no `git log`.

## Message format

Always Conventional Commits. No exceptions.

### Subject line

- `<type>(<scope>): <imperative summary>`, `<scope>` optional.
- Types: `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `chore`, `build`, `ci`, `style`, `revert`.
- Imperative mood: "add", "fix", "remove", not "added", "adds", "adding".
- ≤50 chars when possible, hard cap 72.
- No trailing period.
- Match project convention for capitalization after the colon.

### Body (only if needed)

- Skip entirely when subject is self-explanatory.
- Add body only for: non-obvious *why*, breaking changes, migration notes, linked issues.
- Wrap at 72 chars.
- Bullets `-` not `*`.
- Reference issues/PRs at end: `Closes #42`, `Refs #17`.

### Banned phrases, never write

- "This commit does X", "I", "we", "now", "currently", the diff says what.
- "As requested by...", use a `Co-authored-by:` trailer instead.
- `Co-Authored-By: Claude` / "Generated with Claude Code" / any AI attribution. Commits are authored by the user.
- Emoji (unless the project convention explicitly requires it).
- Restating the file name when scope already says it.

### Always-include-body rule

Always include a body for: **breaking changes, security fixes, data migrations, anything reverting a prior commit.** Never compress these into subject-only, future debuggers need the context.

### Examples

New endpoint with body explaining the why:

```
feat(api): add GET /users/:id/profile

Mobile client needs profile data without the full user payload
to reduce LTE bandwidth on cold-launch screens.

Closes #128
```

Breaking API change:

```
feat(api)!: rename /v1/orders to /v1/checkout

BREAKING CHANGE: clients on /v1/orders must migrate to /v1/checkout
before 2026-06-01. Old route returns 410 after that date.
```

## Exclusions, never commit

- Scratch files / test scripts you created and forgot to clean up.
- Build artifacts, lock files (unless intentional), `.env`, secrets.
- Directories that look like local workspace state (`.cache/`, `dist/`, `node_modules/`, etc.) unless the project explicitly tracks them.
- Generated code that wasn't part of the task.

If something looks like it might be scratch, leave it unstaged. In non-interactive mode, report any skipped files at the end so the user can review.

## Hard rules

- **No Claude attribution.** No `Co-Authored-By: Claude`. No "Generated with Claude" trailer. Commits are authored by the user.
- **No `-A` / `.` adds.** Specific files only. Prevents committing unstaged scratch, env files, build artifacts.
- **No commits before confirmation in interactive mode.** Always show the plan first.
- **Don't stop to ask in non-interactive mode.** If you genuinely can't decide whether to commit something, leave it unstaged and report it at the end.
- **Conventional Commits format is non-negotiable.** Match project capitalization, but the `<type>(<scope>): <summary>` shape is fixed.

## Boundaries

When `--message-only` is set: output the formatted message(s) in fenced code blocks ready to paste. Do **not** run `git add`, `git commit`, or `git commit --amend`. Do not modify the working tree.

Otherwise: full survey → plan → execute flow per the mode-selection rules above.
