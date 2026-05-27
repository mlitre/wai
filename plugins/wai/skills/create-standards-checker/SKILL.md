---
name: create-standards-checker
description: |
  Use this skill to generate a domain-specialized standards-compliance-checker agent for a repo. You name the domain (EV charging, payments, internal protocols, HTTP, OAuth, anything with normative spec docs) and seed the spec registry with aliases → paths; the skill writes a `.claude/agents/<domain>-standards-compliance-checker.md` baked with the right examples + auto-trigger language + edition gotchas. Generated agents share one method (extract normatives → grep → classify ✓ / ⚠ / ✗ / - with quotes + `file:line`) but each has rich domain framing so auto-trigger fires on domain-specific user prompts.

  Use when:
  - User says "I want a compliance checker for OCPP" / "standards auditor for our internal RFCs" / "audit code against our design docs"
  - User says "generate a spec-compliance agent" / "make a standards checker"
  - User mentions auditing code against a written spec and the repo doesn't yet have a specialized agent
allowed-tools: Read, Write, Edit, Bash
inspired-by: ~/.claude/agents/standards-compliance-checker.md
---

Factory skill. Generates a specialized `<domain>-standards-compliance-checker` agent file into `.claude/agents/` of the current repo, plus seeds `.claude/compliance-specs.json` with the chosen registry. The generated agent is self-contained, it inlines the full method so it does not depend on this skill or any wai runtime.

The method itself (preflight, extract normatives, grep, classify, hard rules) is fixed and identical across all generated agents. What varies per domain: the agent's `name`, `description` framing, auto-trigger examples, default registry seed, edition gotchas.

## When to use it

- The user is starting compliance work in a new domain (EV charging, payments, telecom, internal RFCs, regulatory documents, ...) and wants an agent with rich domain framing rather than a bare generic one.
- The user has an existing generic agent but auto-trigger keeps missing on their domain language.
- Multiple teams in the same repo audit against different spec families, generate one specialized agent per family.

Skip it when: the user just wants to audit a one-off doc. In that case, no agent file is needed, they can call the standards-compliance-checker directly (or use a generic one). The factory pays off when the same domain comes back repeatedly.

## Inputs to gather (interactive)

Ask one at a time. Defaults shown.

1. **Domain slug**, short kebab-case, used in the filename and agent name. Examples: `ev`, `payments`, `internal-rfc`, `http`. No default.
2. **Auto-trigger phrases**, 3-8 short phrases the user (or other callers) would use that should fire this agent. Examples for `ev`: "OCPP", "ISO 15118", "V2G", "EVSE", "Plug & Charge", "EEBUS". These go into the description examples + a keyword bag.
3. **Spec aliases**, alias + path pairs to seed `.claude/compliance-specs.json`. Ask for one at a time; stop on empty input. Each entry: `alias`, `path` (absolute or repo-relative, `~/` allowed), optional `edition`, optional `notes`. Example for `ev`:
   - `ocpp-2.1` → `~/Docs/OCPP/OCPP-2.1_Edition2_part2.pdf` (edition: `Edition 2`)
   - `iso-15118-2` → `./specs/iso-15118-2.pdf`
4. **Default code globs**, where the agent should look for implementation by default if the caller doesn't supply a code scope. Default: `["src/**", "pkg/**", "lib/**"]`. Override if the repo uses different conventions.
5. **Edition gotchas**, free text. Anything the agent should always flag (e.g. "OCPP 2.1 has Edition 1 + Edition 2, never use Edition 1"). Optional.

Confirm all answers in a summary block before writing anything.

## Output files

1. **Agent file**, `.claude/agents/<domain>-standards-compliance-checker.md`. Built from `agent-template.md` (sibling file in this skill) with the placeholders below filled in.
2. **Registry seed**, `.claude/compliance-specs.json`. If the file is missing, create it from scratch with the seeded entries. If it exists, ask before merging (show diff, atomic temp-file rename, never partial-write).

Never overwrite an existing agent file without explicit user confirmation. If `.claude/agents/<domain>-standards-compliance-checker.md` already exists, show the user the existing file's title + description first, then ask: overwrite / pick a different slug / abort.

## Template placeholders

`agent-template.md` uses these, fill all of them before writing:

| Placeholder | What |
|---|---|
| `{{domain}}` | Domain slug (e.g. `ev`) |
| `{{domain_label}}` | Human-readable domain name (e.g. `EV-charging`), for the description prose |
| `{{trigger_phrases}}` | Comma-separated list (e.g. `OCPP, ISO 15118, V2G, EVSE, Plug & Charge`) |
| `{{example_alias}}` | Pick one seeded alias for the first example (e.g. `ocpp-2.1`) |
| `{{example_section}}` | Realistic section reference (e.g. `§C01`) |
| `{{example_code_path}}` | Realistic file path (e.g. `src/ocpp/setvariables.ts`) |
| `{{example_inline_doc}}` | Realistic inline-path example (e.g. `/home/me/specs/eebus-lpc-v1.0.0.pdf`) |
| `{{edition_gotchas}}` | Free-text block, pasted into a "Known edition gotchas" section. If empty, omit the section. |

## Write workflow

1. Resolve domain slug → check `.claude/agents/<domain>-standards-compliance-checker.md`. Confirm overwrite if it exists.
2. Read `${CLAUDE_PLUGIN_ROOT}/skills/create-standards-checker/agent-template.md`.
3. Substitute every `{{placeholder}}`. Verify no placeholders remain (`grep -F '{{' tmpfile` must be empty).
4. Atomic write: `<file>.tmp` → `mv`.
5. Handle the registry:
   - If `.claude/compliance-specs.json` missing → write it fresh with the seeded `specs` + the user's `default_code_globs`.
   - If present → `jq` merge: union of existing + new aliases. On alias collision, ask per-alias (keep existing / replace with new / skip). Atomic write.
6. Print:
   - Path to the generated agent
   - Number of aliases seeded into the registry
   - One-line invocation hint: "the agent will auto-fire on prompts like '<one of the trigger phrases>' or invoke it explicitly via the Agent tool"

## Hard rules

- The skill never edits code. The skill only writes the agent file + the registry file.
- Atomic writes only. No partial-write states.
- Never silently overwrite an existing agent or registry. Always show a diff and ask.
- Generated agents inline the full method, they do not import or reference this skill. If the method evolves, run the skill again to re-generate (the user owns the re-generate decision; never auto-update existing agents).
- The skill does not invoke the generated agent. After writing, print the invocation hint and stop.
- The skill writes JSON via `jq` only, never `sed`/`awk`/`echo`. The agent template is plain markdown; substitute via Python or sed-with-care, with the post-write `grep` check above.

## See also

- Command `/spec-registry`, manages the `.claude/compliance-specs.json` registry that all generated agents read. Run `/spec-registry list` to inspect; `/spec-registry add` / `update` / `remove` for ongoing maintenance.
- Sibling file `agent-template.md`, the template body used here. Edit if you want all future generated agents to evolve. Re-run this skill on existing repos to re-generate.
