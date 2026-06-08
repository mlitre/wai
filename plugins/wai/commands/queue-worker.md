---
description: Run a `/loop` worker that drains the wai-queue — reap → claim → dispatch a per-task subagent → complete/fail, then reschedule. Each task runs in throwaway context so the loop session never fills up; the worker is disposable.
argument-hint: "[--once]"
---

# Queue Worker

Turn this session into a queue worker. It runs a `/loop` whose body claims one task per tick and dispatches the actual work to a fresh subagent — so the loop's own context stays flat and the session can be cleared, killed, or restarted at any time without losing work (the queue on disk is the source of truth).

Requires `/queue init` to have been run (so `$WAI_QUEUE_DIR/bin/wai-queue` exists). Read `plugins/wai/skills/queue/SKILL.md` for the full contract.

## Usage

```
/queue-worker            # loop forever: drain, then idle-and-poll when the queue is empty
/queue-worker --once     # drain until the queue is empty, then stop (no idle loop)
```

Run it in **separate sessions** to scale throughput — claims are atomic, so N workers never grab the same task.

## The loop body (each tick)

1. `wai-queue reap` — return stale/abandoned claims to `pending/` first.
2. `t=$(wai-queue claim)` — claim the next eligible task. **Nonzero = nothing claimable:** with `--once`, stop; otherwise idle (longer reschedule) and end the tick.
3. Read `$t/meta.json` (`id`, `cwd`, `agent`) and `$t/prompt.md`.
4. **Dispatch exactly one subagent** of type `meta.agent`, told to work in `meta.cwd`, with `prompt.md` as its instructions. Capture only its final text. This is the only place real work runs — in context that dies on return.
5. Settle:
   - Success → pipe the captured text into `complete` via stdin: `printf '%s' "$result" | wai-queue complete <id>` (or `--result-file <path>` if you wrote it to a file — it's a path, not the text).
   - Failure → `wai-queue fail <id> --reason "<why>"`. Failure = the subagent died/returned nothing, or its result's first line is `FAILED:` (instruct task subagents to emit `FAILED: <reason>` when they can't finish).
6. Keep only a one-line ack in this session, then reschedule.

`fail` retries up to `WAI_QUEUE_RETRIES`, then dead-letters and cascade-fails dependents. Don't do task work inline, and don't accumulate task output in this session — offload to the subagent and write results through the CLI.

## Workflow position

```
/queue init → /queue add ... → /queue-worker (this) → /queue status / result
```

See `plugins/wai/skills/queue/SKILL.md`.
