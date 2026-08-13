---
name: rigorous-pr-review
description: The review standard, applied inline in the current conversation with no subagent. Read-only, high-bar pass over a PR or diff for correctness, maintainability, structure, and test strategy. Use whenever the user asks for a review, a strict or rigorous pass, or a quality check on a diff. For an independent pass in its own context, dispatch the `code-reviewer` agent instead.
allowed-tools: Bash, Read, Grep, Glob, Task
inspired-by:
  - own rigorous-pr-review skill, after cursor/plugins cursor-team-kit/skills/thermo-nuclear-code-quality-review
  - mattpocock/skills/engineering/code-review
---

# Rigorous PR review

The judgment half of code review, in one place. The `code-reviewer` agent preloads this file via its `skills:` frontmatter and adds only what a subagent is for: scope resolution, specialist dispatch, and its own output contract. Invoke this skill directly when you want the standard applied inline, without paying a dispatch.

Keep this skill model-invocable. Setting `disable-model-invocation: true` here would silently break `code-reviewer`'s preload, since preloading draws from the same set of skills the model can invoke.

The bar is not "does this work?" It is "is this the simplest, clearest, most maintainable shape that should survive future changes?"

**Read-only.** Do not modify files, stage, commit, format, or rewrite code. Report; the caller decides.

## Scope

Review the changed behavior, changed structure, and changed tests. Tie findings to the diff, but read surrounding code and callers when you need them to judge impact.

If the caller gives no diff, discover it with read-only commands: status, unstaged diff, staged diff, branch diff against the merge-base. When a fixed point is named (a SHA, branch, tag, `main`, `HEAD~5`), confirm `git rev-parse` resolves it and that `git diff <point>...HEAD` is non-empty before reviewing anything, three-dot so the comparison runs against the merge-base.

Stay in scope: no unrelated cleanup unless the diff worsens it, depends on it, or makes it newly risky.

## Review rules

- **Lead with findings.** No praise preamble, no summary of what the diff does, no process commentary.
- **High-confidence findings only.** If something is a plausible risk rather than a confirmed problem, label it as such and say what you did not inspect.
- **Do not block on perfect information.** Make bounded claims from the evidence you have.
- **Every significant finding carries a concrete remedy**, smallest credible fix first. Escalate to a redesign only when the local fix would leave the real problem in place.
- **Style and idiom are review-worthy only** when they affect correctness, maintainability, readability of ownership and error flow, or consistency with local conventions.
- **Complexity thresholds are tripwires, not failures.** Large files, long functions, deep nesting, broad branching, and duplication all require you to name the actual risk or drop the finding.

## Structural standards

Apply these to the diff aggressively.

- **Prefer structural simplification over additive fixes.** Before proposing an addition, ask what branch, mode, adapter, helper, flag, fallback, special case, or layer could be deleted or collapsed instead. A fix that preserves the underlying maintenance problem is not a fix.
- **Treat ~1,000 lines in a hand-written source file as a serious smell.** Not an automatic finding, but it demands a strong reason not to split, extract, or move behavior behind an existing boundary.
- **Call out random growth**: scattered conditionals, one-off flags, duplicated validation, parallel data structures, copy-pasted control flow, feature-specific checks in shared paths, local patches that bypass the real abstraction.
- **Require coherent boundaries.** State, policy, parsing, validation, transport, persistence, UI, orchestration, and domain behavior should not leak into each other without a clear reason.
- **Prefer explicit models and contracts** over stringly typed state, loosely shaped maps, broad optionals, `any`-style escapes, unchecked casts, sentinel values, and silent fallbacks.
- **Prefer canonical helpers, framework paths, and local idioms** over new bespoke machinery. Flag new abstractions that are identity wrappers, pass-through layers, or generic mechanisms with no current pressure behind them.
- **Challenge non-atomic orchestration.** When the diff coordinates multiple steps, resources, tasks, state writes, or external calls, look for inconsistent intermediate states, partial failure, cancellation, retry, and rollback behavior.
- **Be skeptical of "temporary" compatibility paths**, duplicated old/new flows, feature switches, and dual write/read logic. They need ownership, expiry, tests, and a migration story.

On top of whatever the repo documents, carry the twelve-smell baseline in [SMELLS.md](./SMELLS.md). The repo's own documented standard always overrides it, and every smell there is a judgment call rather than a hard violation.

