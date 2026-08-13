# writing-for-agents replaces write-a-skill, and governs the always-loaded surface only

`write-a-skill` is deleted. `writing-for-agents` takes its place, covering every document an agent consumes rather than skills alone, and its rules are applied retroactively to exactly one tier: the material that sits in context on every turn, which is `CLAUDE.md` and the `description` line of each artifact. The 27 artifact bodies are left alone.

The replaced skill was procedure ("gather requirements, ask the user five questions, draft"). The 2026-08-13 audit found the owner bypassing wai skills exactly where they were procedure on top of a one-liner, and found an opinionated standards document beating an orchestration one 10-0. The incoming document is a standards document about the genre this entire repo consists of.

## Considered Options

Keeping both was rejected: two documents about how to write a skill is two sources of truth for one meaning, which is the failure the incoming document itself names.

A full retroactive pass over all 27 bodies was rejected on the document's own economics. Always-loaded lines cost tokens and attention every turn; bodies cost only when their pointer fires. The audit measured usage rather than prose quality, and none of the survivors were cut for being badly written, so a full rewrite is churn against artifacts currently earning their place.

Authoring-only, with no retroactive pass at all, was rejected because of what the audit found: `general-purpose` was dispatched more than every wai agent combined, which is a weak-pointer problem in the agent descriptions. The nudge hook (ADR-0002) treats the symptom. Auditing the pointers treats the cause, and the two compose.

## Consequences

Three things the old skill carried have no home in upstream's body and were grafted rather than dropped: the capture-intent-from-conversation opener, the description trap, and the progressive-disclosure loading table. Everything else skill-specific moved into the disclosed `SKILL-MECHANICS.md`, so nothing was lost in the swap.

The bodies of existing artifacts now predate the standard that governs new ones, and will read inconsistently with it until they are touched for other reasons. That is accepted: consistency is not worth a rewrite of documents that work. Whether the pointer audit actually moves the `general-purpose` number is measurable with `scripts/usage-audit.sh` (ADR-0006), and the pre-port baseline for that comparison was taken on 2026-08-13, recording 147 cumulative `general-purpose` dispatches across 750 transcripts. Reports live under `reports/`, which is untracked like `plans/`: the numbers are per-machine, so the baseline is recorded here rather than committed.
