---
description: Run a multi-agent PR review. Dispatches the right specialized agents based on what changed (code, tests, comments, error handling, types), then aggregates findings into one action plan.
argument-hint: "[aspect ...] | [parallel]"
allowed-tools:
  - Bash
  - Glob
  - Grep
  - Read
  - Task
inspired-by: anthropic/pr-review-toolkit/commands/review-pr.md
---

# Review PR

Review using specialized agents, each focused on one aspect of code quality.

**Aspects (optional):** `$ARGUMENTS`

## Workflow

1. **Determine scope.**
   - `git status` + `git diff --name-only` to identify changed files.
   - Check for an open PR: `gh pr view` (may not exist).
   - Parse `$ARGUMENTS` for specific aspects; default to "all applicable".

2. **Available aspects:**

   | Aspect | Agent | Triggers when |
   |--------|-------|---------------|
   | `code` | `code-reviewer` | always applicable |
   | `tests` | `pr-test-analyzer` | test files changed |
   | `comments` | `comment-analyzer` | comments / docstrings added or modified |
   | `errors` | `silent-failure-hunter` | error handling changed |
   | `types` | `type-design-analyzer` | new or modified types |
   | `simplify` | `code-simplifier` | run after the others, polish pass |
   | `all` | all applicable | default |

   > `code-reviewer` now auto-dispatches the same 4 specialists on a heuristic. `/review-pr` invokes them directly for predictable parallel coverage on a full PR diff, so we suppress the auto-dispatch with `dispatch: none` to avoid duplicate runs. When constructing the `code-reviewer` prompt below, include the literal token `dispatch: none` as a suffix line.

3. **Pick applicable reviews from the diff.**

   Build the list of agents to dispatch from the file types and content of the changes. Don't run every agent on every PR, only those whose triggers match. `code-reviewer` always applies (with the dispatch suffix per the note above).

4. **Dispatch.**

   Default: **sequential**, one agent at a time. Easier to act on, each report complete before the next starts. Good for interactive review.

   On request (`parallel` in `$ARGUMENTS`): **parallel**, launch all agents in the same response. Faster, results return together.

   ### Parallel pattern

   When dispatching agents in the same response, follow the `using-subagents` primer's prompt-craft rules:

   - **Focused**, one aspect per agent (don't ask `code-reviewer` to also analyze tests).
   - **Self-contained**, paste the relevant diff range, file paths, and `CLAUDE.md` highlights into each agent's prompt. They don't share your context.
   - **Specific output**, name the report shape you want (issues + `file:line` + severity + fix). "Review the diff" is too broad.
   - **No interference**, agents are read-only by tool-allowlist, so they won't step on each other's files, but they can still draw contradictory conclusions about the same change. Cross-check in step 5 aggregation.

   See the `using-subagents` primer for the canonical prompt example and common-mistakes table.

5. **Aggregate** the agents' reports into a single summary:

   ```markdown
   # PR Review Summary

   ## Critical issues (X)
   - [agent]: issue + `file:line`

   ## Important issues (X)
   - [agent]: issue + `file:line`

   ## Suggestions (X)
   - [agent]: suggestion + `file:line`

   ## Strengths
   - what's well-done

   ## Recommended action
   1. Fix critical issues first.
   2. Address important issues.
   3. Consider suggestions.
   4. Re-run targeted reviews after fixes.
   ```

## Usage

```
/review-pr                       # all applicable reviews, sequential
/review-pr tests errors          # only test coverage + error handling
/review-pr comments              # only comments
/review-pr simplify              # simplification pass (run after the rest)
/review-pr all parallel          # all agents in parallel
```

## Workflow integration

**Before committing:**

1. Write code.
2. `/review-pr code errors`
3. Fix critical issues.
4. Commit.

**Before opening a PR:**

1. Stage changes.
2. `/review-pr` (default = all applicable).
3. Address critical and important.
4. Re-run targeted reviews to verify.
5. Open PR.

**After PR feedback:**

1. Make requested changes.
2. Targeted review based on feedback.
3. Verify issues resolved.
4. Push.

## Notes

- Agents run autonomously and return detailed reports.
- Each agent specializes for deep analysis on one dimension.
- Results are actionable with `file:line` references.
- The simplification agent is for polish, run it *after* the others have approved the changes, not before.
