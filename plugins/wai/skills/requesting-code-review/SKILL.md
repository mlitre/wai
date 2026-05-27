---
name: requesting-code-review
description: Dispatches a code-reviewer subagent with crafted context, for completed tasks, major features, or pre-merge gating. Builds on the `using-subagents` primer for prompt-craft + verification; this skill is just the review-specific dispatch wrapper.
inspired-by: github.com/obra/superpowers/skills/requesting-code-review
---

# Requesting Code Review

Catch issues before they cascade. This skill is the review-specific dispatch wrapper, the general "why subagents" framing and prompt-craft rules live in the `using-subagents` primer, not duplicated here.

**Core principle:** review early, review often.

## When to request review

Mandatory:

- After completing a major feature.
- Before merge to main.
- After a non-trivial refactor.

Optional but valuable when you want a one-shot reviewer outside the `/implement-plan` flow (which has its own per-task `wai-spec-reviewer` + `code-reviewer` chain). For a full multi-agent PR audit, use `/review-pr` instead, this skill is for ad-hoc single-pass review.

Optional but valuable:

- When stuck, fresh perspective.
- Before refactoring, baseline check.
- After fixing a complex bug.

## How to request

**1. Get the git range:**

```bash
BASE_SHA=$(git rev-parse HEAD~1)   # or origin/main
HEAD_SHA=$(git rev-parse HEAD)
```

**2. Dispatch the reviewer subagent.** Use the `Task` / `Agent` tool with the `general-purpose` type and fill the template at [`code-reviewer.md`](./code-reviewer.md) (sibling file).

Placeholders in the template:

- `{DESCRIPTION}`, brief summary of what you built.
- `{PLAN_OR_REQUIREMENTS}`, what it should do (plan path, task text, requirements).
- `{BASE_SHA}`, starting commit.
- `{HEAD_SHA}`, ending commit.

**3. Act on feedback:**

- Fix critical issues immediately.
- Fix important issues before proceeding.
- Note minor issues for later.
- Push back with technical reasoning if the reviewer is wrong.

## Reviewer

`requesting-code-review` is the *skill* for dispatching a one-shot reviewer in long workflows (after a task, before merge). It pairs with the `code-reviewer` agent (Opus, 0-100 confidence-scored). Pick the output mode based on what you want:

- Full audit, grouped narrative → `code-reviewer` in verbose mode (default).
- Quick scannable signal → `code-reviewer` in compressed mode (ask for "caveman" / "compressed" / "/caveman-review"). One-line-per-finding with severity emoji.

The sibling `code-reviewer.md` prompt template here is structured for the `code-reviewer` agent.

## Integration

- `using-subagents`, primer (prompt-craft, model selection, verification).
- `/implement-plan`, has its own per-task review chain (`wai-spec-reviewer` + `code-reviewer`); this skill is for non-plan-context reviews.
- `/review-pr`, full multi-agent PR audit (code, tests, comments, errors, types, simplify). Use that for pre-merge gates; use this skill for one-shot mid-feature checks.

## Red flags

Never:

- Skip review because "it's simple".
- Ignore critical issues.
- Proceed with unfixed important issues.
- Argue with valid technical feedback.

If the reviewer is wrong, push back with technical reasoning, show code/tests that prove it works, request clarification. Never silently override.
