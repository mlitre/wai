---
name: claude-automation-recommender
description: Analyze a codebase and recommend Claude Code automations (hooks, subagents, skills, plugins, MCP servers). Use when the user asks for automation recommendations, wants to optimize their Claude Code setup, mentions improving Claude Code workflows, or asks how to first set up Claude Code for a project.
tools: Read, Glob, Grep, Bash
inspired-by: anthropic/claude-code-setup/skills/claude-automation-recommender
---

# Claude Automation Recommender

Analyze codebase patterns and recommend tailored Claude Code automations across all extensibility surfaces.

**Read-only.** Outputs recommendations. Does not create or modify files. The user implements them, or asks Claude separately to help build them.

## Output guidelines

- **1-2 of each type by default.** Surface the top 1-2 most valuable automations per category. Don't overwhelm.
- **Type-specific requests get more.** If the user asks "show me more MCP servers", give 3-5 in that category.
- **Go beyond the references.** The reference docs in this skill cover common patterns. Use web search for recommendations specific to the codebase's tools, frameworks, libraries.
- **Tell the user they can ask for more.** End the report by noting which categories they can drill into.
- **Note when wai already provides it.** Many recommendations (PR review agents, hooks docs, security patterns, conversation analyzer, etc.) already ship in this `wai` plugin, point that out instead of re-recommending the upstream.

## Automation types

| Type | Best for |
|------|----------|
| **Hooks** | Automatic actions on tool events (format on save, lint, block edits). |
| **Subagents** | Specialized reviewers / analyzers that run in parallel. |
| **Skills** | Packaged expertise, workflows, repeatable tasks. Invoked by Claude or user via `/skill-name`. |
| **Plugins** | Collections of skills + agents + commands + hooks. |
| **MCP servers** | External tool integrations (databases, APIs, browsers, docs). |

## Workflow

### Phase 1, codebase analysis

```bash
# Detect project type and tools
ls -la package.json pyproject.toml Cargo.toml go.mod pom.xml 2>/dev/null
head -50 package.json 2>/dev/null

# Dependencies that inform MCP server recommendations
grep -E '"(react|vue|angular|next|express|fastapi|django|prisma|supabase|stripe)"' package.json 2>/dev/null

# Existing Claude Code config
ls -la .claude/ CLAUDE.md 2>/dev/null

# Project structure
ls -la src/ app/ lib/ tests/ components/ pages/ api/ 2>/dev/null
```

**Indicators to capture:**

| Category | Look for | Informs |
|----------|----------|---------|
| Language / framework | `package.json`, `pyproject.toml`, import patterns | hooks, MCP servers |
| Frontend stack | React / Vue / Angular / Next.js | Playwright MCP, frontend skills |
| Backend stack | Express / FastAPI / Django | API documentation tools |
| Database | Prisma / Supabase / raw SQL | Database MCP servers |
| External APIs | Stripe / OpenAI / AWS SDKs | context7 MCP for docs |
| Testing | Jest / pytest / Playwright configs | testing hooks, subagents |
| CI/CD | GitHub Actions / CircleCI | GitHub MCP server |
| Issue tracking | Linear / Jira references | issue-tracker MCP |
| Docs patterns | OpenAPI / JSDoc / docstrings | documentation skills |

### Phase 2, generate recommendations

Reference files in this skill:

- [`references/mcp-servers.md`](references/mcp-servers.md), MCP server patterns by codebase signal.
- [`references/skills-reference.md`](references/skills-reference.md), skill recommendations.
- [`references/hooks-patterns.md`](references/hooks-patterns.md), hook configurations.
- [`references/subagent-templates.md`](references/subagent-templates.md), subagent templates.
- [`references/plugins-reference.md`](references/plugins-reference.md), official + community plugins.

#### MCP server quick map

| Codebase signal | MCP server |
|-----------------|------------|
| Uses popular libs (React, Express, etc.) | **context7**, live docs |
| Frontend with UI testing | **Playwright**, browser automation |
| Supabase | **Supabase MCP** |
| PostgreSQL / MySQL | **Database MCP** |
| GitHub repository | **GitHub MCP**, issues, PRs, actions |
| Linear | **Linear MCP** |
| AWS | **AWS MCP** |
| Slack | **Slack MCP** |
| Memory / context persistence | **Memory MCP** |
| Sentry | **Sentry MCP** |
| Docker | **Docker MCP** |

#### Skills quick map

| Codebase signal | Skill | Already in wai? |
|-----------------|-------|-----------------|
| Building plugins / skills | `write-a-skill` | ✓ wai |
| Git commits | `commit` skill | ✓ wai |
| React / Vue / Angular | `frontend-design` | (separate plugin, future port candidate) |
| Hook authoring | `writing-native-hooks`, `writing-hookify-rules` | ✓ wai |
| Security patterns | `security-patterns` | ✓ wai |
| Plan + execute | `/create-plan`, `/implement-plan`, `subagent-driven-mode` (uses `using-subagents` primer) | ✓ wai |
| Debug | `diagnose` | ✓ wai |
| TDD | `tdd` | ✓ wai |

Custom skills to recommend creating in `.claude/skills/<name>/SKILL.md`:

