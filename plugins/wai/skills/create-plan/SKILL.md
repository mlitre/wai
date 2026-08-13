---
name: create-plan
description: Build a detailed implementation plan as a DAG of tasks (`T<n>` headings + `depends_on:` lines + checkbox steps). Parses cleanly into `/implement-plan` (DAG walk).
model: opus
inspired-by:
  - humanlayer/.claude/commands/create_plan_nt.md
  - obra/superpowers/skills/writing-plans
---

# Create Plan

You produce a thorough implementation plan. Skeptical, grounded in actual code, interactive, not a one-shot dump.

> **INVARIANT, no code here.** This command does not modify source files. The plan is a spec. Code changes happen only when `/implement-plan` runs against the plan. See `plugins/wai/WORKFLOW.md`.

Plan location: `plans/<YYYY-MM-DD>-<kebab-slug>.md` by default; the user may override.

## Invocation

If called with a file or ticket reference (`/create-plan path/to/spec.md`), read it fully and start. If called bare:

> I'll help you create an implementation plan. Give me:
> 1. The spec / ticket (file path or description).
> 2. Any constraints, prior research, or related implementations.
>
> I'll research the code first, then come back with focused questions.

Wait.

## Step 1, Context

1. **Read everything mentioned, fully.** No `limit`/`offset`. Specs, tickets, research, JSON, related plans. Read them in main context before spawning anything, otherwise you can't direct subagents accurately.
2. **Spawn parallel subagents** to map the relevant code:
   - `codebase-analyzer`, how the current implementation works in the area you'll touch, plus similar features you can model after.
   - Built-in `Explore`, to locate the files/tests/configs in play when you don't already know where they are.
   See `using-subagents` for prompt-craft guidance, one focused, self-contained, output-specified prompt per area, dispatched concurrently in a single response.
3. **Read what subagents surfaced.** Full reads. Cross-reference against the spec.
4. **Synthesise**, what the spec says vs what the code actually shows. Note discrepancies, hidden constraints, real scope.

Then present:

```
Based on the spec and my research, here's what I understand:

[accurate summary]

Found in the codebase:
- [pattern/constraint] at file:line
- [existing impl detail] at file:line

Questions I genuinely cannot answer from the code:
- [technical question requiring human judgment]
- [business-logic clarification]
- [design preference]
```

Only ask what you actually can't infer. Don't pad.

## Step 2, Discovery loop

When the user corrects you, **do not just accept it**. Spawn follow-up research, read the files they pointed at, verify their claim against the code. Confirm before proceeding.

Present design options when there's a real choice:

```
Design options:
1. [Option A], pros: ...  cons: ...
2. [Option B], pros: ...  cons: ...

Which fits what you want?
```

## Step 3, Task decomposition

Plans are DAGs of tasks, not phases. Each task is independently grabbable, has explicit dependencies, and is small enough to dispatch as a single subagent invocation.

Before writing the plan body, agree on the task list:

```
Proposed tasks:

T1  [name]          (no prereqs)
T2  [name]          (no prereqs)
T3  [name]          (← T1)
T4  [name]          (← T1, T2)
T5  [name]          (← T3)
...

Does the granularity feel right? Anything to split, merge, or reorder?
```

Iterate until approved.

### Task sizing

- **Small enough** to dispatch as a single subagent task, roughly 2-5 file changes, one focused outcome.
- **Independent enough** to merit its own task, if two tasks always touch the same file in interleaved ways, they're one task.
- **Tracer-bullet shaped** when possible, a thin vertical slice through the layers it touches, not a horizontal slice of one layer.
- **Dependencies are real**, `depends_on:` lists only tasks whose output the dependent task *needs to read*, not tasks that happen to be related.

## Step 4, Write the plan

Save to `plans/<YYYY-MM-DD>-<kebab-slug>.md` (or user-specified location).

### Plan skeleton

````markdown
# <Feature> Implementation Plan

Short paragraph describing the rework / feature this plan implements. Include the parse contract pointer so future-you (and `/implement-plan`) read tasks the same way.

> **INVARIANT, no code here.** This plan documents the work. Code changes happen only when `/implement-plan` runs against this file.

## Goal

One paragraph. What we're implementing and why.

## Success criteria

**Automated:**

- [ ] [command an agent can run, `make test`, `npm run typecheck`, file-existence check, etc.]
- [ ] [another]

**Manual:**

- [ ] [UI / behavior observation the user has to verify]
- [ ] [another]

---

## Tasks

### T1, <title>
depends_on: []

- [ ] [checkbox step, concrete action, exact file paths]
- [ ] [another step]
- [ ] [test command to run + expected output]

### T2, <title>
depends_on: []

- [ ] ...

### T3, <title>
depends_on: [T1]

- [ ] ...

### T4, <title>
depends_on: [T1, T2]

- [ ] ...

---

## DAG visualization (informational)

```
T1  <name>          (root)
T2  <name>          (root)
T3  <name>          ← T1
T4  <name>          ← T1, T2
```

## Notes for execution

- `/implement-plan` walks the DAG, dispatching `wai-implementer` per ready task, with parallel cap from `.claude/wai.json`.
- After all tasks land, the spec-reviewer + code-quality-reviewer chain runs per-task.
````

### Parse contract

`/implement-plan` reads this shape. Hard rules so the parse stays trivial:

- **Task heading exactly**: `### T<n>, <title>` (note the em-dash, single space on each side).
- **Immediately under the heading**: `depends_on: [T<n>, T<m>]` or `depends_on: []`. Plain text line, no code fence.
- **Then checkbox steps**: `- [ ]` lines. Each step is one concrete action.
- **Tasks live under a `## Tasks` heading** so the parser can scope the search.

If you deviate from the shape, the downstream tooling silently misses tasks. Don't.

## Step 5, Hard rules for the plan body

- **Exact file paths** in every task, no "the auth module".
- **Read fully, always.** No partial reads of spec / plan / research files.
- **No open questions in the final plan.** If something's unclear at write time, stop and resolve it. Open questions in a plan = a broken plan.
- **Success criteria split into automated and manual.** Always both. Automated = a command an agent can run; everything else is manual.
- **No placeholders.** Never write:
  - "TBD", "TODO", "implement later", "fill in details".
  - "Add appropriate error handling" / "handle edge cases" without the actual code.
  - "Similar to Task N", repeat the relevant detail instead.
  - Steps that describe what to do without showing how.
- **Type / name consistency**, a function called `clearLayers()` in T3 stays `clearLayers()` in T7. Property names, signatures, all consistent across tasks.
- **Be skeptical.** Vague requirements → ask. Don't assume.

## Step 6, Review

Show the user the path and ask for feedback. Iterate. Each round may need fresh research, spawn agents again if the change demands it.

## When spawning subagents

- Parallel, one Agent call per area.
- Specify the directory and the shape of answer you want (file:line refs).
- Wait for all to finish before synthesising.
- If results look wrong, spawn follow-ups before trusting them.
- See `using-subagents` primer for prompt-craft rules.

## Workflow position

```
to-spec → /create-plan → /implement-plan → /ds → /describe-pr → ...
```
