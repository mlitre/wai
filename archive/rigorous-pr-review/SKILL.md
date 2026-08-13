---
name: rigorous-pr-review
description: Review-only, high-bar PR or diff review focused on correctness, maintainability, structure, test strategy, and local convention fit for C++, Rust, Python, or mixed-language changes. Use when the user invokes /rigorous-pr-review or asks for a strict, review-only quality pass over a PR or diff (no edits).
version: 1.0.0
---

# Rigorous PR Review

Run a review-only code quality pass over a PR or diff. Keep the tone direct and professional. Be strict about correctness, maintainability, unnecessary complexity, weak boundaries, and missing tests, but do not perform edits unless the user explicitly asks for a later implementation pass.

The standard is not "does this work?" The standard is "is this the simplest, clearest, most maintainable shape that should survive future changes?"

Inspired by Cursor's `thermo-nuclear-code-quality-review` skill: https://github.com/cursor/plugins/blob/main/cursor-team-kit/skills/thermo-nuclear-code-quality-review/SKILL.md

## Scope

Review the changed behavior, changed structure, and changed tests. Tie findings to the diff, but inspect surrounding code and callers when needed to understand impact.

If the user does not provide a diff, use read-only project commands to discover it, such as VCS status, unstaged diff, staged diff, and PR branch diff. Honor all active system, developer, repository, and AGENTS.md-style instructions before choosing commands.

Do not report unrelated cleanup unless the diff worsens it, depends on it, or makes it newly risky.

## Review Rules

- Keep the review read-only by default. Do not modify files, stage changes, commit, format, or rewrite code during this skill.
- Lead with findings. Do not start with praise, broad summaries, or process commentary.
- Prefer high-confidence findings. If something is a plausible risk rather than a confirmed problem, label it as such and state what was not inspected.
- Do not block on perfect information. Make reasonable bounded claims from the evidence available.
- Require every significant finding to include a concrete remedy. Give the smallest credible fix first.
- Use a broader redesign only when the local fix would preserve the underlying maintenance problem.
- Treat style and idiom as review-worthy only when they affect maintainability, correctness, readability of ownership/error flow, or consistency with local conventions.
- Treat complexity thresholds as tripwires, not automatic failures. Large files, long functions, deep nesting, broad branching, and duplication require an explanation of the actual risk.

## Structural Standards

Apply these standards aggressively to the diff.

- Prefer structural simplification over additive fixes. First ask what branch, mode, adapter, helper, flag, fallback, special case, or layer can be deleted or collapsed.
- Treat crossing roughly 1,000 lines in a hand-written source file as a serious review smell. Do not fail it automatically, but require a strong reason not to split, extract, or move behavior behind an existing boundary.
- Call out random growth: scattered conditionals, one-off flags, duplicated validation, parallel data structures, copy-pasted control flow, feature-specific checks in shared paths, and local patches that bypass the real abstraction.
- Require coherent boundaries. State, policy, parsing, validation, transport, persistence, UI, orchestration, and domain behavior should not leak into each other without a clear reason.
- Prefer explicit models and contracts over stringly typed state, loosely shaped maps, broad optionals, `any`-style escapes, unchecked casts, sentinel values, and silent fallbacks.
- Prefer canonical helpers, framework paths, and local idioms over new bespoke machinery. Flag new abstractions that are identity wrappers, pass-through layers, or generic mechanisms without current pressure.
- Challenge sequential orchestration and non-atomic updates when the diff coordinates multiple steps, resources, tasks, state writes, or external calls. Look for inconsistent intermediate states, partial failure, cancellation, retry, and rollback behavior.
- Be skeptical of "temporary" compatibility paths, duplicated old/new flows, feature switches, and dual write/read logic. They need ownership, expiry, tests, and a migration story.

## Design Questions

Use these questions to drive the review:

- Can the changed behavior be represented by fewer states, fewer branches, or a stronger type?
- Is this solving the root boundary problem, or adding local branching around it?
- Is the new helper or abstraction pulling real complexity out of callers, or just renaming code?
- Does the diff make the common path obvious and the exceptional path explicit?
- Are errors propagated with enough context for callers and operators to act?
- Would the next similar change have one obvious place to go?
- Does the code fail closed where correctness, security, authorization, persistence, or external protocols are involved?
- Can partial progress leave the system in a state the rest of the code does not expect?

