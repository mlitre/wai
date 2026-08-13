# wai workflow

Canonical engineering workflow shipped with the wai plugin. Source of truth for what runs in what order, what each step produces, and which side paths exist.

`/setup` does **not** copy this spine into project memory. It writes a three-line pointer to `CLAUDE.local.md` between marker comments:

```
<!-- wai-workflow-start -->
...
<!-- wai-workflow-end -->
```

The pointer names no commands, so editing this file can never leave a repo's memory stale. See [docs/adr/0004](../../docs/adr/0004-spine-is-a-pointer-in-claude-local-md.md).

## Spine

```
/setup                  one-time per repo, writes .claude/wai.json
  ↓
/create-plan            emits a DAG (T<n> + depends_on)
  ↓
/implement-plan         DAG walk, parallel up to wai.json parallel_cap,
                        TDD always, per-task spec + quality review,
                        retry-once → quarantine on failure
  ↓
/ds                     diffscape browser review
  ↓
/describe-pr            writes .claude/pr-descriptions/<branch-slug>.md,
                        then offers to run `gh pr create` (never pushes)
  ↓
cleanup-worktrees       after merge; recommended cadence: weekly or post-merge
```

Two other entry points feed the same implementation step:

| Entry | Produces | Feeds |
|---|---|---|
| `/diagnose` | `plans/<date>-diagnose-<slug>.md` | `/create-plan`, or `cavecrew-builder` if the fix is trivial |
| `to-spec` | `specs/<slug>.md` (local file only) | `/create-plan` |

## Two implementation drivers

`/implement-plan` and `/fix-findings` are the same fan-out machine with different parsers. Both dispatch `wai-implementer` → `wai-spec-reviewer` → `code-reviewer` per item, parallel up to `parallel_cap`, retry-once then quarantine.

| Command | Input | Ordering |
|---|---|---|
| `/implement-plan` | DAG: `### T<n>` headings + `depends_on:` lines | Topological, respects dependencies |
| `/fix-findings` | Flat numbered list: handoff doc, review output, diagnosis report | No dependencies, fully parallel |

Use `/fix-findings` when you have a list of independent findings and no plan. It exists because that shape was previously handled by ad-hoc `general-purpose` dispatch. See [docs/adr/0001](../../docs/adr/0001-wai-implementer-accepts-freeform-tasks.md).

## INVARIANT, code lands in three places

Every step before implementation (`to-spec`, `/create-plan`, `/iterate-plan`, `/diagnose`) investigates, designs, plans, or decomposes. None of them write source files.

Source files are written by exactly three things:

- `/implement-plan` and `/fix-findings`, via the `wai-implementer` agent.
- `wai-implementer` dispatched directly in freeform mode, for one-off "investigate and fix this" work.
- `cavecrew-builder`, 1-2 file mechanical edits (typos, renames). No `Bash`, so it cannot build or test.

## Outward actions

wai takes one outward-facing action, and only behind an explicit per-invocation confirmation: `/describe-pr` may run `gh pr create --body-file`. It never runs `git push`; if the branch is not on the remote it stops and says so. See [docs/adr/0003](../../docs/adr/0003-describe-pr-creates-prs-but-never-pushes.md).

## Side paths

| Path | When |
|---|---|
| `grill-me` | Stress-test a plan or design. Engages docs mode when `CONTEXT.md` exists: challenges the glossary, updates it inline, offers ADRs when `docs/adr/` exists. |
| `handoff` ↔ `/resume-handoff` | Compact session into a handoff doc; the next session reads, verifies, plans, resumes. A handoff's numbered findings feed `/fix-findings`. |
| `/iterate-plan` | Surgical edits to an existing plan given new feedback. |
| `/local-review <user>:<branch>` | Set up a worktree from a colleague's branch. Then `code-reviewer` → `/ds <base>` → manual `gh pr review`. |
| `pr-triage` | Status digest of authored + review-assigned PRs, with a per-PR "action on me?" verdict. |
| `improve-codebase-architecture` | Independent architectural review, informed by `CONTEXT.md` and `docs/adr/`. HTML report of deepening candidates. |
| `create-standards-checker` / `/spec-registry` | Generate a domain-specialised compliance agent; maintain `.claude/compliance-specs.json`. |
| `commit` | Conventional Commits for the session's changes. |

## Subagent surface

`code-reviewer` is the single review surface. It runs as the quality gate inside `/implement-plan` and `/fix-findings`, and stands alone for ad-hoc review. It self-dispatches `silent-failure-hunter` / `pr-test-analyzer` / `comment-analyzer` / `type-design-analyzer` per heuristic.

Implementation: `wai-implementer` (DAG task or freeform), `wai-spec-reviewer` (pass/fail against spec), `cavecrew-builder` (surgical edits).

Investigation: `codebase-analyzer` (how code works, `file:line` traces), `web-search-researcher` (sourced external research).

Override any of them locally by dropping a same-named agent in `.claude/agents/`; Claude Code gives local agents precedence.

A `PreToolUse` hook nudges toward this roster when `general-purpose` is dispatched. It warns and allows; it does not block. See [Hooks](#hooks) below and [docs/adr/0002](../../docs/adr/0002-nudge-not-block-on-general-purpose.md).

## Hooks

Workflow-level hooks the plugin registers in `hooks/hooks.json`. Diffscape's three hooks are documented separately in [DIFFSCAPE.md](./DIFFSCAPE.md).

| Piece | Trigger | Role |
|---|---|---|
| `PreToolUse` hook, `hooks/nudge-general-purpose.sh` | Before each `Task` / `Agent` call | Reads `tool_input.subagent_type`; when it is `general-purpose`, prints the wai roster as a `systemMessage` and allows the call |

The nudge is advisory by design. It always exits 0, never exits 2, and fails open: no `jq`, empty stdin, or unparseable payload all exit 0 with no output, so a bad payload can never stall an agent dispatch. A hard deny was rejected in [docs/adr/0002](../../docs/adr/0002-nudge-not-block-on-general-purpose.md), the work would just move into the main thread, which costs more context than the delegation it replaced.

The message maps the common shapes onto `wai-implementer` (freeform), `codebase-analyzer`, the built-in `Explore`, `code-reviewer`, `web-search-researcher`, `/fix-findings`, and `cavecrew-builder`, and says plainly that `general-purpose` is still right when the task needs the full toolbelt across many phases.

## Configuration

Per-repo config lives in `.claude/wai.json`. Shape:

```json
{
  "context_md": "docs/CONTEXT.md",
  "adr_dir": "docs/adr",
  "parallel_cap": 3
}
```

Actual consumers, verified against the tree:

| Field | Read by |
|---|---|
| `parallel_cap` | `/implement-plan`, `/fix-findings` |
| `context_md` | `setup` (writes), `grill-me` and `improve-codebase-architecture` (docs mode) |
| `adr_dir` | `setup` (writes), `grill-me` (ADR offers) |

There are no tracker fields. wai does not mirror plans to an issue tracker.

## Cadence

| Job | When |
|---|---|
| `/setup` | once per repo on adoption; `/setup --update` whenever this file's pointer format changes |
| `cleanup-worktrees` | weekly or after a PR merges |
| `pr-triage` | start of each work block |
