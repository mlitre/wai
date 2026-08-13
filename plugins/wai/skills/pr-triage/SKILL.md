---
name: pr-triage
description: Single action-oriented table of the user's open GitHub PRs, authored plus review-assigned, with a per-PR "action on me?" verdict. Use when the user asks about their PR queue, what is blocked, what is ready to land, or what reviews they owe. Prefer it over hand-rolled `gh` commands.
---

# PR triage

Single-pane view of the user's open GitHub PRs with a concrete "what do I do next?" verdict per row.

## When to use

The user wants a status digest of their open PRs. Typical phrasings:
- "Summarize my open PRs"
- "What's the status of all my PRs?"
- "What PRs do I need to review?"
- "Give me a table of my pull requests with action items"
- "What's on my plate?"

If the user only wants a single PR's status, skip this skill, run `gh pr view <num>` directly.

## What the skill does

1. Resolves the user's GitHub login via `gh api user`.
2. Lists open PRs the user authored.
3. Lists open PRs where the user is BOTH a requested reviewer AND an assignee (the intersection, required-and-assigned, not either-or).
4. For every PR, fetches `reviewDecision`, `mergeable`, `mergeStateStatus`, `isDraft`, and the `statusCheckRollup`.
5. Renders one markdown table sorted by urgency, with an explicit "Action on me?" column.

## How to invoke

Run the bundled script. It does everything in one shot:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/skills/pr-triage/scripts/pr_triage.py
```

Flags:
- `--login <user>`, triage a different user's PRs (defaults to the gh-authenticated user)
- `--no-drafts`, exclude draft PRs from the table
- `--json`, emit raw JSON instead of markdown (use when post-processing)

Paste the script's stdout into the reply as-is. The script already sorts and formats the table; do not reorder or rewrite columns unless the user asks.

## Verdict semantics

The "Action on me?" column is the whole point of this skill. The script uses the following rules, keep them stable so the user can rely on the verdict.

Author role:
- `CHANGES_REQUESTED` → **YES, address feedback** (append "+ CI" if any CI failed, "+ rebase" if `DIRTY`).
- CI failure → **YES, fix CI** (append "+ rebase" if `DIRTY`; append "undraft" if draft).
- `DIRTY` merge state → **YES, rebase**.
- `mergeable=UNKNOWN` + `mergeStateStatus=UNKNOWN` → **YES, rebase** (GitHub has not computed mergeability, usually means stale base).
- `mergeStateStatus=CLEAN` → **YES, ready, merge or ping** (approved or no protection blocking; user decides whether to merge or chase a reviewer).
- Otherwise (typically `REVIEW_REQUIRED` + `BLOCKED` with CI green or pending) → **no, waiting reviewer**.

Reviewer+assignee role:
- `CHANGES_REQUESTED` already on the PR → **YES, re-review or ping** (author may have pushed fixes; or they're stalled and need a nudge).
- Otherwise → **YES, review**.

## Output expectations

- Single markdown table. No prose summary above it unless the user asked a follow-up question.
- The tally line at the bottom (`**Tally:** N on you, M waiting on others.`) stays.
- If the user asks to refresh the table after some PRs change, just re-run the script, GitHub is the source of truth, not the prior turn's output. State changes between turns are normal (CI finishes, mergeability gets recomputed, reviewers approve); call them out only if the user asks what changed.

## Caveats

- `mergeStateStatus` requires gh 2.x and the GraphQL field of the same name. Older gh versions will surface a "Unknown JSON field" error, the user should upgrade rather than dropping the column.
- `gh search prs --review-requested=<user> --assignee=<user>` is the strict intersection. If the user later wants the looser "either reviewer OR assignee" semantics, add a flag rather than changing the default, the strict semantics are the whole point of the second list.
- The script trusts whatever gh login is active. If the user wants someone else's queue, pass `--login`.
- No GitHub PR comments are ever posted by this skill, it is read-only on remote state.
