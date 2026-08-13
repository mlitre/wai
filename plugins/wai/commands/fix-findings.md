---
description: Execute a flat findings list item-by-item. Parses a numbered list out of a handoff doc, a `code-reviewer` output, or a diagnosis report, then dispatches `wai-implementer` (freeform) → `wai-spec-reviewer` → `code-reviewer` per item, fully parallel up to `.claude/wai.json`'s `parallel_cap`. Retry-once on reviewer rejection; quarantine on second failure. End-of-walk report lists green vs blocked items.
argument-hint: "[path/to/findings.md] [--parallel-cap N] [--only 3,5]"
---

# Fix Findings

Same machine as `/implement-plan`, different parser. Findings list is the spec. One finding is the unit of work. Reviewer agents gate each finding.

The difference: no DAG. Findings are independent, so there is no topological order and nothing to wait on. Everything that is not already done is ready on turn one.

## Inputs

```
/fix-findings <path>.md
/fix-findings <path>.md --parallel-cap 1   # override config
/fix-findings <path>.md --only 3,5         # run only these findings
```

If no path is given, ask. Don't guess, and don't scrape the conversation for something list-shaped.

Typical sources:

| Source | Where it lands |
|---|---|
| `handoff` skill doc | OS temp dir, path printed by the skill |
| `code-reviewer` findings | pasted into a file, or a review report the user names |
| `/diagnose` report | `plans/<YYYY-MM-DD>-diagnose-<slug>.md` |

## Setup

1. **Read the file completely.** No `limit`/`offset`.
2. **Read `.claude/wai.json`.** Extract `parallel_cap` (default 3 if missing). Override with `--parallel-cap`.
3. **Parse the findings list** (contract below).
4. **Number the items** `F1..Fn` in source order, whatever the file called them. Those IDs are yours, they exist so the report and the retry chain can name things.
5. **Check existing state.** Any item already marked `- [x]` or explicitly "fixed" / "done" in the source is `complete` upfront. Don't re-run it.
6. **Read scene-setting files.** Anything a finding names by path. You paste slices into implementer prompts.

## Parse contract

Findings lists are hand-written and inconsistent. Be forgiving. Accept, in this order of preference:

- `1.` / `1)` ordered list items.
- `- [ ]` / `- [x]` checkboxes.
- `- ` / `* ` plain bullets.
- `### <heading>` sections, when the file is a series of per-finding headings rather than a list.

Rules:

- One item = one top-level entry plus its indented children. Nested sub-bullets are detail for the parent, not separate findings.
- Strip severity prefixes (`[HIGH]`, `Critical:`, `P1`) into a severity field, keep them out of the title.
- If a finding names a `file:line`, capture it. That is the implementer's starting point.
- Ignore prose sections that are not the list: summaries, context, "what I tried" narration. Findings lists usually have exactly one list that matters, the longest one under a heading like "Findings", "Issues", "Remaining work", "Next steps".

If you cannot find a list, stop:

> No findings list found in `<path>`. I looked for numbered items, checkboxes, bullets, and per-finding headings. Point me at the section, or pass a different file.

Do not guess a list out of paragraphs. A wrong parse fans out wrong work in parallel, which is the expensive failure here.

Ambiguity that is not fatal, resolve it and say so in the report: if you found two candidate lists, name which one you took and why.

## Walk

### Ready set

An item is **ready** when it is not `complete` and not `blocked`. There are no dependencies, so on the first pass that is every unfinished item.

### Loop

```
while ready_set is non-empty:
  pick up to parallel_cap ready items
  dispatch implementer for each (single response, multiple Agent calls)
  wait for all to return
  for each item that returned:
    run the per-item review chain (see below)
    update item state: complete | blocked
  recompute ready_set
```

End condition: ready_set empty AND no in-flight dispatches.

A blocked item blocks nothing else. There are no descendants. Note it and keep walking.

### Per-item review chain

Identical to `/implement-plan`:

