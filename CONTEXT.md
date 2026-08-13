# Context

Glossary for this repo. Definitions only, no rules and no implementation detail: conventions live in `CLAUDE.md`, writing standards in the `writing-for-agents` skill, decisions in `docs/adr/`.

Use these terms exactly. When a term here and a term in a session disagree, the disagreement is the interesting part; resolve it and update this file in place.

## Repo shape

**Marketplace**
The catalog at `.claude-plugin/marketplace.json`, read by Claude Code when someone runs `/plugin marketplace add`. Advertises exactly one plugin.

**Plugin**
`plugins/wai/`, the thing that gets installed. Holds every artifact.

**Artifact**
One installable unit inside the plugin: a skill or an agent. Reference files (`SMELLS.md`, `DEEPENING.md`, `SKILL-MECHANICS.md`) are not artifacts, they are disclosed reference belonging to one.
*Avoid*: tool, module, item, command.

**Command**
Retired term. The plugin system treats `commands/*.md` and `skills/<name>/SKILL.md` as one component type, both registering a `/name` shortcut, so wai calls them all skills. Say **user-invoked skill** for one only the human can fire.

**Roster**
The full set of artifacts currently on disk. `INDEX.md` is its human-facing catalog, `scripts/check-index.sh` is what keeps the two honest.

## Provenance

**Port**
Rewrite an upstream artifact's substance into this repo's voice, as a new artifact. Never a copy: vendoring upstream files verbatim is not porting.

**Merge**
Fold an upstream artifact's substance into an artifact that already exists here, so no new roster entry appears.

**Graft**
Carry a piece of a wai artifact onto a replacement body, when the replacement does not cover it. What happened to the description trap when `write-a-skill` became `writing-for-agents`.

**Re-survey**
A pass over upstream repos looking for ideas worth porting. Manual and occasional, driven by the checklist at the end of `SOURCES.md`. Distinct from a sync, which this repo does not do.

**Usage audit**
A measurement of the roster against real transcripts, run by `scripts/usage-audit.sh`. Answers what gets used, never what is well written.

**Disk-artifact discriminator**
The rule that "did it leave files behind" outranks "was it invoked" when judging whether an artifact is alive. One-shot bootstrap artifacts fire once per repo and then look dead by invocation count alone.

**Sediment**
Stale material that accumulates because adding feels safe and removing feels risky. What the 56-to-38 strip was clearing.

## Documents

**User-invoked**
A skill with `disable-model-invocation: true`: only the human typing `/name` can fire it, and no other artifact can reach it. Costs no context load, spends cognitive load instead.

**Pointer**
A reference held in context that names out-of-context material and encodes when to reach it. A skill's `description` and a naming line in `CLAUDE.md` are the same object. Full treatment in `writing-for-agents`.

**Context load**
The cost of always-loaded material: pointers, `CLAUDE.md`. Paid every turn whether or not the material fires.

**Cognitive load**
The cost on the human of knowing which documents exist and when to reach for each.

**Disclosed reference**
Material pushed out of a main file and behind a pointer, loaded only when the pointer fires.

**Spine**
The canonical workflow this plugin ships, documented in `plugins/wai/WORKFLOW.md`. Projects hold a pointer to it in `CLAUDE.local.md`, never a copy.

## Review and execution

**Axis**
An independent dimension of review. Two exist: **Standards** (does this follow the repo's conventions and the smell baseline) and **Spec** (does this implement what was asked). Reported side by side, never merged. See ADR-0005.

**Gate**
A pass/fail check whose verdict drives control flow rather than informing a human. `wai-spec-reviewer` in plan mode is a gate; `code-reviewer` standalone is a report.

**DAG plan**
A plan written as `### T<n>` task headings with `depends_on:` lines, the only format `/implement-plan` parses.

**Quarantine**
What happens to a DAG task that fails review twice: the task stops, and its descendants are marked blocked.

## Code design

Deep-module vocabulary (**module**, **interface**, **implementation**, **depth**, **seam**, **adapter**, **leverage**, **locality**) is defined once in the `codebase-design` skill and deliberately not repeated here.
