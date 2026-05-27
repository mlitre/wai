---
description: Bootstrap a repo for the wai workflow, writes `.claude/wai.json`, injects WORKFLOW spine into `CLAUDE.md`, opt-in scaffolds `CONTEXT.md` + `docs/adr/`. `--update` re-injects spine only.
argument-hint: "[--update]"
---

# Setup

Explicit invocation surface for the `setup` skill. Use when adopting wai in a new repo or after editing `plugins/wai/WORKFLOW.md`.

## Usage

```
/setup            # full bootstrap, walks prompts, writes config, injects spine
/setup --update   # re-inject WORKFLOW spine into CLAUDE.md, leave config alone
```

## Behavior

Invoke the `setup` skill. The skill handles state detection, prompting, atomic writes, and the marker-comment injection.

`--update` mode: skip all prompts. Read current `plugins/wai/WORKFLOW.md`, regenerate the spine block, replace whatever is currently between `<!-- wai-workflow-start -->` / `<!-- wai-workflow-end -->` in the project's `CLAUDE.md`. Do not touch `.claude/wai.json`.

## After it finishes

The skill suggests two next steps:

1. **`claude-automation-recommender`**, surfaces stack-specific MCP servers, hooks, and other automations. Run once per project.
2. **`create-standards-checker`**, if the repo audits code against a written spec (protocols, RFCs, design docs, regulatory documents), generate a domain-specialized `<domain>-standards-compliance-checker` agent. Walks you through the registry seed + writes the agent + `.claude/compliance-specs.json`.
