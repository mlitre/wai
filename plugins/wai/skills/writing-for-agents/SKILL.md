---
name: writing-for-agents
description: Writing any document an agent consumes. Use when creating or editing a skill, an agent, a command, CLAUDE.md, AGENTS.md, or a reference doc reached by a pointer.
inspired-by:
  - mattpocock/skills/productivity/writing-for-agents
  - obra/superpowers/skills/writing-skills
  - anthropic/skill-creator/skills/skill-creator
---

# Writing for agents

A skill, a `CLAUDE.md`, an agent definition, a doc reached by a pointer: the packaging differs, the writing does not. The same levers make each one predictable, where predictable means the agent takes the same *process* every run, not that it produces the same output.

When the document is a skill, read [SKILL-MECHANICS.md](./SKILL-MECHANICS.md) for frontmatter, the invocation choice, and router skills.

## Before you write

Scan the conversation first. If the user has been doing the workflow they want written down ("turn this into a skill"), the substance is already in front of you: tools used, sequence, corrections, input and output formats. Extract that, then ask only what is missing. Confirm before drafting.

Writing from scratch what the transcript already contains is the most common way these documents come out generic.

## Context pointers

A **context pointer** is a reference held in the agent's context that names out-of-context material and encodes the condition for reaching it. A skill's `description` is one. A line in `CLAUDE.md` naming a doc is the same object.

The pointer's *wording*, not its target, decides when the agent reaches the material, and how reliably. A must-have target behind a weakly worded pointer is a variance bug: sharpen the wording first, and inline the material only if sharpening fails.

A pointer does two jobs: state what the material is, and list the **branches** that should trigger reaching it (a branch is a distinct case the document handles, so different runs take different paths through it). Every word of an always-loaded pointer costs on every turn, so it earns harder pruning than the body:

- **Front-load the leading word.** The pointer is where it does its triggering work.
- **One trigger per branch.** Synonyms renaming a single branch are one branch written twice. Collapse them, keep only genuinely distinct branches.
- **Cut identity the body already carries.**

### The description trap

A pointer states *when*, never *how*. When a description summarizes the workflow, the agent follows the summary and skips reading the body.

Real case: a skill description said "code review between tasks", so the agent did one review even though the body required two (spec compliance, then code quality). Changing the description to name only the triggering condition made the agent read the body and run both.

```yaml
# BAD, summarizes the workflow, so the body goes unread
description: Use when executing plans, dispatches a subagent per task with code review between tasks

# BAD, process detail in the pointer
description: Use for TDD, write the test first, watch it fail, write minimal code, refactor

# GOOD, triggering conditions only
description: Use when executing implementation plans with independent tasks

# GOOD, trigger plus symptoms, no workflow
description: Use when tests have race conditions, timing dependencies, or pass and fail inconsistently
```

If the pointer tells the agent *how* the document works, rewrite it to say *when* it applies. The body is for how.

## The two loads

Every document and pointer you add spends one of two budgets:

- **Context load**, the cost of always-loaded material on the agent's window: a `CLAUDE.md` line, a skill description, anything in context every turn, spending tokens and attention whether or not it fires.
- **Cognitive load**, the cost on the human: which documents exist, and when to reach for each. The human is the index. Not a cost to minimize; it is the price of human agency. Spend it where human judgment matters, remove it where it does not.

Material reached only through a pointer escapes context load at the price of the pointer's own line. Material with no pointer at all rides entirely on cognitive load.

## Information hierarchy

