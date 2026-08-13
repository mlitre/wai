# Skill mechanics

The skill-specific branch of [writing-for-agents](./SKILL.md): what changes when the document is a skill. Frontmatter, the invocation choice, router skills, and how to pressure-test the result. Everything else about writing it is in `SKILL.md`.

## Frontmatter

wai conventions, enforced by `scripts/check-index.sh`:

```yaml
---
name: skill-name                    # required, kebab-case, matches the directory
description: ...                    # required, the pointer, see SKILL.md
allowed-tools: Read, Grep, Glob     # recommended, narrows the surface
inspired-by:                        # required when ported, one line per upstream
  - owner/repo/path/to/upstream
---
```

Every ported artifact needs both an `inspired-by` line and a row in `SOURCES.md`. The lint checks that they agree.

## Invocation

Two choices, trading the two loads:

- **Model-invoked** keeps a `description`, so the agent can fire the skill on its own and other skills can reach it. You can still type its name: model invocation always includes user reach, and a description only ever adds agent discovery. The description is the skill's top-level context pointer, forced to stay loaded at all times, which is permanent context load bought in exchange for discoverability. A model-invoked skill whose content is all reference is also one home for shared reference, since another skill can invoke it. Mechanics: omit `disable-model-invocation`, and write a model-facing description carrying the trigger branches.
- **User-invoked** strips the description from the agent's reach. Only the human typing its name can invoke it, and no other skill can. Zero context load, but it spends cognitive load: you are the index that has to remember it exists. Mechanics: set `disable-model-invocation: true`, and the `description` becomes human-facing, a one-line summary with the trigger list stripped.

Pick model invocation only when the agent must reach the skill on its own, or another skill must. If it only ever fires by hand, make it user-invoked and pay no context load.

Shared reference that two user-invoked skills both need can live in neither, since with no descriptions neither can fire the other. Push it to a plain file outside the skill system, which any skill can point at.

### Splitting by invocation

The invocation cut of splitting (the sequence cut is in `SKILL.md`): split off a model-invoked skill when you have a distinct leading word that should trigger it on its own, a trigger word you actually use in your prompts, or when another skill must reach it. You pay context load for the new always-loaded description, so that independent reach has to be worth it.

### Pushy descriptions for undertriggering

Agents undertrigger skills more often than they overtrigger them. Counter it by naming the trigger phrases explicitly rather than relying on inference:

```yaml
# WEAK, relies on the agent inferring relevance
description: How to build a fast internal dashboard.

# PUSHY, names what to match against
description: How to build a fast internal dashboard. Use whenever the user mentions dashboards, data visualization, internal metrics, or displaying company data, even if they do not say "dashboard" explicitly.
```

Name the triggers, and stop there. Hype ("ALWAYS USE THIS!!") is a no-op the model discounts.

## Router skills

When user-invoked skills multiply past what you can remember, that piled-up cognitive load is cured by a **router skill**: one user-invoked skill naming the others and when to reach for each, so the human remembers one instead of many. It can only hint, never fire them, since user-invoked skills have no description and nothing but the human can reach them.

In wai the human-facing router is `INDEX.md`, not a skill.

## Layout

```
skill-name/
├── SKILL.md          # required
├── REFERENCE.md      # disclosed reference, when a branch needs it
└── scripts/          # only for deterministic operations
    └── helper.sh
```

Add a script when the operation is deterministic (validation, formatting, parsing), when the same code would otherwise be generated repeatedly, or when errors need explicit handling. Scripts save tokens and remove a class of generation error. wai is markdown-first, so a script needs a reason.

Domain variants (AWS / GCP / Azure, or one file per spec edition) go one level down as `references/<variant>.md`, with `SKILL.md` selecting the variant. Only the selected file loads.

## Pressure-test before shipping

Writing a skill is TDD applied to documentation. The rationalizations are the failing test.

| TDD | Skill creation |
|-----|----------------|
| Failing test | baseline scenario, the agent fails or rationalizes without the skill |
| Production code | the skill body |
| Watch it fail | record the exact rationalizations the agent used |
| Minimal code | write the skill that answers *those specific* rationalizations |
| Watch it pass | rerun the scenario with the skill loaded |
| Refactor | vary the scenario, find new loopholes, plug them |

1. Pick the rule you want a future agent to follow.
2. Construct a scenario that pressures an agent to break it (time pressure, "just this once", "I already tested it manually").
3. Run it without the skill. Record the exact words the agent used to rationalize.
4. Write the skill targeting those words. Generic best-practice advice gets ignored; a named and rebutted rationalization gets followed.
5. Rerun with the skill present. If the agent complies, vary the scenario and hunt for the next loophole.

This is also how a no-op dispute gets settled: run the document, do not argue about the default.

## Flowcharts

Use a flowchart only where a future agent might take the wrong branch at a real decision point ("worktree or not?", "has spec review passed?"). Reference material goes in tables, code in code blocks, linear sequences in numbered lists. A flowchart rendering "step 1, step 2, step 3" is noise.
