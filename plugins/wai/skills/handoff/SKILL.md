---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up. Saves to the OS temp directory so it doesn't pollute the workspace.
argument-hint: "What will the next session be used for?"
inspired-by: |
  mattpocock/skills/productivity/handoff
  humanlayer/.claude/commands/create_handoff.md
---

# Handoff

Compact the current session into a handoff doc so a fresh agent can continue. The goal: enough context to resume, no more.

## Where to save

Default: the OS temp directory, `${TMPDIR:-/tmp}/handoffs/<YYYY-MM-DD>_<HH-MM-SS>_<kebab-description>.md`. Create the parent dir if needed.

Don't write into the workspace. Handoffs are scratch artefacts.

If the user passes a different path as an argument, save there instead. If the argument describes the *next session's focus* rather than a path, treat it as the focus and use the default location.

## Filename format

`<YYYY-MM-DD>_<HH-MM-SS>_<kebab-description>.md`

- `YYYY-MM-DD` = today's date.
- `HH-MM-SS` = current time, 24-hour (e.g. `13-55-22` for 1:55 PM).
- `<kebab-description>` = brief summary of the session's focus, lowercased, hyphen-separated. Three to six words.

Examples:
- `2026-05-26_13-55-22_create-context-compaction.md`
- `2026-05-26_09-12-04_fix-webhook-retry-bug.md`

## Document structure

Open with YAML frontmatter:

```yaml
---
date: <ISO timestamp with timezone>
git_commit: <output of `git rev-parse HEAD`>
branch: <output of `git rev-parse --abbrev-ref HEAD`>
repository: <basename of the repo>
topic: <short topic line>
tags: [<comma-separated, relevant component or area names>]
status: complete
type: handoff
---
```

Then this skeleton, drop any section that's empty rather than padding it:

```markdown
# Handoff: <very concise description>

## Task(s)
What you were working on, and the status of each: completed / work in progress / planned / discussed.
If working from a plan, name the phase you reached. Reference the plan or research doc by path.

## Critical references
The 2-3 most important spec docs, architectural decisions, or design notes the next agent must follow. Skip if none.

## Recent changes
Concrete changes made this session. Prefer `path/file.ext:line` over code blocks.

## Learnings
Patterns, root causes, surprising constraints. Things the next agent should know but couldn't derive from the diff alone. Include file paths.

## Artifacts
Files this session produced or updated. File paths or `file:line` refs. The next agent should be able to read these in order to resume.

## Suggested skills
Skills the next agent should invoke when resuming, e.g. `tdd`, `diagnose`, `improve-codebase-architecture`. Skip if none apply.

## Action items / next steps
Ordered list of what's next, based on task statuses above.

## Other notes
Anything else worth passing on, where to find related docs, gotchas, project-specific quirks.
```

## Rules

- **More info, not less**, this is the floor of what a good handoff contains; include more if it'll help the next agent.
- **No duplication.** If a PRD, plan, ADR, issue, or commit already says it, link to it. Don't restate.
- **Prefer `file:line` over code blocks.** A reference an agent can chase later is better than a code blob pasted inline. Keep code only when it pertains to a specific error you were debugging.
- **Redact secrets.** No API keys, passwords, tokens, PII. If you must reference an env var, name it but don't print the value.
- **Specific, not vague.** "Investigated auth" is useless. "Found that `verifyToken()` at `src/auth/token.ts:18` uses `<` instead of `<=` for expiry comparison; off-by-one" is the bar.

## After writing

Tell the user the file path and both ways to pick it up:

```
Handoff written to <absolute path>.

Resume by hand in a new session:

  /resume-handoff <path>

Or hand it straight to a background agent:

  claude --bg "/resume-handoff <path>"
```

### Handing it to a background agent

When the user asks to hand the work off rather than park it (`--bg`, "start it now", "send it to an agent"), run the background form yourself instead of printing it:

```bash
claude --bg "/resume-handoff <absolute path>"
```

Verified against Claude Code 2.1.231, where `--bg` starts the session as a background agent. If the flag is missing on the user's version, print the manual command and say why rather than guessing at a substitute.

Two rules on the automated form:

- **Pass the absolute path.** The background agent does not inherit this session's working directory.
- **The handoff doc has to be complete first.** A background agent cannot come back and ask what you meant, so anything you were planning to explain in chat belongs in the file.
