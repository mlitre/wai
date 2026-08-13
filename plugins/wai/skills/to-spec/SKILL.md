---
name: to-spec
argument-hint: "[--interview|--synthesize]"
description: Produce a spec for a feature/bug/refactor. Two interaction modes, interview (ask questions, build the spec collaboratively) or synthesize (compress existing conversation context into a spec). Output is a local file at `specs/<YYYY-MM-DD>-<slug>.md`. Use when user says "spec this out", "write a PRD", "design this", or before `/create-plan`.
inspired-by:
  - obra/superpowers/skills/brainstorming
  - mattpocock/skills/engineering/to-prd
---

# To Spec

Turn ideas into specs. Output is a written spec the user can edit, share, or hand to `/create-plan`.

> **INVARIANT, no code here.** This skill does not modify source files. Code changes happen only in `/implement-plan`. See `plugins/wai/WORKFLOW.md`.

## Arguments

```
/to-spec                # ask interview|synthesize on the first turn
/to-spec --interview    # force interview mode
/to-spec --synthesize   # force synthesize mode, using the current conversation
```

Specs are written as local files under `specs/<YYYY-MM-DD>-<slug>.md`. wai does not publish to an issue tracker.

## Mode

Every invocation opens with a single multiple-choice:

> Interview or synthesize?
> 1. **interview**, I ask questions one at a time, build the spec collaboratively.
> 2. **synthesize**, I compress what's already in this conversation into a spec.

`--interview` / `--synthesize` arg overrides the prompt.

## Output target

The spec is a local file at `specs/<YYYY-MM-DD>-<kebab-slug>.md`, committed to git.

**Hard gate before code.** Do not invoke any implementation skill until the user approves the written spec.

wai does not publish specs to an issue tracker. If you want the spec in a tracker, paste it there yourself.

## Interview mode

Use when the user has the idea but the requirements aren't sharp yet.

### 1. Project context

Check current repo state, files, recent commits, existing ADRs / `CONTEXT.md`. Use the project's domain glossary throughout the spec.

### 2. Scope sanity check

If the request describes multiple independent subsystems ("build a platform with chat + billing + analytics + ..."), flag immediately. Don't refine details of something that needs decomposition. Help the user split into sub-projects, each with its own spec → plan → implementation cycle.

### 3. Ask questions one at a time

- Prefer multiple-choice over open-ended.
- Focus on purpose, constraints, success criteria, not implementation details.
- One question per turn. Break compound questions into multiple turns.

### 4. Propose 2-3 approaches

When there's a real design choice, present options with trade-offs and a recommendation. Lead with the recommended option and explain why.

### 5. Present design sections

Once the picture is clear, present design sections one at a time and get section-by-section approval. Cover: architecture, components, data flow, error handling, testing.

Scale each section to its complexity, a few sentences for straightforward, up to 200-300 words for complex topics.

### 6. Write the spec

Save to `specs/<YYYY-MM-DD>-<kebab-slug>.md`. Use the template below.

### 7. Spec self-review

Re-read with fresh eyes:

1. **Placeholders**, any "TBD", "TODO", or vague requirements? Fix inline.
2. **Internal consistency**, sections contradict each other? Fix.
3. **Scope**, focused enough for one implementation plan? If not, decompose.
4. **Ambiguity**, could any requirement be interpreted two ways? Pick one, make it explicit.

### 8. User review gate (local-file mode)

> Spec written to `<path>`. Please review and tell me if you want changes before we start the implementation plan.

Wait. If they request changes, edit + re-run self-review. Only proceed when approved.

### 9. Hand off

Suggest `/create-plan <spec-path>` as the next step.

## Synthesize mode

Use when the conversation already contains enough context to write the spec without further interviewing.

- Skim the conversation for: problem statement, decisions made, constraints discovered, approaches discussed, ADRs referenced.
- Look for unresolved questions, if there are any, the conversation isn't ripe for synthesis. Switch to interview mode for those gaps.
- Write the spec using the same template.
- Run the same self-review.
- Run the user review gate before anything downstream starts.

## Spec template

```markdown
# <Feature name>

> Spec for <one-line problem statement>.

## Problem

What the user is trying to do and what's stopping them today.

## Solution

What the spec proposes, from the user's perspective.

## User stories

1. As a <actor>, I want <feature>, so that <benefit>.
2. ...

## Implementation decisions

- Modules to build / modify (deep modules where possible).
- Interfaces.
- Architectural decisions.
- Schema changes.
- API contracts.
- Specific interactions.

(No file paths or code snippets, they go stale. Exception: a snippet that encodes a decision more precisely than prose can, state machine, reducer, schema, type shape, may be inlined. Trim to decision-rich parts, not a working demo.)

## Testing decisions

- What makes a good test for this (external behavior only).
- Which modules will be tested.
- Prior art for similar tests in the codebase.

## Out of scope

Explicit non-goals. Prevents scope creep at planning time.

## Open questions

(None at write time. If anything is unresolved, the spec is not done.)

## Further notes

Anything else worth recording.
```

## Hard rules

- **One question at a time** in interview mode. No compound questions.
- **YAGNI**, strip unnecessary features ruthlessly.
- **Use the project's domain glossary** throughout. Match existing vocabulary.
- **No open questions in the written spec.** Resolve mid-loop. Open questions = broken spec.
- **No file paths or code snippets** in the spec, they rot fast. Carve-out: snippets that encode a decision.
- **Hard gate before code (local-file mode).** Do not invoke any implementation skill, write code, scaffold, or take any implementation action until the user approves the written spec. "This is too simple to need a spec" is the rationalization that wastes the most work.
- **Suggest `/create-plan` next** once the user has approved the spec.

## Why this replaces `brainstorming` + `to-prd`

`brainstorming` was interview-mode-only with a local-file hard gate. `to-prd` was synthesize-mode-only with a tracker default. They were the same skill split by output medium. Merged here with mode (`interview` | `synthesize`) as the only axis; the tracker target was cut after a usage audit found it had never once been used.
