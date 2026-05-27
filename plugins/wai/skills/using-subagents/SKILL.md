---
name: using-subagents
description: Primer for dispatching subagents, how to craft focused prompts, pick the right model, avoid common mistakes, and verify what came back. Use whenever you're about to dispatch a Task/Agent subagent for any purpose. `/implement-plan` (DAG walker), `/research-codebase`, `/review-pr`, `/create-plan`, and `requesting-code-review` all build on this primer.
inspired-by: obra/superpowers/skills/dispatching-parallel-agents + obra/superpowers/skills/subagent-driven-development (MIT, Jesse Vincent)
---

# Using Subagents

## Why subagents

Delegate to specialized agents with isolated context. Craft their instructions precisely so they stay focused. Agents do not inherit your session history, you construct exactly what they need. This also preserves your context for coordination.

The trade-off you're making: spend a few minutes writing a tight prompt → save much more by not burning your context on the work, and by keeping the agent on-task instead of letting it drift the way you would inside a long session.

## How to write a focused subagent prompt

Three load-bearing properties:

1. **Focused**, one clear problem domain. Not "fix the tests"; "fix the 3 failing tests in `src/agents/agent-tool-abort.test.ts`".
2. **Self-contained**, paste every piece of context the agent needs. Error messages, test names, repro steps, file paths. Never say "you know where this code is."
3. **Specific about output**, what should the agent return? "Summary of root cause + changes" beats "fix it" every time. If you can't describe the output shape, the prompt isn't ready.

### Canonical example

```text
Fix the 3 failing tests in src/agents/agent-tool-abort.test.ts:

1. "should abort tool with partial output capture", expects 'interrupted at' in message
2. "should handle mixed completed and aborted tools", fast tool aborted instead of completed
3. "should properly track pendingToolCount", expects 3 results, gets 0

These are timing / race-condition issues.

Steps:
1. Read the test file and understand what each test verifies.
2. Identify root cause, timing or actual bug?
3. Fix by replacing arbitrary timeouts with event-based waiting, OR fixing the abort
   implementation, OR adjusting test expectations if behavior intentionally changed.

Do NOT just bump timeouts, find the real issue.

Return a summary of what you found and what you fixed.
```

Focused (one file). Self-contained (test names + symptoms + hypothesis). Specific output (summary of root cause + changes).

## Common mistakes

| Mistake | Effect | Fix |
|---|---|---|
| Too broad ("fix all the tests") | Agent gets lost, drifts into unrelated files. | Specify a file or subsystem. |
| No context ("fix the race condition") | Agent doesn't know where. | Paste error messages, test names, repro. |
| No constraints | Agent might refactor everything. | "Do not change production code" / "tests only". |
| Vague output expectation ("fix it") | You don't know what changed. | "Return summary of root cause + changes". |
| Sending the plan file | Agent loads the whole plan, burns its context on irrelevant tasks. | Paste only the task text + scene-setting context. |

## Model selection

Use the **least capable** model that can handle the task. Cost and speed compound, a bad model picks waste 10× more than the underlying API call.

| Task complexity | Model class |
|---|---|
| 1-2 files, complete spec, mechanical (rename, port, format) | Fast cheap model (Haiku-tier). |
| Multiple files, integration concerns, light judgment | Standard (Sonnet-tier). |
| Architecture, design, broad codebase understanding, hard debugging | Most capable (Opus-tier). |

Most well-specified tasks are mechanical. When in doubt, start cheap, escalate on `BLOCKED` or `NEEDS_CONTEXT` returns.

## Verification

After a subagent returns:

1. **Read the summary in full.** Don't skim, the agent may have flagged concerns or noted scope changes you need to integrate.
2. **Check for conflicts.** If you dispatched multiple agents that touched related files, did they step on each other?
3. **Run the suite.** Don't trust "tests pass" in the summary alone, re-run from your session.
4. **Spot-check the diff.** Agents can make systematic errors (wrong import path, wrong type used everywhere). Skim the actual changes.

The summary is the *agent's account* of what happened. Verification is *your account* of whether it's right.
