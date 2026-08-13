---
description: Explicit invocation surface for the `to-spec` skill. Produces a spec via interview or synthesize mode. Writes a local file under `specs/`.
argument-hint: "[--interview|--synthesize]"
---

# To Spec

Invoke the `to-spec` skill. Mode flags pass through.

## Usage

```
/to-spec                     # asks interview|synthesize on first turn, writes specs/<date>-<slug>.md
/to-spec --interview         # force interview mode
/to-spec --synthesize        # force synthesize mode (uses current conversation context)
```

## Behavior

Invoke the `to-spec` skill. Skill handles mode prompting, scope sanity check, the question loop, design presentation, spec template, self-review, and the user-approval gate.

Specs are written as local files under `specs/`. wai does not publish to an issue tracker.

## Workflow position

```
to-spec → /create-plan → /implement-plan → ...
```

See `plugins/wai/WORKFLOW.md`.
