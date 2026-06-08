---
description: Orchestrator ops for the wai-queue inter-agent task queue. `init` scaffolds the CLI into your environment; `add`/`status`/`result`/`cancel` enqueue and inspect tasks. Pairs with `/queue-worker` and the `queue` skill.
argument-hint: "[init | add <prompt> | status | result <id> | cancel <id>]"
---

# Queue

Orchestrator side of the inter-agent task queue. Invoke the `queue` skill for the contract and the `/queue init` scaffold; for everything else this is a thin wrapper over the `wai-queue` CLI.

## Usage

```
/queue init                                  # scaffold $WAI_QUEUE_DIR/bin/wai-queue + state dirs (runs the skill)
/queue add <prompt>                          # enqueue; prints the task id
/queue add --cwd <dir> --priority <0-99> --agent <type> --needs <id,...> <prompt>
/queue status                                # per-state counts + one line per task
/queue result <id>                           # print a done/failed task's result.md
/queue cancel <id>                           # remove a not-yet-running task
```

Under the hood these shell out to `wai-queue <subcommand>` (the CLI `/queue init` installed at `$WAI_QUEUE_DIR/bin/wai-queue`). `add` flags: `--cwd` (where the task's subagent works, default `$PWD`), `--priority` (`0-99`, lower = higher, default `50`), `--agent` (subagent type, default `general-purpose`), `--needs` (DAG deps — claimed only once all are `done/`). `<prompt>` of `-` reads stdin.

## Behavior

- `init` runs the `queue` skill: copies the canonical CLI from `${CLAUDE_PLUGIN_ROOT}/skills/queue/wai-queue.sh` into `$WAI_QUEUE_DIR/bin/wai-queue` (atomic, detect-then-ask before overwrite) and creates the state dirs.
- The queue on disk is the single source of truth; this session holds no queue state. Results are read on demand (`status` / `result`), not pushed.
- To actually run the tasks, start one or more workers with `/queue-worker` (in separate sessions). They're race-safe, so run as many as you want.

## Workflow position

```
/queue init → /queue add ... → /queue-worker (drains) → /queue status / result
```

See `plugins/wai/skills/queue/SKILL.md`.
