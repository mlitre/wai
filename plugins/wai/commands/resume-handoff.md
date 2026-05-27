---
description: Resume work from a handoff document, read it, verify the codebase state still matches, propose a plan, then start.
inspired-by: humanlayer/.claude/commands/resume_handoff.md
---

# Resume from a handoff

You're picking up where another session (or another agent) left off. The handoff doc describes what was done, what was learned, and what's next. Your job is to read it, sanity-check that the code still matches its claims, and then resume the work.

## Invocation

The user runs `/resume-handoff <path>` where `<path>` is the handoff file.

If no path is given, respond with:

> Where's the handoff? Pass me a path, e.g. `/resume-handoff path/to/handoff.md`.

Wait. Don't guess at file locations.

## Process

### 1. Read the handoff in full

Use `Read` without `limit`/`offset`. Extract every section: tasks and statuses, recent changes, learnings, artifacts, action items, other notes.

Also read every artifact and reference the handoff mentions, plan docs, research notes, related files. Read them in the main context (don't delegate); they're load-bearing.

### 2. Verify state

The handoff is a frozen snapshot. Code moves on. Before trusting any claim:

- For each "recent change" the handoff lists, check that change is still present (`git log`, `git show`, or read the file).
- For each "learning" with a file:line reference, confirm the line still says what the handoff claims.
- Note divergences. If the codebase has moved past the handoff, surface it.

Use subagents for parallel verification when there's more than ~3 things to check. Each subagent gets one bounded check.

### 3. Present analysis

Tell the user what you found. Use this skeleton, short, specific, no fluff:

```
Handoff from <date>, by <author>.

**Tasks:**
- Task A, was <status>; now <verified | drift>.
- Task B, was <status>; now <verified | drift>.

**Recent changes:**
- <change>, <still present | rebased | missing>.

**Learnings still valid:** <yes / partial, list>.

**Recommended next:**
1. <most logical action>.
2. <second>.

**Risks/blockers found:** <list, or "none">.

Proceed with #1, or adjust?
```

Stop. Wait for the user.

### 4. Plan

Once they confirm, use `TaskCreate` to turn the action items into tasks. Prioritise by dependency order. Add any new tasks the verification surfaced.

Show the task list, confirm, then start with the first one.

## Rules

- **Never assume.** "Handoff says X exists" ≠ "X exists now." Always verify.
- **Don't skip Step 2.** A handoff older than ~a few days has almost always drifted somewhere.
- **Reference learnings throughout the work.** The handoff captured them for a reason, apply them, especially the ones marked as patterns or anti-patterns.
- **When you finish, consider writing a new handoff.** Continuity matters.

## When the handoff is stale

If verification turns up that a lot has changed since the handoff was written, major refactor, big feature added in between, etc., say so explicitly. The original plan may no longer apply. Ask whether to re-evaluate the strategy or push through with adaptations.
