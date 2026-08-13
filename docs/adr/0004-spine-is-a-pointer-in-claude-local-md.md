# The workflow spine is a pointer in CLAUDE.local.md, not a step list in CLAUDE.md

`setup` used to inject an enumerated 11-step spine into the project `CLAUDE.md` between marker comments. That produced a per-repo copy of content that is byte-identical everywhere, so it rotted: `everest-core/CLAUDE.md` was still advertising `/research-codebase`, `to-issues`, `/validate-plan` and `/review-pr` after those were cut. `setup` now writes a three-line pointer (this repo uses wai, config in `.claude/wai.json`, canonical spine in the plugin's `WORKFLOW.md`) into `CLAUDE.local.md`, and adds the wai personal-file patterns to `.git/info/exclude`.

## Considered Options

A single unscoped `~/.claude/rules/wai-workflow.md`, mirroring `git-policy.md`, was rejected in favour of keeping the marker in the repo it applies to.

Deleting the injection entirely was rejected: a pointer is cheap and marks a repo as wai-adopted, even though skill descriptions already do the actual routing.

## Consequences

The block names no commands, so plugin changes can no longer make a repo's memory wrong. `CLAUDE.local.md` is verified loaded by Claude Code 2.1.231 (scope label `Local`), gated behind a `localSettings` capability check, so `setup` should confirm the file is actually picked up rather than assume it. `.git/info/exclude` is per-clone and does not survive a re-clone; it is shared across linked worktrees, so one write covers all of a repo's worktrees.
