---
description: Execute a wai DAG plan task-by-task. Walks the `T<n>` / `depends_on:` graph, dispatches `wai-implementer` → `wai-spec-reviewer` → `code-reviewer` per task, parallel up to `.claude/wai.json`'s `parallel_cap`. Retry-once on reviewer rejection; quarantine on second failure. End-of-walk report lists green vs blocked tasks.
inspired-by: humanlayer/.claude/commands/implement_plan.md
---

# Implement Plan

Subagent-driven by default. Plan is the spec. Task is the unit of work. Reviewer agents gate the merge of each task.

## Inputs

```
/implement-plan plans/<file>.md
/implement-plan plans/<file>.md --parallel-cap 1   # override config
/implement-plan plans/<file>.md --start T7         # resume from a task
/implement-plan plans/<file>.md --only T7,T9       # run only these (+ their reachable subtrees if dependencies are unmet)
```

If no plan path is given, ask. Don't guess.

## Setup

1. **Read the plan completely.** No `limit`/`offset`.
2. **Read `.claude/wai.json`.** Extract `parallel_cap` (default 3 if missing). Override with `--parallel-cap` flag.
3. **Parse the DAG.** Parse contract defined in `/create-plan`:
   - `### T<n>, <title>` heading.
   - `depends_on: [T<n>, T<m>]` line.
   - Checkbox steps.
4. **Validate the DAG.** Topological sort. If a cycle exists, abort with the cycle named.
5. **Check existing state.** For each task, if all its checkbox steps are `[x]`, mark `complete` upfront, don't re-run. Trust prior work.
6. **Read scene-setting files.** Anything the plan references in its goal / approach / per-task hints. Fully. You'll paste relevant slices into implementer prompts.

If you find the plan still uses the old phased format (no `### T<n>` headings, only `## Phase N`), abort:

> Plan uses phased format. The DAG walker needs the new format from `/create-plan`. Either:
>   - re-run `/create-plan` on the source spec to regenerate, or
>   - use the linear executor: read tasks manually + dispatch implementer per task.

## DAG walk

### Ready set

A task is **ready** when:

- It is not yet `complete`.
- All entries in its `depends_on:` are `complete`.
- It is not `blocked` from a prior quarantine.

### Loop

```
while ready_set is non-empty:
  pick up to parallel_cap ready tasks
  dispatch implementer for each (single response, multiple Agent calls)
  wait for all to return
  for each task that returned:
    run the per-task review chain (see below)
    update task state: complete | blocked
    if blocked: propagate `blocked` to DAG descendants
  recompute ready_set
```

End condition: ready_set empty AND no in-flight dispatches.

### Per-task review chain

```
implementer returns DONE → spec-reviewer
  spec-reviewer pass → quality-reviewer
    quality-reviewer pass → mark task complete, tick checkboxes
    quality-reviewer fail → retry implementer once with reviewer comments appended
      retry implementer DONE → spec-reviewer (full re-review) → quality-reviewer
        quality-reviewer pass → mark complete
        quality-reviewer fail → quarantine
      retry implementer not-DONE → quarantine
  spec-reviewer fail → retry implementer once with spec-reviewer comments appended
    retry implementer DONE → spec-reviewer (re-review)
      spec-reviewer pass → quality-reviewer (fresh)
        ... (same as above)
      spec-reviewer fail → quarantine
    retry implementer not-DONE → quarantine

implementer returns DONE_WITH_CONCERNS → same chain, but surface concerns in the end-of-walk report.
implementer returns NEEDS_CONTEXT → augment prompt with the requested context, re-dispatch once.
                                    If still NEEDS_CONTEXT → quarantine.
implementer returns BLOCKED → quarantine.
```

**Retry-once.** Each implementer dispatch gets at most one retry per failure mode. Second failure = quarantine.