A document is built from two content types that mix freely: **steps** (ordered actions the agent performs) and **reference** (definitions, rules, facts consulted on demand). A document can be all steps (a recipe), all reference (a review's rules, this document), or both.

The core decision is where each piece sits on the **information hierarchy**, a ladder ranked by how immediately the agent needs the material:

| Level | When it loads | Budget |
|-------|---------------|--------|
| **Pointer**, frontmatter `name` + `description`, or the naming line in `CLAUDE.md` | always in context | ~100 words |
| **In-file step**, what the agent does, in order | when the pointer fires | the primary tier |
| **In-file reference**, consulted on demand | when the pointer fires | often a flat peer set, which is fine |
| **Disclosed reference**, a sibling file or any external doc | only when its own pointer fires | unlimited |

Push too little down and the top bloats. Push too much and you hide material the agent needs. That tension is the whole decision.

**Progressive disclosure** is the move down the ladder, out of the main file and behind a pointer, so the top stays legible. It is not primarily a token optimization; it is how the hierarchy is protected. Branching is the cleanest test: inline what every branch needs, disclose what only some branches reach. When a document has steps, in-file reference that should have been disclosed buries them, and attending to them becomes a coin flip.

**Co-location** is the within-file companion. The ladder decides how far down a piece sits; co-location decides what sits beside it once there. Keep a concept's definition, rules, and caveats under one heading rather than scattered, so reading one part brings its neighbors with it. Distinct from duplication: duplication repeats one meaning in two places, scattering fragments one meaning across many.

**Sprawl** is the failure mode: a document simply too long, even when every line is live and unique. Attention thins across the excess, and every extra line is one more to keep relevant. The cure is the ladder.

## Steps and completion criteria

Every step ends on a **completion criterion**, the condition telling the agent the work is done. Two properties make it a lever:

- **Clarity.** Can the agent tell done from not-done? A vague bound ("understanding reached") invites **premature completion**: ending the step before it is genuinely done, attention slipping to being done. The visible steps still ahead supply the pull; the criterion's clarity is the resistance. Sharpen the bound first, since that is local and cheap. Only if it is irreducibly fuzzy *and* you observe the rush, split the sequence to hide the later steps, and note that hiding works only across a real context boundary (a handoff or a subagent dispatch). An inline call leaves the later steps in context and clears nothing.
- **Demand.** How much it requires. "Every modified model accounted for" forces thorough work where "produce a change list" does not. Demand drives the digging the agent does inside the work, and it is not step-bound: "every rule applied" binds a body of flat reference just as "every step done" binds a sequence, which is how an all-reference document still carries an exhaustiveness bar.

The strongest criteria are both checkable and exhaustive.

## When to split

Splitting one document into two spends one of the two loads, so split only when the cut earns it:

- **By sequence**, where the later steps tempt the agent to rush the one in front of it. Keeping them out of view drives more legwork on the current task. Beware the reverse: merging sequences exposes each step to what follows, inviting premature completion.
- **By invocation**, skill-specific. See [SKILL-MECHANICS.md](./SKILL-MECHANICS.md).

## Leading words

A **leading word** is a compact concept already living in the model's pretraining that the agent thinks with while running the document (*lesson*, *fog of war*, *tracer bullets*). Repeated as a token, never as a sentence, it accumulates a distributed definition and anchors a whole region of behavior in the fewest tokens by recruiting priors the model already holds. Coining your own works if you define it clearly, but a made-up word recruits no priors: you pay in definition tokens what a pretrained word gives free. Reach for an existing word first.

It anchors twice. In the body, execution: the agent reaches for the same behavior every time the word appears, and inside flat reference it focuses attention on a class of thing to look for. In a pointer, invocation: when the same word lives in your prompts, your docs, and your codebase, the agent links that shared language to the material and reaches it more reliably.

Hunt for passages begging to collapse into a single token:

- "fast, deterministic, low-overhead" becomes *tight* (a tight loop).
- "a loop you believe in" becomes *red*, turning a fuzzy gate into a binary observable state.

**Negation** is the failure mode beside this lever. Steering by prohibition drags the forbidden behavior into context and makes it more available, not less. Say "don't think of an elephant" and the elephant is all there is; the negation is a weak modifier that the strongly activated concept overruns, so the ban half-reads as an instruction. Prompt the **positive**: state the target behavior so the banned one is never spoken. A prohibition earns its place only as a hard guardrail you cannot phrase positively, and even then pair it with the positive target.

## Pruning

- Keep each meaning in a **single source of truth**, one authoritative place, so changing the behavior is a one-place edit. **Duplication** costs maintenance and tokens, and inflates a meaning's prominence on the ladder past its real rank. It is the accidental inverse of a leading word, which repeats a token on purpose and never the meaning.
- The **environment** is a source of truth too: `package.json` scripts, config files, the directory layout, `--help` output. A document that restates it is a **cache**, a copy of a lookup, earning its load only when the lookup is expensive. Cache what the agent cannot find by looking: the unwritten convention, the reason behind a choice, the gotcha no config confesses. Leave one-file, one-command lookups to the environment, where they cannot go stale.
- Check every line for **relevance**. A line loses it by never bearing on the task (mere exposition, or a branch that should be disclosed) or by going stale as the world it describes changes. Without a pruning discipline the default fate is **sediment**: stale layers that settle because adding feels safe and removing feels risky, until you have to core down through them to find what is still live.
- Hunt **no-ops** sentence by sentence. An instruction the model already obeys by default pays load to say nothing. The test, does it change behavior versus the default, is model-relative rather than reader-relative: two people disagreeing about a no-op disagree about the default, and settle it by running the document, not by debating. When a sentence fails, delete the whole sentence rather than trim words from it. The test also grades leading words: a word too weak to beat the default (*be thorough*, when the agent is already thorough-ish) is a no-op, and the fix is a stronger word (*relentless*), not a different technique.
