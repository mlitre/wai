---
description: Bootstrap a repo for the wai workflow, writes `.claude/wai.json`, writes the pointer block into `CLAUDE.local.md`, excludes it via `.git/info/exclude`, opt-in scaffolds `CONTEXT.md` + `docs/adr/`. `--update` refreshes the pointer only.
argument-hint: "[--update]"
---

# Setup

Explicit invocation surface for the `setup` skill. Use when adopting wai in a new repo, or on a repo still carrying the old enumerated spine block.

## Usage

```
/setup            # full bootstrap, walks prompts, writes config + pointer + git exclude
/setup --update   # refresh the pointer, clear legacy blocks, leave config alone
```

## Behavior

Invoke the `setup` skill. The skill handles state detection, prompting, atomic writes, the marker-comment pointer, and the `.git/info/exclude` top-up.

`--update` mode: skip all prompts. Rewrite the pointer block between `<!-- wai-workflow-start -->` / `<!-- wai-workflow-end -->` in the project's `CLAUDE.local.md`, and remove any legacy marker block left behind in `CLAUDE.md`. Do not touch `.claude/wai.json`.

## After it finishes

The skill asks you to confirm `CLAUDE.local.md` actually loaded (run `/memory`, look for scope `Local`), then suggests one next step:

1. **`create-standards-checker`**, if the repo audits code against a written spec (protocols, RFCs, design docs, regulatory documents), generate a domain-specialized `<domain>-standards-compliance-checker` agent. Walks you through the registry seed + writes the agent + `.claude/compliance-specs.json`.
