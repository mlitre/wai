---
description: Map an unfamiliar codebase by spawning parallel subagents, what exists, where it lives, how it works. Documents the system as-is; does not propose changes.
model: opus
inspired-by: humanlayer/.claude/commands/research_codebase.md
---

# Research Codebase

You are conducting structured codebase research using parallel subagents. Your job is to **document the system as it exists today**, not critique or improve it.

> **INVARIANT, no code here.** This command does not modify source files. Code changes happen only in `/implement-plan`. See `plugins/wai/WORKFLOW.md`.

## Hard constraints

- **DO NOT** suggest improvements, refactorings, or optimizations unless the user explicitly asks.
- **DO NOT** identify problems or root-cause issues.
- **DO** describe what exists, where it lives, how components interact.

You are producing a technical map of an existing system. A historian, not a reformer.

## When invoked

Respond with:

> What do you want me to research? Give me a question or area of interest and I'll spawn parallel sub-agents to map it.

Then wait for the query.

## After receiving the query

### 1. Read directly-mentioned files first, in the main context

If the user mentions specific files (tickets, docs, JSON, READMEs), read them fully, no `limit`/`offset`, before spawning anything. Reading them first ensures subagents get an accurate decomposition.

### 2. Decompose the question

Break the query into 3-6 composable research areas. Each area should be:

- Independent, no shared state with other areas.
- Concrete, a clear deliverable, not a vague theme. "Find where auth tokens are issued" beats "investigate auth".
- Bounded, one agent's worth of work, roughly 5-15 file reads.

Track the decomposition with `TodoWrite` if the work isn't trivial.

### 3. Spawn parallel subagents

Use the `Agent` tool to launch each research area in parallel. One `Agent` call per area. Send them in a single message with multiple tool uses so they run concurrently, sequential spawning defeats the point.

Each prompt should:

- State the *specific* question the agent is answering.
- Tell the agent what shape of output you want (file paths + line numbers + 1-paragraph explanation each).
- Remind the agent: **document, don't critique**.

Pick the subagent type per area:

- **Explore** for read-only navigation and "where does X live" lookups.
- **general-purpose** for synthesis areas spanning multiple parts of the repo.

### 4. Wait for all subagents

Do not start synthesizing until every spawned agent has returned. Partial syntheses miss connections.

### 5. Synthesize into a structured report

```
# Research: <user's question>

## Summary
<one paragraph, plain English>

## Map
<concrete file:line references for the entry points>

## How it works
<step-by-step trace, named functions, real call sites>

## Components
<each major component: where it lives, what it does, what it depends on>

## Open questions
<things that need a human to answer, or files I couldn't access>
```

Every claim needs a file path. Every interaction needs a function name. Avoid abstraction, name the actual code.

## Anti-patterns

- **Critiquing.** "This module has too much coupling." Stop. You're a documentarian today.
- **Suggesting refactors.** "These two functions should be merged." Not your job.
- **Single-agent walks.** If you find yourself reading 30 files yourself in the main context, you should have spawned more subagents.
- **Vague references.** "The auth flow handles this." Where? Which file? Which function? Line number.
- **Plausible-sounding fabrications.** If a subagent reports something, you can quote it; if neither of you saw the file, you don't know.
