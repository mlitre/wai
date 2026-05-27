---
name: write-a-skill
description: Create new agent skills with proper structure, progressive disclosure, and bundled resources. Use when user wants to create, write, or build a new skill.
inspired-by:
  - mattpocock/skills/productivity/write-a-skill
  - obra/superpowers/skills/writing-skills
  - anthropic/skill-creator/skills/skill-creator
---

# Writing Skills

## Process

1. **Capture intent.** Before asking, scan the current conversation. If the user has been doing the workflow they want to skill-ify ("turn this into a skill"), the substance is already in front of you, tools used, sequence, corrections, input/output formats. Extract that first, ask only what's missing. Confirm with the user before drafting.

2. **Gather requirements** - ask user about:
   - What task/domain does the skill cover?
   - What specific use cases should it handle?
   - Does it need executable scripts or just instructions?
   - Any reference materials to include?

3. **Draft the skill** - create:
   - SKILL.md with concise instructions
   - Additional reference files if content exceeds 500 lines
   - Utility scripts if deterministic operations needed

4. **Review with user** - present draft and ask:
   - Does this cover your use cases?
   - Anything missing or unclear?
   - Should any section be more/less detailed?

## Skill Structure

```
skill-name/
├── SKILL.md           # Main instructions (required)
├── REFERENCE.md       # Detailed docs (if needed)
├── EXAMPLES.md        # Usage examples (if needed)
└── scripts/           # Utility scripts (if needed)
    └── helper.js
```

## SKILL.md Template

```md
---
name: skill-name
description: Brief description of capability. Use when [specific triggers].
---

# Skill Name

## Quick start

[Minimal working example]

## Workflows

[Step-by-step processes with checklists for complex tasks]

## Advanced features

[Link to separate files: See [REFERENCE.md](REFERENCE.md)]
```

## Description Requirements

The description is **the only thing your agent sees** when deciding which skill to load. It's surfaced in the system prompt alongside all other installed skills. Your agent reads these descriptions and picks the relevant skill based on the user's request.

**Goal**: Give your agent just enough info to know:

1. What capability this skill provides
2. When/why to trigger it (specific keywords, contexts, file types)

**Format**:

- Max 1024 chars
- Write in third person
- First sentence: what it does
- Second sentence: "Use when [specific triggers]"

**Good example**:

```
Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when user mentions PDFs, forms, or document extraction.
```

**Bad example**:

```
Helps with documents.
```

The bad example gives your agent no way to distinguish this from other document skills.

### The description trap: do not summarize the workflow

The description should describe **triggering conditions only**. Do not summarize the skill's process, steps, or workflow in the description.

When a description summarises the workflow, Claude follows that summary and skips reading the body. Real example: a skill description said "code review between tasks", Claude did one review, even though the body required two (spec compliance → code quality). When the description was changed to *"Use when executing implementation plans with independent tasks"* (no workflow leak), Claude read the body and did both reviews.

```yaml
# BAD: summarizes workflow → Claude follows the summary
description: Use when executing plans, dispatches subagent per task with code review between tasks

# BAD: process detail in the description
description: Use for TDD, write test first, watch it fail, write minimal code, refactor

# GOOD: triggering conditions only
description: Use when executing implementation plans with independent tasks in the current session

# GOOD: trigger + symptoms, no workflow
description: Use when tests have race conditions, timing dependencies, or pass/fail inconsistently
```

Rule of thumb: if your description tells Claude *how* the skill works, rewrite it to describe *when* the skill applies. The body is for *how*. The description is for *should I open this?*

### Pushy descriptions for undertriggering

Claude tends to *undertrigger* skills, to not invoke them when they'd help. Counter this in the description with explicit trigger language. "Make sure to use this skill whenever the user mentions X, Y, or Z, even if they don't ask for it by name."

```yaml
# WEAK: relies on Claude inferring relevance
description: How to build a fast internal dashboard.

# PUSHY: names the triggers Claude should match against
description: How to build a fast internal dashboard. Use this skill whenever the user mentions dashboards, data visualization, internal metrics, or wants to display company data, even if they don't say "dashboard" explicitly.
```

Don't push it into hype ("ALWAYS USE THIS!!"). Just name the trigger phrases.

## Progressive disclosure

Skills use three loading levels:

| Level | When loaded | Budget |
|-------|-------------|--------|
| **Metadata**, `name` + `description` | Always in context | ~100 words |
| **SKILL.md body** | When the skill triggers | < 500 lines ideal |
| **Bundled resources**, references, scripts, assets | On demand (scripts can execute without being read) | unlimited |

Key patterns:

- Keep SKILL.md under 500 lines. Past that, add a level of hierarchy with clear pointers to the next file to read.
- For reference files over 300 lines, include a table of contents.
- Reference files should be linked from SKILL.md with explicit guidance on *when* to read them.

## Domain organization

When a skill supports multiple domains (e.g. AWS / GCP / Azure), organize by variant:

```
cloud-deploy/
├── SKILL.md              # workflow + which-variant selection
└── references/
    ├── aws.md
    ├── gcp.md
    └── azure.md
```

SKILL.md picks the variant based on user input or detected context; Claude then reads only the relevant reference file. Avoids bloating the always-loaded body.

## TDD for skills

Writing a skill is test-driven development applied to documentation. If you didn't pressure-test the skill against an agent before writing it, you don't know if the skill teaches the right thing.

| TDD | Skill creation |
|-----|----------------|
| Failing test | Baseline scenario, agent fails / rationalizes without the skill |
| Production code | The skill body |
| Watch it fail | Document the exact rationalizations / failures the agent uses |
| Minimal code | Write the skill that addresses *those specific* rationalizations |
| Watch it pass | Re-run the scenario with the skill loaded; agent should now comply |
| Refactor | Find new rationalizations and plug them; re-verify |

**Process:**

1. Pick the rule you want a future agent to follow.
2. Construct a scenario that pressures an agent to break the rule (time pressure, "just this once", "I already tested it manually").
3. Run the scenario without the skill. Record the exact words the agent uses to rationalize.
4. Write the skill targeting those specific rationalizations. Don't write generic advice.
5. Re-run the scenario with the skill present. Did the agent comply?
6. If yes, look for new loopholes by varying the scenario. If no, the skill isn't sharp enough, rewrite.

**Why this matters:** generic "best practices" skills get ignored. Skills that name and rebut the *specific rationalizations* an agent uses get followed. The rationalizations are the failing test.

## Flowcharts only for non-obvious decisions

Use a graphviz flowchart only when there's a decision point where a future agent might go the wrong way, e.g. "should I create a worktree or not?", "did spec review pass yet?".

Do not use flowcharts for:

- Reference material → use tables or lists.
- Code examples → use markdown blocks.
- Linear step lists → use numbered lists.

A flowchart that just renders "step 1 → step 2 → step 3" is noise.

## When to Add Scripts

Add utility scripts when:

- Operation is deterministic (validation, formatting)
- Same code would be generated repeatedly
- Errors need explicit handling

Scripts save tokens and improve reliability vs generated code.

## When to Split Files

Split into separate files when:

- SKILL.md exceeds 100 lines
- Content has distinct domains (finance vs sales schemas)
- Advanced features are rarely needed

## Review Checklist

After drafting, verify:

- [ ] Description includes triggers ("Use when...")
- [ ] SKILL.md under 100 lines
- [ ] No time-sensitive info
- [ ] Consistent terminology
- [ ] Concrete examples included
- [ ] References one level deep