## Remedy Standards

A concrete remedy can be one of these shapes:

- Delete an unnecessary branch, mode, flag, fallback, or wrapper.
- Move behavior to the layer that owns the decision.
- Replace scattered conditionals with a typed state, policy object, dispatch table, strategy, or existing framework extension point.
- Collapse duplicated flows into one canonical path.
- Split an oversized file by ownership boundary, not by arbitrary line count.
- Make updates atomic, transactional, idempotent, or explicitly recoverable.
- Strengthen the public contract so invalid states are harder to express.
- Add focused tests around the behavior that would fail before the remedy.

Do not recommend broad rewrites when a smaller boundary correction would solve the issue. Do recommend a larger redesign when local patches would entrench the problem.

## Evidence Gathering

Inspect enough context to make the review defensible:

- Changed files and hunks.
- Public API boundaries touched by the diff.
- Nearby callers, implementations, tests, fixtures, and configuration when relevant.
- Existing local patterns before recommending a new abstraction.
- Failure paths, cancellation paths, persistence/migration paths, concurrency boundaries, and protocol/state-machine transitions when the diff touches them.

When a significant finding needs broader exploration and subagents are available, launch a narrowly scoped subagent to locate patterns, callers, ownership boundaries, or test locations. Ask for evidence and remedy options, not a final verdict. Do not use subagents for local, obvious fixes.

## Language Lenses

Apply the relevant checks without turning them into a rote checklist.

For C++:
- Ownership and lifetime clarity, RAII, const-correctness, move/copy behavior, API boundaries, expected-error handling, thread safety, and resource cleanup.
- Watch for hidden global state, invalid references, weak type boundaries, exception mismatch, unsafe casts, and logging or diagnostics that hide failure causes.

For Rust:
- Ownership model, borrowing shape, trait boundaries, error types, async/cancellation behavior, unnecessary cloning, allocation pressure, and unsafe isolation.
- Watch for broad enums, leaky traits, stringly typed state, swallowed errors, panic-prone paths, and concurrency assumptions not enforced by types.

For Python:
- Type clarity, API shape, dependency boundaries, async/resource cleanup, testability, import side effects, and hidden global state.
- Watch for broad exception handling, mutable defaults, ad hoc parsing, unclear None/error semantics, monkeypatch-heavy designs, and slow paths in hot code.

## Test Strategy

Always critique test coverage in proportion to risk.

For small refactors, it is acceptable to say existing tests appear sufficient if the diff preserves behavior and the evidence supports that.

Be stricter for protocol logic, state machines, parsing, persistence, migrations, concurrency, security, authorization, public APIs, error handling, and cross-module behavior. Check whether tests cover the behavior users depend on, not just happy paths or implementation details.

## Approval Bar

Recommend approval only when the diff is correct, maintainable, locally idiomatic, and tested in proportion to risk.

Request changes when the diff:

- Adds avoidable complexity to a shared or long-lived path.
- Expands an already large file or function without improving ownership boundaries.
- Introduces state, fallback, compatibility, retry, migration, or async behavior without proving failure paths.
- Weakens type, API, or module boundaries.
- Relies on hidden ordering, global state, partial updates, or undocumented caller obligations.
- Leaves important behavior untested when the risk is more than local and mechanical.

## Output Format

Use this structure every time:

1. **Findings**

   List findings first, ordered by severity. For each finding include:
   - Severity: `Critical`, `High`, `Medium`, or `Low`.
   - Location: precise file and line when available.
   - Impact: what can break or become harder to maintain.
   - Evidence: the concrete code behavior or diff fact.
   - Remedy: the smallest credible fix, plus larger redesign only if justified.
   - Test note: what test should prove the fix, or why existing tests are enough.

   If there are no findings, say that clearly and do not invent minor issues.

2. **Test Strategy**

   Summarize coverage gaps, missing edge cases, and commands run or not run.

3. **Open Questions**

   Include only questions that materially affect review confidence or remedy choice.

4. **Summary**

   Keep this brief and secondary to the findings.