| Codebase signal | Skill to create | Invocation |
|-----------------|-----------------|------------|
| API routes | `api-doc` (OpenAPI template) | both |
| Database project | `create-migration` (validation script) | user-only |
| Test suite | `gen-test` (example tests) | user-only |
| Component library | `new-component` (templates) | user-only |
| PR workflow | `pr-check` (checklist) | user-only |
| Releases | `release-notes` (git context) | user-only |
| Code style | `project-conventions` | Claude-only |
| Onboarding | `setup-dev` (prereq script) | user-only |

#### Hooks quick map

| Codebase signal | Hook |
|-----------------|------|
| Prettier configured | `PostToolUse`: auto-format on edit |
| ESLint / Ruff configured | `PostToolUse`: auto-lint on edit |
| TypeScript project | `PostToolUse`: type-check on edit |
| Tests directory exists | `PostToolUse`: run related tests |
| `.env` files present | `PreToolUse`: block `.env` edits |
| Lock files present | `PreToolUse`: block lock-file edits |
| Security-sensitive code | `PreToolUse`: require confirmation (or use wai's `security-patterns` recipe) |

#### Subagent quick map

| Codebase signal | Subagent | Already in wai? |
|-----------------|----------|-----------------|
| Large codebase (500+ files) | `code-reviewer`, parallel review | ✓ wai |
| Auth / payments code | `security-reviewer`, security audits | partial (`code-reviewer` + `security-patterns`) |
| API project | `api-documenter`, OpenAPI generation |, |
| Performance-critical | `performance-analyzer` |, |
| Frontend-heavy | `ui-reviewer`, a11y review |, |
| Needs more tests | `test-writer`, `pr-test-analyzer` | ✓ wai (`pr-test-analyzer`) |
| Error-handling audit | `silent-failure-hunter` | ✓ wai |
| Type design | `type-design-analyzer` | ✓ wai |
| Comment audit | `comment-analyzer` | ✓ wai |
| Code simplification | `code-simplifier` | ✓ wai |

#### Plugins quick map

| Codebase signal | Plugin |
|-----------------|--------|
| General productivity | `anthropic-agent-skills`, or `wai` (this plugin) |
| Document workflows | docx, xlsx, pdf skills |
| Frontend development | `frontend-design` |
| Building AI tools | `mcp-builder` |

### Phase 3, output report

**Only 1-2 recommendations per category**, the most valuable ones for this codebase. Skip categories that aren't relevant. Mark anything already in wai.

```markdown
## Claude Code Automation Recommendations

### Codebase profile
- **Type**: [language / runtime]
- **Framework**: [framework]
- **Key libraries**: [libs detected]

---

### MCP servers

#### context7
**Why**: [specific reason from detected libs]
**Install**: `claude mcp add context7`

---

### Skills

#### [skill name]
**Why**: [specific reason]
**Create**: `.claude/skills/[name]/SKILL.md`
**Invocation**: user-only / both / Claude-only
**Already in wai**: yes / no, if yes, no action needed.

---

### Hooks

#### [hook name]
**Why**: [specific reason from detected config]
**Where**: `.claude/settings.json`

---

### Subagents

#### [agent name]
**Why**: [specific reason]
**Where**: `.claude/agents/[name].md`

---

**Want more?** Ask for additional recommendations for any category.
**Want help implementing?** Just ask.
```

## Decision framework

### When to recommend an MCP server

- External service integration (databases, APIs).
- Documentation lookup for libraries / SDKs.
- Browser automation or testing.
- Team tool integration (GitHub, Linear, Slack).
- Cloud infrastructure management.

### When to recommend a skill

- Document generation (docx, xlsx, pptx, pdf, also in plugins).
- Frequently repeated prompts or workflows.
- Project-specific tasks with arguments.
- Applying templates or scripts to tasks.
- Quick actions invoked with `/skill-name`.
- Workflows that should run in isolation (`context: fork`).

Invocation control:

- `disable-model-invocation: true`, user-only (for side effects: deploy, commit, send).
- `user-invocable: false`, Claude-only (background knowledge).
- Default, both.

### When to recommend a hook

- Repetitive post-edit actions (formatting, linting).
- Protection rules (block sensitive file edits).
- Validation checks (tests, type checks).

### When to recommend a subagent

- Specialized expertise needed (security, performance).
- Parallel review workflows.
- Background quality checks.

### When to recommend a plugin

- Need multiple related skills.
- Want pre-packaged automation bundles.
- Team-wide standardization.

## Configuration tips

### MCP server setup

- **Team sharing**, check `.mcp.json` into the repo.
- **Debugging**, `--mcp-debug` flag.
- **Prerequisites**, GitHub CLI (`gh`) for GitHub ops, Puppeteer / Playwright CLI for browser MCPs.

### Headless mode

Recommend headless Claude for automated pipelines:

```bash
# Pre-commit hook
claude -p "fix lint errors in src/" --allowedTools Edit,Write

# CI pipeline
claude -p "<prompt>" --output-format stream-json | your_command
```

### Permissions for hooks

Configure allowed tools in `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": ["Edit", "Write", "Bash(npm test:*)", "Bash(git commit:*)"]
  }
}
```
