---
name: diagnose
description: Disciplined diagnosis loop for hard bugs and performance regressions. Output is a Diagnosis Report, root cause + minimal repro + proposed fix sketch. Does NOT edit code. Trivial fixes hand off to `cavecrew-builder`; non-trivial fixes hand off to `/create-plan`. Use when the user says "diagnose this" / "debug this", reports a bug, says something is broken/throwing/failing, or describes a performance regression.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
inspired-by:
  - mattpocock/skills/engineering/diagnose
  - obra/superpowers/skills/systematic-debugging
---

# Diagnose

A discipline for hard bugs. Skip phases only when you can name *which* phase you are skipping and *why*.

> **INVARIANT, no code here.** This skill does not modify source files. The output is a written Diagnosis Report. Code changes happen only via `cavecrew-builder` (trivial 1-2 file fix) or `/create-plan → /implement-plan` (non-trivial). See `plugins/wai/WORKFLOW.md`.

## Phase 1, Build a feedback loop

This is the whole skill. Everything else is mechanical.

If you have a fast, deterministic, agent-runnable pass/fail signal for the bug, you will find the cause. Bisection, hypothesis-testing, and instrumentation all just consume that signal. If you don't have one, no amount of staring at code will save you.

Spend disproportionate effort here. Be aggressive. Be creative. Refuse to give up.

### Ways to construct one, roughly in this order

1. **Failing test** at whatever seam reaches the bug, unit, integration, e2e. Cheapest first.
2. **Curl / HTTP script** against a running dev server. Works when the bug is reachable via the network surface.
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot. Works for any program that takes input and produces output.
4. **Replay a captured trace.** Save a real request / payload / event log to disk; replay it through the code path. Works when the bug only shows up with production-shaped data.
5. **Throwaway harness.** Spin up the smallest subset of the system (one service, mocked deps) that exercises the bug code path with a single function call.
6. **Bisection harness.** If the bug appeared between two known states (commit, dataset, version), automate "boot at state X, check, repeat" so `git bisect run` works end-to-end.

If none of those work, stop and re-read the bug report. The loop might be easier than you think.

### Iterate on the loop itself

The loop is a product. Once you have *a* loop, ask:

- Can I make it faster? Cache setup, skip unrelated init, narrow the test scope.
- Can I make the signal sharper? Assert on the *specific* symptom, not "didn't crash".
- Can I make it more deterministic? Pin time, seed RNG, isolate filesystem, freeze network.

A 30-second flaky loop is barely better than no loop. A 2-second deterministic loop is a debugging superpower.

### Non-deterministic bugs

The goal is not a clean repro but a *higher reproduction rate*. Loop the trigger 100×, parallelize, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is debuggable. 1% is not. Keep raising the rate until it is.

### When you genuinely cannot build a loop

Stop and say so explicitly. List what you tried. Ask the user for one of:

- (a) access to whatever environment reproduces it,
- (b) a captured artifact (HAR file, log dump, core dump, screen recording with timestamps),
- (c) permission to add temporary production instrumentation.

Do not proceed to hypothesize without a loop. Hypothesizing without a feedback signal is theater.

## Phase 2, Reproduce

Run the loop. Watch the bug appear. Confirm two things:

- The loop produces the failure mode the *user* described, not a different failure that happens to be nearby. Wrong bug = wrong fix.
- The failure is reproducible across multiple runs (or for non-deterministic bugs, at a rate high enough to debug against).

## Phase 3, Minimize

Cut everything that isn't load-bearing. Trim inputs, trim dependencies, trim setup. After minimizing:

- Smallest input that still triggers the bug.
- Fewest moving parts in the code path.
- Most direct assertion of the symptom.

Minimization is a *test of understanding*. If you can't make the repro smaller, you don't yet know what causes it. Stay here.

## Phase 4, Hypothesize

State your hypothesis in one sentence: "The bug is caused by X because Y, and I'd expect Z to fix it."

If the hypothesis is fuzzy, the fix will be fuzzy. Sharpen it before moving on.

Write the hypothesis down. You will be tempted to revise it silently. Don't. If it turns out to be wrong, the revision is valuable data.

## Phase 5, Instrument

Add the cheapest possible observation that will confirm or refute the hypothesis. A log line, a breakpoint, an assertion, a `print`, whatever lands the signal fastest.

