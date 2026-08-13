# wai-implementer accepts freeform tasks, not just DAG task IDs

A usage audit of 711 transcripts found 141 dispatches to the built-in `general-purpose` agent against 86 to `wai-implementer`, and the labels showed why: most real work is "investigate this and fix it", not "execute task T4 from a plan". Every wai agent refused that shape, `wai-implementer` because it required a `T<n>` ID, `cavecrew-builder` because it hard-refuses 3+ files and has no `Bash`. We gave `wai-implementer` a second input mode that takes a plain task description while keeping the TDD invariant and the diff-plus-test-output receipt.

## Considered Options

Adding a tenth agent for investigate-and-fix was rejected: `wai-implementer` already grants the exact toolset those dispatches needed (`Bash, Read, Edit, Write, Grep, Glob`) and has 86 proven dispatches, so a new agent would have duplicated a working one and added a third editing surface to disambiguate.

Widening `cavecrew-builder` instead was rejected because its bounded-scope, cheap-caveman-receipt contract is the entire point of the agent, and caveman output is wrong for build and test logs.

## Consequences

`wai-implementer` no longer has a single input contract, so its prompt carries a mode branch. `/implement-plan` continues to pass DAG task IDs and is unaffected; the freeform mode is what `/fix-findings` and ad-hoc dispatch use.
