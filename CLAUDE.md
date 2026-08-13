# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repo is

`wai` is a **single-plugin Claude Code marketplace**, serving two roles at once:

- The **marketplace**, `.claude-plugin/marketplace.json`, the catalog read by `/plugin marketplace add github.com/<owner>/wai`. One plugin advertised.
- The **plugin**, `plugins/wai/`, a personal toolkit of skills and agents, owned and edited here. Installed via `/plugin install wai@wai`.

Content is **inspired by** [mattpocock/skills](https://github.com/mattpocock/skills), [humanlayer's `.claude/`](https://github.com/humanlayer/humanlayer/tree/main/.claude), and others credited in `SOURCES.md`, but every artifact is rewritten. There is no upstream sync; this repo is the source of truth.

Vocabulary (artifact, port, merge, graft, roster, pointer, axis, gate, spine, sediment) is defined in [CONTEXT.md](./CONTEXT.md). Read it before writing anything that uses those words.

## Layout

`ls` shows the tree. What it does not show:

- `plugins/wai/skills/<name>/SKILL.md` is every `/name` shortcut, model- or user-invoked. There is no `commands/` directory: Claude Code treats `commands/*.md` and `skills/<name>/SKILL.md` as one component type, and only the latter carries sibling reference files. The lint fails if `commands/` reappears.
- `plugins/wai/agents/` is flat, one file per agent. Reference material belonging to an agent lives beside the skill that owns the subject.
- `plugins/wai/{server,ui,vendor,scripts}/` and three of the hooks are Diffscape, the one engine exception, documented in `plugins/wai/DIFFSCAPE.md`. It is not a precedent for porting other engine-backed plugins.
- `reports/` is untracked, like `plans/`: usage-audit counts are per-machine.

## Conventions

- **Skill frontmatter:** `name`, `description` (required); `allowed-tools`, `argument-hint`, `inspired-by` (as applicable).
- **Agent frontmatter:** `name`, `description`, `tools`; `skills:` preloads a skill's full body at agent startup. Do not list `Skill` in `tools` for that.
- **Invocation is a per-skill choice.** A skill another artifact preloads or invokes (`rigorous-pr-review`, `codebase-design`, `tdd`, `to-questionnaire`) must stay model-invocable, or the preload silently breaks. Otherwise set `disable-model-invocation: true` where an accidental autonomous fire is expensive or hard to undo: `implement-plan`, `fix-findings`, `setup`, `local-review`, `resume-handoff`. A user-invoked skill may only be *suggested* to the model, never named as a dispatch target: hooks, agent bodies, and other skills must route to something the model can actually reach.
- **Writes stay the user's.** A model-invocable skill that mutates shared state or reaches outside the machine takes its approval from a user turn, never from a calling agent. With no user turn, print the exact command and stop (`spec-registry` writes, `describe-pr`'s `gh pr create`).
- **Reference skills by bare name** (`rigorous-pr-review`), not scoped. Agent dispatch is the exception, since `subagent_type` resolves scoped.
- **Every ported artifact** carries `inspired-by` in frontmatter and a matching row in `SOURCES.md`. Both, always: they are how future-you diff-checks upstream.
- **Writing standard:** the `writing-for-agents` skill governs every document here. Read it before adding or reworking one.
- **Voice:** direct, opinionated, conversational. Short paragraphs. Name files and line numbers. Avoid filler ("delve", "crucial", "robust", "nuanced"). ALL-CAPS guardrails only where a specific anti-pattern needs blocking.
- **Fork and own.** Port the *idea* from upstream, never a script that pulls files in, and never a verbatim vendored file.
- **gstack stays separate.** It lives at `~/.claude/skills/gstack/` with its own update path. Do not move its content here or reference its paths.
- **No machine-specific paths** in artifacts. Use `${CLAUDE_PLUGIN_ROOT}`.

## Adding an artifact

1. Pick a name in *your* taste, not the upstream's. Slash names collide globally, so check gstack and installed plugins first (gstack owns `/ship`, `/qa`, `/review`, `/investigate`).
2. Write `skills/<name>/SKILL.md` or `agents/<name>.md` with the frontmatter above.
3. Add the `SOURCES.md` row and the `INDEX.md` line.
4. Run `scripts/check-index.sh`.
5. Re-install with `/plugin uninstall wai@wai && /plugin install wai@wai`, or restart Claude Code.

## Scripts

```
scripts/check-index.sh    # INDEX.md + SOURCES.md provenance vs the tree; exit 1 = drift
scripts/usage-audit.sh    # roster vs real transcripts, dated report under reports/
```

Run the lint after adding or removing an artifact. Run the audit **before any roster strip**, read its disk-artifact table before the invocation counts, and diff it against the previous report rather than reading one alone.

These two are the only executables here. The repo has no toolchain by design: no `package.json`, no build script, no test runner, nothing to `npm test`. Both exemptions lint or measure the repo against itself rather than building it, which is where the line sits. See `docs/adr/0006`.

## Install for development

```
/plugin marketplace add .          # from the repo root
/plugin install wai@wai
```