Do not refactor while diagnosing. Do not rename variables. Do not clean up code style. Every change you make is a confounder for the next run of the loop.

### Multi-layer systems: instrument every boundary

When the path crosses components (CI → build → signing, API → service → DB, workflow → script → tool), instrument at each layer before guessing which one is wrong:

```
For EACH component boundary:
  - log what enters
  - log what exits
  - verify env / config propagation
  - check state at the layer
```

Run the loop once with this in place. The evidence will show *which* layer breaks (secrets → workflow ✓, workflow → build ✗). Then investigate that layer specifically. Don't propose fixes before you can name the failing boundary.

## Phase 6, Write the Diagnosis Report

When the hypothesis is confirmed, write a report. Do **not** edit source code. The report becomes seed input to `cavecrew-builder` (trivial fix) or `/create-plan` (non-trivial fix).

Report shape:

```markdown
# Diagnosis, <one-line symptom>

## Symptom

What the user observes. What the bug report says. What's failing.

## Repro

The minimal repro you arrived at in Phase 3. Commands + expected vs actual output.

## Root cause

One sentence. What the code is actually doing wrong, named at the right level (boundary, layer, line range).

## Evidence

The instrumented run from Phase 5. Specific log lines / assertions that confirmed the hypothesis. File:line refs for the failing boundary.

## Proposed fix

A *sketch* of the change. Name the file(s) and the shape of the edit. Do not write the diff, that's the next skill's job.

If fix is trivial (1-2 files, mechanical) → hand off to `cavecrew-builder`.
If fix is non-trivial → hand off to `/create-plan plans/<date>-diagnose-<slug>.md`.

## Regression test

The seam where a test should go to catch this from coming back (unit / integration / e2e). The shape of the assertion. Same hand-off applies.
```

### 3+ failed hypotheses → question the architecture

Count your hypotheses. After three failed ones, each revealing a new symptom elsewhere or requiring "massive refactoring", stop hypothesizing. The pattern is architectural, not local.

Symptoms of an architectural problem disguised as a bug:

- Every hypothesis reveals new shared state / coupling / problem in a different place.
- Each proposed fix creates new symptoms downstream.
- Fixes require restructuring well beyond the apparent bug.

When this happens, raise the question explicitly: *is the underlying pattern sound, or are we sticking with it through inertia?* Discuss with the user before attempt #4. This is not a failed hypothesis, it's a wrong shape. Capture it in the report's "Root cause" section and recommend an ADR / architecture pass before any fix attempt.

## Phase 7, Hand off

Print the report path and the next step:

- **Trivial fix** (1-2 files, mechanical): hand off to `cavecrew-builder` with the report as context.
- **Non-trivial fix**: hand off to `/create-plan plans/<date>-diagnose-<slug>.md`, the report becomes seed input. The plan tasks will include the regression test as their own DAG node.

Either way, the fix lands later through the normal workflow. This skill stops at the report.

## Anti-patterns

- **Hypothesizing before the loop works.** You will be wrong, you won't know you're wrong, and you'll burn an hour.
- **Fixing nearby code "while you're in there".** Confounds the diagnosis. Open a separate change.
- **Trusting the bug report verbatim.** Users describe symptoms, not causes. Phase 2 exists to verify you are chasing the right one.
- **Skipping the regression test because the fix "is obvious".** The bug was obvious in hindsight too.

### Rationalizations

| Excuse | Reality |
|--------|---------|
| "Issue is simple, don't need process" | Simple issues have root causes too. The loop is fast for simple bugs. |
| "Emergency, no time for process" | Disciplined debugging is faster than guess-and-check thrashing. |
| "Just try this first, then investigate" | First fix sets the pattern. Do it right from the start. |
| "I'll write the test after confirming the fix works" | Untested fixes don't stick. The failing test is what proves the fix. |
| "Multiple fixes at once saves time" | Can't isolate what worked. Causes new bugs. |
| "Reference is too long, I'll adapt the pattern" | Partial understanding guarantees bugs. Read it completely. |
| "I see the problem, let me fix it" | Seeing symptoms ≠ understanding root cause. |
| "One more fix attempt" (after 2+ failures) | 3+ failures = architectural problem. Question the pattern, don't fix again. |
