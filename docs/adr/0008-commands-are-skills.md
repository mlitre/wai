# Commands are skills, and invocation is a per-skill choice

`plugins/wai/commands/` is deleted. Every `/name` shortcut is now `plugins/wai/skills/<name>/SKILL.md`, and whether the model may fire one autonomously is set per skill with `disable-model-invocation`.

The plugin reference is explicit that these were never two things: *"Plugins add skills to Claude Code, creating `/name` shortcuts that you or Claude can invoke. Location: `skills/` or `commands/` directory in plugin root."* `disable-model-invocation` is documented as applying to plugin skills **and** commands. This session's own context confirmed it from the other side: every wai command was listed to the model under "skills available for use with the Skill tool", beside the actual skills. So the directory carried no behavior, only two capability differences that ran the other way, since a `commands/*.md` is a single flat file that cannot hold sibling reference material or a `scripts/` directory.

Two rules replace the directory split:

1. A skill that another artifact preloads or invokes must stay model-invocable, or the reference silently breaks. `rigorous-pr-review` is preloaded by `code-reviewer`; `codebase-design`, `tdd`, and `to-questionnaire` are reached by other skills.
2. Otherwise, set `disable-model-invocation: true` where an accidental autonomous fire is expensive or hard to undo. Five qualify: `implement-plan` and `fix-findings` fan out subagents that write code, `setup` and `local-review` have one-shot side effects on a repo, and `resume-handoff` takes over the session's direction.

## Considered Options

Keeping the split as documentation of intent was the status quo, and it was the strongest argument against this change: a file's location is the cheapest signal a future reader gets, and `CLAUDE.md`, `INDEX.md`, and `check-index.sh` all encoded it. Rejected because the signal was false. It implied a behavioral difference that does not exist, while hiding the one that does, and three artifacts had already grown wrapper commands whose entire content was "invoke the same-named skill."

Moving everything to `commands/` instead was rejected outright: only `skills/<name>/` supports the sibling reference files that `rigorous-pr-review`, `codebase-design`, `grill-me`, `tdd`, and `writing-for-agents` all depend on.

Leaving every skill model-invocable, the convention written earlier the same day, was rejected once the merge made it load-bearing. It had been generalized from the narrow preload constraint in rule 1 into a blanket ban, which would have made `implement-plan` autonomously firable for the first time.

## Consequences

Three merges came with the move. `to-spec` and `setup` lost pure wrapper commands, their flags folded into `## Arguments` sections. `diagnose` was different: its command owned the entire `--from-ci` mode, roughly 80 lines that appeared nowhere in the skill, so deleting it would have deleted the feature. It became a second input mode instead, matching the shape `wai-implementer` and `wai-spec-reviewer` already use.

Making previously user-only artifacts model-invocable moved a guarantee that used to come free. `spec-registry` and `describe-pr` both said "confirm with the user" at a time when only a human could invoke them; a calling agent can now be what confirms. Both were re-gated on a user turn, which narrowed ADR-0003.

The rule that a user-invoked skill can only be suggested, never named as a dispatch target, was learned by breaking it: the `general-purpose` nudge hook kept routing to `/fix-findings` after it became user-invoked, so the nudge dead-ended into the fallback it exists to prevent.

`check-index.sh` fails if `commands/` reappears, since nothing else would notice a stray file that still registers a working `/name`.

Two frontmatter fields ride along unverified: `model:` on `create-plan` and `iterate-plan`, and `argument-hint` on four skills. Neither is documented for skills. `argument-hint` was made non-load-bearing by writing `## Arguments` sections; `model: opus` is the open one, and if skills ignore it those two run on the session model.