```
implementer returns DONE → spec-reviewer
  spec-reviewer pass → quality-reviewer
    quality-reviewer pass → mark item complete, tick the checkbox if the source file has one
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

**Retry-once.** One retry per failure mode. Second failure = quarantine.

**Quarantine.** Mark the item `blocked`, report it, continue with the rest.

### Overlap check

Parallel findings sometimes touch the same file. Before dispatching a batch, group items whose captured `file:line` hits the same path and run those **sequentially** within the batch. Two implementers editing one file concurrently is a merge conflict you will pay for later.

## Dispatching an implementer

Agent name: `wai-implementer`, **freeform mode**. Freeform means: no `T<n>` task ID in the prompt. That absence is what the agent branches on, so do not invent one.

Prompt shape:

```
Fix this finding.

Finding: <title, verbatim from the list>
Severity: <if the source gave one>
Location: <file:line, if the source gave one>

Detail (verbatim from the source, including sub-bullets):
<...>

Scene-setting context:
<relevant excerpts from the files the finding names, paste, don't make the subagent hunt>
<project CLAUDE.md highlights>

Investigate before you implement, and keep it bounded to this finding.

Working directory: <repo or worktree path>

Augmentation (retry only):
<previous attempt's reviewer comments + failure trace, inline>
```

Follow the `using-subagents` primer's prompt-craft rules: focused, self-contained, specific output. Never make the implementer read the source findings file, paste the item's text.

## Dispatching reviewers

After an implementer reports `DONE` or `DONE_WITH_CONCERNS`:

1. Capture the commit range the implementer landed (`<base-sha>..<head-sha>`).
2. Dispatch `wai-spec-reviewer` with the finding text as the spec + implementer's report + commit range. The finding is the spec; there is nothing else to check against.
3. On `pass`, dispatch `code-reviewer` with freeform context: commit range, project `CLAUDE.md` path, implementer report, spec-reviewer verdict. The reviewer self-dispatches narrow specialists per heuristic.
4. On any `fail`, kick into the retry chain above.

Sequential, spec first. Quality findings on code that doesn't fix the finding are wasted work.

## End-of-walk report

```markdown
# /fix-findings, `<path>.md`

## Summary
- Findings fixed:   <N> / <total>
- Findings blocked: <M>
- Parsed as: <numbered list | checkboxes | bullets | headings>, <total> items

## Green
- ✓ F1, <title>
- ✓ F2, <title>
- ...

## Blocked
- ✗ F4, <title>
  - Failure mode: <implementer NEEDS_CONTEXT / spec-reviewer fail / quality-reviewer fail / implementer BLOCKED>
  - Last implementer diff: <commit sha or "none">
  - Last reviewer verdict: <quote the verdict reason>
  - Suggested next step: <`/diagnose` if the finding is under-specified, `/create-plan` if the fix needs a real design>

## Concerns to review
- F3, DONE_WITH_CONCERNS: <quote concern>
```

For a blocked item, recommend `/diagnose` when the finding was too vague to act on, and `/create-plan` when the implementer said the fix is bigger than one coherent change.

## Continuous execution

Don't pause between findings for "should I continue?" prompts. Execute until the ready set is empty or the user interrupts. The end-of-walk report is the deliverable.

## Override

Agent names are hardcoded: `wai-implementer`, `wai-spec-reviewer`, `code-reviewer`. Project-local override: drop same-named files under `.claude/agents/`, Claude Code prefers local over plugin.

## See

- `implement-plan.md`, the DAG-shaped sibling of this command.
- `wai-implementer.md`, agent definition, freeform mode section.
- `wai-spec-reviewer.md`, `code-reviewer.md`, agent definitions.
- `using-subagents` skill, prompt-craft primer.
- `docs/adr/0001-wai-implementer-accepts-freeform-tasks.md`, why freeform mode exists.

## Workflow position

```
handoff / code-reviewer / /diagnose → /fix-findings → /ds → /describe-pr → ...
```

For a plan with dependencies between tasks, use `/implement-plan`, same machine, different parser.
