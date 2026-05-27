# wai workflow

Canonical engineering workflow shipped with the wai plugin. Source of truth for what runs in what order, what each step produces, and which side paths exist.

`/setup` reads this file and injects the spine summary into the project `CLAUDE.md` between marker comments:

```
<!-- wai-workflow-start -->
...
<!-- wai-workflow-end -->
```

Run `/setup --update` after editing this file to push the new spine into project `CLAUDE.md`.

## Spine

```
/setup                  one-time per repo, writes .claude/wai.json
  ↓
/research-codebase      map an unfamiliar codebase (read-only)
  ↓
to-spec                 local file by default; --tracker writes a PRD issue
  ↓
/create-plan            emits a DAG (T<n> + depends_on)
  ↓
to-issues               per-plan opt-in, mirrors DAG to GH Issues
  ↓
/implement-plan         subagent-driven, parallel up to wai.json parallel_cap,
                        TDD always, per-task spec + quality review,
                        retry-once → quarantine on failure
  ↓
/validate-plan          runs the plan's automated success criteria
  ↓
/review-pr              multi-agent audit
  ↓
/ds                     diffscape browser review
  ↓
/describe-pr            writes .claude/pr-descriptions/<branch-slug>.md
                        (no push, no gh pr edit)
  ↓
git push + gh pr create (MANUAL)
  ↓
cleanup-worktrees       after merge; recommended cadence: weekly or post-merge
```

## INVARIANT, code only in `/implement-plan`

Every step before `/implement-plan` (`/research-codebase`, `to-spec`, `/create-plan`, `/iterate-plan`, `/diagnose`) investigates, designs, plans, or decomposes. None of them write source files.

The two carve-outs:

- `prototype`, throwaway exploration code in a `prototypes/` dir; deleted before `to-spec`.
- `cavecrew-builder`, 1-2 file mechanical edits triggered by user request (typos, renames). Bypasses the planning chain by design.

## Side paths

| Path | When |
|---|---|
| `prototype` | Pre-`to-spec` exploration. Logic mode = terminal app; UI mode = multi-variant route. Output is throwaway. |
| `/diagnose` | Bug intake. Default mode takes a bug description; `--from-ci <pr>` ingests GitHub Actions logs. Writes `plans/<date>-diagnose-<slug>.md`. Trivial fix → `cavecrew-builder`. Non-trivial → `/create-plan` against the diagnosis. |
| `handoff` ↔ `/resume-handoff` | Compact session into a handoff doc; the next session reads, verifies, plans, resumes. |
| `/local-review <user>:<branch>` | Set up a worktree from a colleague's branch. Then `/review-pr <pr#>` → `/ds <base>` → manual `gh pr review`. |
| `pr-triage` | Status digest of authored + review-assigned PRs. |
| `issue-triage` | Issue tracker state-machine triage. |
| `improve-codebase-architecture` | Independent architectural review. HTML report of deepening candidates. |
| `zoom-out` | Higher-level map of an unfamiliar area. Auto-fires on "give me a map" / "I don't know this area". |

## Subagent surface

Three agents do the work for `/implement-plan`:

- `wai-implementer`, implements one DAG task. TDD Iron Law as invariant.
- `wai-spec-reviewer`, checks implementer output against task spec. Pass/fail only.
- `code-reviewer`, runs after spec-reviewer passes. Checks duplication, error handling, naming, CLAUDE.md compliance. Self-dispatches `silent-failure-hunter` / `pr-test-analyzer` / `comment-analyzer` / `type-design-analyzer` per heuristic for deeper coverage.

Override locally by dropping a same-named agent in `.claude/agents/`, Claude Code's plugin system gives local agents precedence.

`requesting-code-review` skill stays for non-plan-context reviews (ad-hoc gut checks, pre-refactor baseline). It dispatches the standalone `code-reviewer` agent.

`/review-pr` orchestrates 6 review-toolkit agents on a full PR diff: code-reviewer, pr-test-analyzer, comment-analyzer, silent-failure-hunter, type-design-analyzer, code-simplifier.

## Configuration

Per-repo config lives in `.claude/wai.json`. Shape:

```json
{
  "tracker": "github",
  "tracker_repo": "<owner>/<repo>",
  "labels": {
    "prd": "type:prd",
    "task": "type:task"
  },
  "context_md": "docs/CONTEXT.md",
  "adr_dir": "docs/adr",
  "parallel_cap": 3
}
```

Skills that read this config: `to-spec`, `to-issues`, `issue-triage`, `/create-plan`, `/implement-plan`, `zoom-out`, `improve-codebase-architecture`, `grill-me`.

## Cadence

| Job | When |
|---|---|
| `/setup` | once per repo on adoption; `/setup --update` whenever this WORKFLOW.md changes |
| `cleanup-worktrees` | weekly or after a PR merges |
| `claude-md` audit | quarterly or when CLAUDE.md feels stale |
| `pr-triage` | start of each work block |