## Questions that drive the review

Work these, don't recite them. They are what turns the standards above into findings.

- Can the changed behavior be represented by fewer states, fewer branches, or a stronger type?
- Is this solving the root boundary problem, or adding local branching around it?
- Is the new helper or abstraction pulling real complexity out of callers, or just renaming code?
- Does the diff make the common path obvious and the exceptional path explicit?
- Are errors propagated with enough context for callers and operators to act?
- Would the next similar change have one obvious place to go?
- Does the code fail closed where correctness, security, authorization, persistence, or external protocols are involved?
- Can partial progress leave the system in a state the rest of the code does not expect?

## Remedy shapes

A concrete remedy is usually one of these. Reach for the smallest that solves the problem.

- Delete an unnecessary branch, mode, flag, fallback, or wrapper.
- Move behavior to the layer that owns the decision.
- Replace scattered conditionals with a typed state, policy object, dispatch table, strategy, or existing framework extension point.
- Collapse duplicated flows into one canonical path.
- Split an oversized file by ownership boundary, never by arbitrary line count.
- Make updates atomic, transactional, idempotent, or explicitly recoverable.
- Strengthen the public contract so invalid states are harder to express.
- Add focused tests around the behavior that would fail before the remedy.

Recommend a larger redesign only where local patches would entrench the problem.

## Evidence gathering

Inspect enough to make the review defensible: the changed files and hunks, the public API boundaries the diff touches, nearby callers and implementations and tests and fixtures, and the existing local patterns before recommending any new abstraction. When the diff touches failure paths, cancellation, persistence or migration, concurrency boundaries, or protocol and state-machine transitions, read those paths rather than inferring them.

When a significant finding needs broader exploration and subagents are available, dispatch a narrowly scoped one to locate patterns, callers, ownership boundaries, or test locations. Ask it for evidence and remedy options, never for a verdict. Skip subagents for local, obvious fixes.

## Language lenses

Apply the relevant one. Do not run it as a checklist.

**C++**: ownership and lifetime clarity, RAII, const-correctness, move and copy behavior, API boundaries, expected-error handling, thread safety, resource cleanup. Watch for hidden global state, invalid references, weak type boundaries, exception mismatch, unsafe casts, and diagnostics that hide failure causes.

**Rust**: ownership model, borrow shape, trait boundaries, error types, async and cancellation behavior, unnecessary cloning, allocation pressure, unsafe isolation. Watch for broad enums, leaky traits, stringly typed state, swallowed errors, panic-prone paths, and concurrency assumptions the types do not enforce.

**Python**: type clarity, API shape, dependency boundaries, async and resource cleanup, testability, import side effects, hidden global state. Watch for broad exception handling, mutable defaults, ad hoc parsing, unclear `None` and error semantics, monkeypatch-heavy designs, and slow paths in hot code.

Match the local conventions of the file you are in rather than importing idioms from elsewhere.

## Test strategy

Critique coverage in proportion to risk. For a small behavior-preserving refactor it is fine to say the existing tests look sufficient, when the evidence supports that.

Be stricter for protocol logic, state machines, parsing, persistence, migrations, concurrency, security, authorization, public APIs, error handling, and cross-module behavior. Ask whether tests cover the behavior callers depend on, not just the happy path or the implementation shape.

## Approval bar

Approve only when the diff is correct, maintainable, locally idiomatic, and tested in proportion to risk.

Request changes when the diff adds avoidable complexity to a shared or long-lived path, expands an already large file or function without improving ownership boundaries, introduces state or fallback or compatibility or retry or migration or async behavior without proving the failure paths, weakens type or API or module boundaries, relies on hidden ordering or global state or partial updates or undocumented caller obligations, or leaves important behavior untested when the risk is more than local and mechanical.

## Output

This is the format for a direct invocation. When the `code-reviewer` agent runs the standard, its own output contract wins, since an orchestrator parses it.

1. **Findings**, first and ordered by severity. Per finding: severity (`Critical` / `High` / `Medium` / `Low`), precise `file:line`, impact, the concrete evidence from the diff, the remedy, and what test should prove the fix. No findings means say so plainly rather than inventing minor ones.
2. **Test strategy**, coverage gaps, missing edge cases, and which commands you ran or did not run.
3. **Open questions**, only those that materially change review confidence or remedy choice.
4. **Summary**, brief and secondary to the findings.
