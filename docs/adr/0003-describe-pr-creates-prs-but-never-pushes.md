# describe-pr may run gh pr create, but never git push

`WORKFLOW.md` originally ended at "manual push + `gh pr create`", and the audit showed the cost: 95 `gh pr create` invocations against 25 generated description files, so roughly 70 PRs opened without the description the skill had been built to write. `describe-pr` now offers to run `gh pr create --body-file` after an explicit confirmation, and stops with an instruction to push if the branch is not already on the remote.

## Considered Options

Printing a copy-pasteable command was the more conservative option and was rejected as insufficient: retyping is what caused the 70 skips in the first place.

## Consequences

This is a deliberate, narrow break in the rule that wai takes no outward-facing action. The split is between the two commands, not between confirmed and unconfirmed: `gh pr create` is offered behind a per-invocation confirmation, and `git push` remains outside the skill entirely because the global git policy requires one-off authorization for it. A future reader should not read this ADR as license to let wai push.
