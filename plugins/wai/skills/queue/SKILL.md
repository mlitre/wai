---
name: queue
description: |
  Bash-backed inter-agent task queue. One orchestrator session enqueues tasks; one or more live `/loop` worker sessions claim them and run each task in a throwaway subagent, so the loop session's context never accumulates. The on-disk queue is the single source of truth — workers are disposable (clear/kill/restart any time). Atomic directory-`mv` claims make N workers race-safe; tasks carry cwd + priority + agent-type + DAG deps; failures retry then cascade-fail dependents; a reaper recovers work from dead workers. The CLI is scaffolded into the user's environment on first use, so this repo stays markdown-only.

  Use when:
  - User wants to hand work off to other agents via a queue ("queue up these tasks", "have a worker drain this", "set up an inter-agent task queue").
  - User asks how to run looped worker agents without their context filling up.
  - User says "/queue init", "enqueue a task", "start a queue worker", or asks to add/inspect queued tasks.
allowed-tools: Read, Write, Edit, Bash
---

# queue

A task queue two kinds of agent share. The **orchestrator** (your interactive session) enqueues tasks and reads results. **Workers** are `/loop` sessions that drain the queue, running each task in a fresh subagent. They never talk directly — they coordinate through a directory on disk.

> The CLI is `wai-queue` (subcommands: `init add status result cancel claim complete fail reap`). The canonical source lives in this skill at `wai-queue.sh`; `/queue init` copies it into your environment. This repo ships markdown — the bash is a generated user artifact, mirroring how `create-standards-checker` generates agents on demand.

## The one idea that makes this work

`/loop` reschedules the *same prompt into the same session*, so context **persists** across iterations — it does not auto-`/clear`. If a worker did task work inline, iteration N would drag the residue of tasks 1…N-1 until it bloats and compacts.

So the work never runs in the loop. Each tick the worker claims one task and **dispatches it to a fresh subagent**, whose context dies on return. The loop session keeps only a one-line ack per task. "Clearing context per task" is automatic, because the work was never in the loop's context to clear.

And because the **queue on disk is the single source of truth**, the worker holds no essential state. Clear it, kill it, restart it — a fresh worker resumes by reading the queue. When the loop session's thin acks pile up, wipe it; nothing is lost.

## Setup: `/queue init`

Scaffolds the CLI into the user's environment and creates the state dirs.

1. Resolve `WAI_QUEUE_DIR` (default `${XDG_DATA_HOME:-$HOME/.local/share}/wai/queue`).
2. Read the canonical CLI from `${CLAUDE_PLUGIN_ROOT}/skills/queue/wai-queue.sh`.
3. Write it to `$WAI_QUEUE_DIR/bin/wai-queue` **atomically** (write to `wai-queue.tmp`, then `mv`), and `chmod +x` it. **Detect-then-ask:** if `$WAI_QUEUE_DIR/bin/wai-queue` already exists, show the user it's there and ask before overwriting — never clobber silently.
4. Run `wai-queue init` to create `pending/ claimed/ done/ failed/ bin/`.
5. Tell the user the CLI path (`$WAI_QUEUE_DIR/bin/wai-queue`) and suggest adding `$WAI_QUEUE_DIR/bin` to `PATH` (or aliasing) so later sessions can call `wai-queue` directly.

## Enqueue (orchestrator)

```
wai-queue add [--cwd <dir>] [--priority <0-99>] [--agent <type>] [--needs <id,...>] <prompt|->
```

- `--cwd` — the directory the task's subagent works in. Lets one queue serve many repos. Default `$PWD`.
- `--priority` — `0-99`, lower = higher priority. Jumps the FIFO line. Default `50`.
- `--agent` — which subagent type runs it (e.g. `general-purpose`, `code-reviewer`). Default `general-purpose`.
- `--needs` — comma-separated task ids this task depends on. It won't be claimed until all of them are in `done/`.
- `<prompt>` — the task instructions; `-` reads stdin.

`add` prints the task id. Inspect with `wai-queue status`; read output with `wai-queue result <id>`; drop a not-yet-running task with `wai-queue cancel <id>`.

## Worker loop contract (each `/loop` tick)

A worker is a session running `/loop` (see `/queue-worker`). Every tick does exactly this:

1. `wai-queue reap` — return any stale/abandoned claims to `pending/` first.
2. `t=$(wai-queue claim)` — claim the next eligible task. **Nonzero exit = nothing claimable** → idle (back off, longer reschedule) and stop the tick.
3. Read `$t/meta.json` (`cwd`, `agent`, `id`) and `$t/prompt.md`.
4. **Dispatch one subagent** of type `meta.agent`, instructed to work in `meta.cwd`, with `prompt.md` as its task. Capture its final text. This is where the real work happens — in throwaway context.
5. Settle the task:
   - Success → store the captured text as the result. `complete` reads it from **stdin** (or from a file path via `--result-file <path>` — it is a path, not the text): `printf '%s' "$result" | wai-queue complete <id>`.
   - Failure → `wai-queue fail <id> --reason "<why>"`. **Failure** = the subagent died/returned nothing, **or** its result's first line is the sentinel `FAILED:` (task prompts should instruct subagents to emit `FAILED: <reason>` when they can't finish).
6. Reschedule. Keep only a one-line ack in the loop session.

`fail` retries until the task has been attempted `WAI_QUEUE_RETRIES` times (default 2 — i.e. one retry), then dead-letters to `failed/` and cascade-fails any dependents that can no longer run. `reap` counts toward the same budget, so a perpetually-stale task dead-letters rather than requeueing forever. `claim` enforces deps and is atomic, so you can run **many** worker sessions against one queue safely — throughput scales with how many you start.

## On-disk model (for debugging)

A task is a directory that moves between state dirs: `pending/<prio>-<id>/` → `claimed/<id>/` → `done/<id>/` or `failed/<id>/`. Each holds `prompt.md` + `meta.json`; `claimed/` adds `claim.json` (`{worker, ts}`); terminal states add `result.md`. State = which dir it's in. The priority prefix exists only in `pending/`.

## Environment

| Var | Default | Meaning |
|---|---|---|
| `WAI_QUEUE_DIR` | `${XDG_DATA_HOME:-$HOME/.local/share}/wai/queue` | Queue root. A second independent queue = a second value. |
| `WAI_QUEUE_RETRIES` | `2` | Max attempts before a task dead-letters. |
| `WAI_QUEUE_STALE` | `1800` | Seconds before `reap` reclaims a claim. Must exceed your longest single task, or a still-running task can be wrongly requeued. |
| `WAI_QUEUE_WORKER` | `$(hostname)-$$` | Worker identity stamped into `claim.json`. |

## Tests

`plugins/wai/scripts/tests/test-queue.sh` (run via `plugins/wai/scripts/tests/run-all.sh`) exercises the CLI deterministically — atomic-claim races, priority/DAG ordering, cascade-fail, the reaper — with no model needed, because the CLI itself never dispatches a subagent. Only the *worker* (a Claude session) does.
