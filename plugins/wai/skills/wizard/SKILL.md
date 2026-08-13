---
name: wizard
description: Generate an interactive bash wizard that walks a human through steps only they can perform. Use when a task needs credentials, a third-party dashboard, infrastructure provisioning, CI secrets, hardware setup, or a one-off migration or cutover that the agent cannot execute itself.
allowed-tools: Read, Write, Bash, Grep, Glob
inspired-by:
  - mattpocock/skills/engineering/wizard
---

# Wizard

Some steps are yours to work out and someone else's to perform: the credential you must not hold, the dashboard only a human can click, the cutover that needs a person watching it. Narrating those into a chat window loses them the moment the session scrolls.

Emit a **runnable bash wizard** instead. The agent does the thinking, the human does the doing, at their own pace, with state that survives closing the terminal.

This is the reusable form of a boundary the rest of wai applies case by case: `describe-pr` stops before the push, `diagnose` stops before the fix, `local-review` stops before the verdict.

## When it fits

The step is human-only for one of these reasons, and the reason belongs in the wizard's preamble so the operator knows why they are in the loop:

- **Secret handling.** Credentials, API keys, CI secrets. The agent must not see or store the value.
- **Out-of-band UI.** A vendor console, a hardware setup flow, a physical device.
- **Judgment at the moment of action.** A cutover or migration where someone has to watch and decide to continue.

If none of these hold, do the work directly instead of generating a wizard about it.

## Shape of the generated script

```bash
#!/usr/bin/env bash
set -euo pipefail
```

Requirements the generated script must meet:

- **Resumable.** Record completed steps to a state file next to the script. On start, read it and skip what is done. A wizard that cannot survive a closed laptop will not be finished.
- **One step, one screen.** Print what to do, why it matters, and what to look for when it worked. Then wait for the operator.
- **Verify each step where verification is possible.** After the human acts, check it: hit the endpoint, read back the config, `gh secret list`, whatever confirms the state. Fail loudly and stop rather than advancing on an unverified step.
- **Never echo secrets.** Read them with `read -rs`, pass them onward without printing, and never write them to the state file or the shell history.
- **Idempotent where it can be.** Re-running a completed step should detect that and move on rather than duplicating a resource.
- **Every step reversible or flagged.** If a step cannot be undone, say so on screen before the prompt, not after.

## Process

1. Establish the goal and the end state the operator should be able to verify.
2. List the steps. Split those the agent can do from those it cannot, and do the agent's half now rather than putting it in the wizard.
3. Generate the script, plus a one-paragraph header comment saying what it provisions and what it will ask for.
4. Do not run it. Hand the operator the path and the first command. Running it is the point of the boundary.
