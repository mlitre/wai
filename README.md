# WAI

Personal Claude Code toolkit, a single-plugin marketplace bundling skills, agents, and commands for engineering workflows.
Inspired by [mattpocock/skills](https://github.com/mattpocock/skills), [humanlayer's `.claude/`](https://github.com/humanlayer/humanlayer/tree/main/.claude), [obra/superpowers](https://github.com/obra/superpowers), and others, rewritten for personal use.
See [SOURCES.md](./SOURCES.md) for upstream credits.

## Why this over upstream

- **An opinionated workflow spine.** Every step from initial spec to merged PR is a single named command; the chain is documented in [`plugins/wai/WORKFLOW.md`](plugins/wai/WORKFLOW.md) and `/setup` drops a pointer to it in the project's `CLAUDE.local.md`.
- **Fork-and-own.** Nothing is vendored verbatim. Each artifact has been voice-passed, trimmed, or merged with siblings. No upstream sync, this repo is the source of truth.
- **Measured, not aspirational.** The roster is periodically checked against real transcripts and cut. The 2026-08-13 audit took it from 56 artifacts to 38 by deleting everything with no invocations and no output on disk. See the audit note at the end of [SOURCES.md](./SOURCES.md).
- **One explicit engine exception.** Everything is markdown only except [`ds` / Diffscape](plugins/wai/DIFFSCAPE.md), which ships a Node review server, three hooks, vendored JS, and shell scripts. The exception is documented and not generalized to other artifacts.

## Install

```
/plugin marketplace add github.com/mlitre/wai
/plugin install wai@wai
```

In `wai@wai`, the first `wai` is the plugin name; the second is the marketplace name.

## Quickstart

After installing, run inside any repo you want to use the workflow on:

```
/setup                  # one-time per-repo bootstrap
/create-plan            # produce a DAG plan
/implement-plan         # walk the DAG with reviewer-gated subagents
/ds                     # diffscape browser review
/describe-pr            # write .claude/pr-descriptions/<branch>.md,
                        # then offer `gh pr create` (you push, it never does)
cleanup-worktrees       # after merge
```

Two other ways in: `/diagnose` for a bug, `/to-spec` for a spec first. Got a flat list of findings rather than a plan? `/fix-findings` runs the same reviewer-gated chain with no dependency ordering.

Full chain, side paths, and per-step detail in [`plugins/wai/WORKFLOW.md`](plugins/wai/WORKFLOW.md).
Per-artifact one-liners in [`plugins/wai/INDEX.md`](plugins/wai/INDEX.md).
Engine exception (Diffscape) documented in [`plugins/wai/DIFFSCAPE.md`](plugins/wai/DIFFSCAPE.md).

## Repo layout

```
.claude-plugin/marketplace.json     marketplace catalog
plugins/wai/
  .claude-plugin/plugin.json        plugin manifest
  WORKFLOW.md                       canonical workflow spine
  INDEX.md                          per-artifact catalog
  DIFFSCAPE.md                      diffscape feature reference (engine exception)
  skills/<name>/SKILL.md            description-activated skills
  agents/<name>.md                  subagent definitions
  commands/<name>.md                slash commands
  hooks/                            general-purpose nudge + diffscape hooks
  server/, ui/, vendor/             diffscape runtime (engine exception)
docs/adr/                           decision records for the plugin itself
archive/                            superseded artifacts, kept for reference
```

## Adding new content

| Type | Where | Frontmatter required |
|---|---|---|
| Skill | `plugins/wai/skills/<name>/SKILL.md` | `name`, `description` (+ optional `allowed-tools`, `inspired-by`) |
| Agent | `plugins/wai/agents/<name>.md` | `name`, `description`, `tools` |
| Command | `plugins/wai/commands/<name>.md` | `description` (+ optional `model`, `inspired-by`) |

Add inspiration credit to `inspired-by` in frontmatter, a row in `SOURCES.md`, and a one-line entry in `plugins/wai/INDEX.md`. The `scripts/check-index.sh` lint flags artifacts present in the tree but missing from INDEX.

## License

MIT, see [LICENSE](./LICENSE).
