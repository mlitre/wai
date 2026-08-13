# The general-purpose PreToolUse hook warns, it does not block

`general-purpose` outnumbered every wai agent combined (141 dispatches), and there is no settings knob to disable a built-in agent, so the only enforceable mechanism is a `PreToolUse` hook on `Agent`/`Task`. We made that hook print the wai roster and allow the call rather than deny it.

## Considered Options

Hard-denying `general-purpose` was rejected as a wall with no door. A share of those dispatches genuinely need Read, Edit, Write, Bash and Grep in one agent; if the hook denies and no wai agent accepts the shape, the work moves into the main thread instead, which costs more context than the delegation it replaced. ADR-0001 builds the door, but a nudge is reversible and a block is the kind of friction that gets hooks deleted wholesale.

## Consequences

The hook is advisory, so the 141-to-0 imbalance may persist. That is acceptable: the measurement that produced this decision is repeatable, and if the nudge does not move the numbers the hook can be tightened later with the freeform `wai-implementer` already in place as the fallback.