**Quarantine.** Mark the task `blocked`. Mark all DAG descendants `blocked` too (their dependency is dead). Continue with the rest of the ready set, don't halt the whole walk for one stuck task.

## Dispatching an implementer

Agent name: `wai-implementer`. Local override: drop `.claude/agents/wai-implementer.md` in the project.

Prompt shape (see `wai-implementer.md` agent definition for the input contract):

```
Task ID: T<n>
Task title: <title>
depends_on: [T<m>, T<p>]
Issue: #N (if mirrored)

Checkbox steps (paste verbatim from the plan):
- [ ] step 1
- [ ] step 2
...

Scene-setting context:
<relevant excerpts from the plan's goal / approach>
<relevant excerpts from files the task touches, paste, don't make the subagent read the plan>
<project CLAUDE.md highlights>

Working directory: <repo or worktree path>

Augmentation (retry only):
<previous attempt's reviewer comments + failure trace, inline>
```

Follow the `using-subagents` primer's prompt-craft rules: focused, self-contained, specific output. Never make the implementer read the plan file, paste the task's text.

## Dispatching reviewers

After an implementer reports `DONE` or `DONE_WITH_CONCERNS`:

1. Capture the commit range the implementer landed (`<base-sha>..<head-sha>`).
2. Dispatch `wai-spec-reviewer` with the task spec + implementer's report + commit range.
3. On `pass`, dispatch `code-reviewer` with freeform context: commit range, project `CLAUDE.md` path, implementer report, spec-reviewer verdict. Reviewer self-dispatches narrow specialists per heuristic; orchestrator does not enumerate them.
4. On any `fail`, kick into the retry chain above.

The two reviewers run **sequentially** (spec first; quality only after spec passes). Don't parallelize them, quality findings on broken-spec code are wasted work.

## End-of-walk report

```markdown
# /implement-plan, `plans/<file>.md`

## Summary
- Tasks complete: <N> / <total>
- Tasks blocked:  <M>

## Green
- ✓ T1, <title>
- ✓ T2, <title>
- ...

## Blocked
- ✗ T7, <title>
  - Failure mode: <implementer NEEDS_CONTEXT / spec-reviewer fail / quality-reviewer fail / implementer BLOCKED>
  - Last implementer diff: <commit sha or "none">
  - Last reviewer verdict: <quote the verdict reason>
  - Suggested next step: `/iterate-plan plans/<file>.md` to refine T7, then re-run.

## DAG descendants blocked by quarantine
- T9 (← T7)
- T12 (← T9)
- ...

## Concerns to review
- T3, DONE_WITH_CONCERNS: <quote concern>
- T5, DONE_WITH_CONCERNS: <quote concern>
```

For each blocked task, recommend `/iterate-plan` on the plan with that task's failure context.

## Continuous execution

Don't pause between tasks for "should I continue?" prompts. Execute until:

- The ready set is empty.
- A quarantine cascade has killed everything reachable.
- The user interrupts.

Progress chatter wastes the user's time. The end-of-walk report is the deliverable.

## Override

Agent names are hardcoded: `wai-implementer`, `wai-spec-reviewer`, `code-reviewer`. Project-local override: drop same-named files under `.claude/agents/`, Claude Code's resolution prefers local over plugin.

## Bootstrap

The first time this command runs on a plan that was generated *before* the DAG-walker existed, that plan was likely executed manually. The command treats already-`[x]`'d tasks as complete and only re-runs missing ones, so partial completions resume cleanly.

## See

- `wai-implementer.md`, agent definition.
- `wai-spec-reviewer.md`, agent definition.
- `code-reviewer.md`, agent definition (handles quality review + specialist dispatch).
- `using-subagents` skill, prompt-craft primer.
- `plugins/wai/WORKFLOW.md`, workflow context.

## Workflow position

```
/create-plan → /implement-plan → /ds → /describe-pr → ...
```

For a flat list of independent findings rather than a DAG, use `/fix-findings`, same machine, different parser.
