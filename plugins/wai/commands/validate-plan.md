---
description: Validate that an implementation matches its plan. Runs the success criteria, diffs the actual changes against the plan, surfaces deviations and missing pieces.
inspired-by: humanlayer/.claude/commands/validate_plan.md
---

# Validate Plan

You're checking whether the implementation actually delivers what the plan promised. Honest, thorough, constructive, but not optimistic about uncertainty.

## Setup

When invoked:

1. **Identify your context.**
   - Were you part of the implementation conversation? Review what was done.
   - Starting fresh? You'll discover everything from git + code.

2. **Locate the plan.**
   - If a path is given, use it.
   - Otherwise, look at recent commits for plan references; ask the user if you still can't find it.

3. **Gather evidence.**
   ```bash
   git log --oneline -n 20
   git diff <base>..HEAD   # whatever range covers the implementation
   ```
   Run `make check test` (or the project's equivalent) once at the start to get a baseline.

## Process

### 1. Map the plan to expected changes

Read the plan fully. Plans are DAGs, `### T<n>, <title>` task headings, `depends_on: [...]` lines, checkbox steps. Build a list of:

- Tasks that should have landed (every `T<n>` with all its checkboxes ticked).
- Files that should have changed (named in each task's checkbox steps).
- Functions / modules added or modified.
- Tests added.
- Each success criterion (automated and manual) from the plan's top-level "Success criteria" section.

If the plan still uses the old phased format (`## Phase 1`, `## Phase 2`), call it out, the plan is stale relative to `/create-plan`'s DAG output. You can still validate, but flag the format mismatch in the report.

### 2. Verify in parallel

Spawn subagents for independent verification areas. Each gets a narrow scope:

- One for database / schema changes ("did the migration land? does the schema match?").
- One for code changes ("did these files change as specified? line-by-line plan-vs-actual").
- One for test coverage ("are the new tests present? do they run? do they pass?").

Wait for all. Then synthesise.

### 3. Run the automated criteria

For each `- [x]` (or `- [ ]`) under "Automated Verification":

- Run the command exactly as written.
- Note pass/fail with the actual output if it failed.

Don't trust the existing checkbox, re-run it. The plan may have been ticked optimistically.

### 4. Surface deviations

For each phase:

- Does the code match what the plan said?
- Are variable names / file locations / API shapes the same? (Minor differences are fine; flag them but don't make a fuss.)
- Anything **added** beyond the plan? Flag it (might be improvement, might be scope creep).
- Anything **missing**? Flag it loudly.

### 5. Manual criteria

You can't run them. List them clearly so the user knows what's left to test by hand.

## Report

Output one report:

```markdown
## Validation: <plan name>

### Task status
- ✓ T1: <name>, fully implemented
- ✓ T2: <name>, fully implemented
- ⚠️ T3: <name>, partially implemented (see issues)
- ✗ T4: <name>, blocked / not landed

### Automated checks
- ✓ Build: `make build`
- ✓ Tests: `make test`
- ✗ Lint: `make lint`, 3 warnings (see output below)

### Matches plan
- Migration adds `<table>` as specified
- API endpoints implement specified methods
- Error handling follows plan

### Deviations
- Variable renames in `<file:line>`, cosmetic
- Extra validation in `<file:line>`, looks like an improvement
- **Missing**: <thing the plan required that isn't there>

### Risks / open issues
- <e.g.> Missing index on foreign key could hurt query perf at scale
- <e.g.> No rollback path in the migration

### Manual verification still needed
1. <UI/behaviour item from plan>
2. <integration item>

### Recommendations
- Address lint warnings before merge
- Consider adding integration test for <scenario>
```

## Rules

- **Run every automated check.** Don't skip "because it probably passes."
- **Don't grade on a curve.** If a phase is 80% done, it's partial, not done.
- **Be honest about shortcuts.** If you were part of the implementation and skipped something, say so.
- **Constructive, not punitive.** Surface gaps with the fix, not just the gripe.

## Workflow position

The usual order:

1. `/implement-plan`, build it (DAG walk).
2. `commit` skill, atomic commits (or `wai-implementer` commits per-task).
3. `/validate-plan`, this command.
4. `/describe-pr`, write the description.

Validation works better after commits are made, git history is a clean source of truth for what was actually delivered.

## Scope vs `verification-before-completion`

This command is **plan-specific**: it runs the success criteria listed *in the plan file* and checks the plan's task list against the diff. Use `verification-before-completion` for the general "evidence before claims" discipline that applies to any completion claim, not just plan execution.
