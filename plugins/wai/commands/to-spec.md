---
description: Explicit invocation surface for the `to-spec` skill. Produces a spec via interview or synthesize mode. Default writes a local file under `specs/`; `--tracker` publishes a PRD issue.
argument-hint: "[--interview|--synthesize] [--tracker]"
---

# To Spec

Invoke the `to-spec` skill. Mode and target flags pass through.

## Usage

```
/to-spec                     # asks interview|synthesize on first turn, writes specs/<date>-<slug>.md
/to-spec --interview         # force interview mode
/to-spec --synthesize        # force synthesize mode (uses current conversation context)
/to-spec --tracker           # publish PRD issue to tracker instead of local file
/to-spec --synthesize --tracker
```

## Behavior

Invoke the `to-spec` skill. Skill handles mode prompting, scope sanity check, the question loop, design presentation, spec template, self-review, and the user-approval gate.

`--tracker` reads `tracker_repo` + `labels.prd` from `.claude/wai.json`. Requires `/setup` to have run.

## Workflow position

```
prototype → to-spec → /create-plan → to-issues → /implement-plan → ...
```

See `plugins/wai/WORKFLOW.md`.
