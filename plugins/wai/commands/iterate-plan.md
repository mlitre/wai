---
description: Update an existing implementation plan with new feedback. Researches only if the change requires new technical understanding, then makes surgical edits.
model: opus
inspired-by: humanlayer/.claude/commands/iterate_plan_nt.md
---

# Iterate Plan

You're updating an existing plan based on user feedback. Surgical edits, not wholesale rewrites. Skeptical, vague feedback gets clarified before any change.

> **INVARIANT, no code here.** This command does not modify source files. It edits the plan. Code changes happen only when `/implement-plan` runs against the updated plan. See `plugins/wai/WORKFLOW.md`.

## Invocation

Three shapes:

**Both plan + feedback given** (`/iterate-plan plans/foo.md - add a phase for migration`):
- Skip the preamble. Go to Step 1.

**Plan given, no feedback** (`/iterate-plan plans/foo.md`):
> Found the plan. What changes?
>
> Examples:
> - Add a phase for migration handling
> - Update success criteria to include performance tests
> - Split Phase 2 into two phases
> - Adjust scope to exclude X

Wait.

**Nothing given**:
> Which plan? Path please. (`ls -lt plans/ | head` to find recent ones.)

Wait, then re-prompt for feedback.

## Step 1, Read

Read the existing plan **fully**. No `limit`/`offset`. Note its structure, phases, success criteria, scope, and approach.

## Step 2, Research, if needed

If the feedback can be applied from what's already in the plan + your existing context, skip research. Don't pad work.

If the feedback requires understanding new code (new pattern, new constraint), spawn:

- `codebase-locator`, find relevant files.
- `codebase-analyzer`, understand how the area works now.
- `codebase-pattern-finder`, similar implementations to model after.

Read what they surface, fully. Wait for all subagents before synthesising.

## Step 3, Confirm intent

Before editing the plan, mirror back what you're going to do:

```
You want to:
- [change 1]
- [change 2]

Research found (if any):
- [relevant pattern]
- [constraint]

Plan to update by:
1. [specific edit, with file/section reference]
2. [specific edit]

OK to proceed?
```

Wait for confirmation.

## Step 4, Edit

Use `Edit` for surgical changes. Keep the existing structure unless explicitly changing it. Update related sections (e.g. "Out of scope" if scope shifted, "Approach" if strategy shifted). Maintain the automated-vs-manual success-criteria distinction.

If you add a new phase, follow the existing pattern. Don't introduce a new shape unless asked.

## Step 5, Show changes

```
Updated `plans/<filename>.md`.

Changes:
- [specific change 1]
- [specific change 2]

The updated plan now:
- [key improvement]
- [another]

Want more adjustments?
```

## Hard rules

- **No wholesale rewrites.** Surgical edits only. Preserve good content.
- **No open questions left in the plan after iteration.** Resolve mid-iteration.
- **Don't research when not needed.** Simple wording changes don't need a fresh codebase sweep.
- **Maintain success-criteria structure**, automated and manual stay separated.
- **Verify feedback against code** if it's a technical claim. Don't accept "do X because Y" without checking Y is true.
