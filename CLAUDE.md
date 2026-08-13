# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`wai` is a **single-plugin Claude Code marketplace**. The repo serves two roles at once:

- The **marketplace** (`.claude-plugin/marketplace.json` at the root), the catalog Claude Code reads when a user runs `/plugin marketplace add github.com/<owner>/wai`. One plugin advertised: `wai` (general toolkit).
- The **plugin**, `plugins/wai/`, personal toolkit of skills, agents, and commands, owned and edited here. Installed via `/plugin install wai@wai`.

Domain-specific compliance work (EV charging, payments, internal RFCs, ...) is **not** a separate plugin anymore. The `create-standards-checker` skill generates domain-specialised agents per repo on demand; the registry CLI (`/spec-registry`) maintains the shared `.claude/compliance-specs.json`. See the skill + command for details.

Content is **inspired by** [mattpocock/skills](https://github.com/mattpocock/skills) and [humanlayer's `.claude/`](https://github.com/humanlayer/humanlayer/tree/main/.claude), but every artifact is rewritten for personal use. There is no upstream sync, this repo is the source of truth.

## Layout

```
wai/
├── .claude-plugin/marketplace.json     # marketplace catalog
├── plugins/wai/
│   ├── .claude-plugin/plugin.json      # plugin manifest
│   ├── skills/<name>/SKILL.md          # description-activated skills
│   ├── agents/<name>.md                # subagent definitions
│   ├── commands/<name>.md              # slash commands
│   ├── WORKFLOW.md                     # canonical workflow spine
│   ├── INDEX.md                        # per-artifact catalog (linted by scripts/check-index.sh)
│   ├── DIFFSCAPE.md                    # diffscape feature doc (engine exception)
│   ├── hooks/                          # nudge-general-purpose.sh + diffscape hooks
│   ├── scripts/                        # diffscape: server start/stop + tests
│   ├── server/                         # diffscape: Node review server
│   ├── ui/                             # diffscape: single-page review UI
│   └── vendor/                         # diffscape: diff2html + highlight.js
├── scripts/check-index.sh              # lints plugins/wai/INDEX.md vs artifact tree
├── docs/adr/                           # decision records for the plugin itself
├── archive/                            # superseded artifacts, kept for reference
├── README.md, SOURCES.md, LICENSE
```

## Conventions

- **Skill frontmatter:** `name`, `description` (required); `allowed-tools`, `inspired-by` (recommended).
- **Agent frontmatter:** `name`, `description`, `tools`.
- **Command frontmatter:** `description`; optional `model`, `inspired-by`.
- **Every ported artifact** carries an `inspired-by` line in its frontmatter pointing at the upstream path, AND a corresponding row in `SOURCES.md`. Both are required. Future-you uses these to diff-check upstream when looking for new ideas.
- **Voice:** mattpocock-style hybrid, direct, opinionated, conversational. Short paragraphs. Name files and line numbers. Avoid filler ("delve", "crucial", "robust", "nuanced"). Don't use ALL-CAPS guardrails unless a specific anti-pattern needs blocking.
- **No upstream sync.** This is a "fork-and-own" toolkit. If mattpocock or humanlayer ships a great new artifact, port the *idea*, never run a script that pulls files in.
- **gstack stays separate.** The third-party gstack framework lives at `~/.claude/skills/gstack/` with its own update path. Do not move gstack content into this repo, and do not reference gstack paths from wai artifacts.

## When adding a new artifact

1. Pick a name in *your* taste, not the upstream's. Slash commands collide globally, check gstack and installed plugins first (e.g., gstack already owns `/ship`, `/qa`, `/review`, `/investigate`).
2. Create the file under the right directory with the required frontmatter.
3. Add `inspired-by: <upstream-path>` to frontmatter if applicable.
4. Add a row to `SOURCES.md` with link + a note on what changed in the rewrite.
5. Re-install with `/plugin uninstall wai@wai && /plugin install wai@wai` (or just restart Claude Code, caches refresh on session start).

## Lint

After adding/removing skills, agents, or commands, run:

```
scripts/check-index.sh
```

Exit 0 = `plugins/wai/INDEX.md` matches the tree. Exit 1 = drift; fix the index.

## What NOT to do

- Do not write a `package.json`, build script, or test runner. The repo has no toolchain by design, these are markdown files read by Claude at runtime.
- Do not invent `bun run ...`, `npm test`, etc. There is nothing to run.
- Do not vendor upstream files verbatim. Anything in this repo is your own writing.
- Do not include machine-specific absolute paths (`/Users/mlitre/...`, `~/.gstack/...`) in artifacts. Use `${CLAUDE_PLUGIN_ROOT}` for plugin-relative paths if you ever need filesystem references.

### Diffscape exception

`plugins/wai/` ships one engine-backed feature: **Diffscape**, a browser-based code-review UI (`/ds`). It brings a Node review server, three hooks, two shell scripts, vendored `diff2html` + `highlight.js`, and a single-page UI. Imported from the standalone `diffscape` plugin at the owner's request; documented in `plugins/wai/DIFFSCAPE.md` and `SOURCES.md`. **The only approved engine break from the markdown-only rule.** Do not use it as precedent for porting other engine-backed plugins, markdown-fork-own is still the default.

Diffscape ops:

```
plugins/wai/scripts/start-server.sh   # boot review server
plugins/wai/scripts/stop-server.sh    # shut down
plugins/wai/scripts/tests/            # smoke tests
```

## Install for development

Install from GitHub:

```
/plugin marketplace add github.com/<owner>/wai
/plugin install wai@wai
```

Local dev: `/plugin marketplace add .` from the repo root, then `/plugin install wai@wai`.
