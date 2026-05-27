---
name: writing-native-hooks
description: Write Claude Code native hooks (settings.json `PreToolUse` / `PostToolUse` / `UserPromptSubmit` / `Stop` / `SessionStart` / `Notification` / `SubagentStop` / `PreCompact`). Use when the user wants to add a hook to block, warn on, or augment a tool call, or wants to enforce a checklist before stopping. No engine, Claude Code reads `settings.json` directly.
---

# Writing Native Claude Code Hooks

Claude Code reads hooks from `settings.json`. Each hook runs a shell command at a fixed event; the command reads tool input on stdin, prints JSON on stdout, and uses exit code to allow/block.

No DSL, no Python engine. Anything you can write as a shell one-liner or script can be a hook.

For a rule-DSL alternative, install the `hookify` plugin separately, it ships its own `writing-hookify-rules` skill. Native hooks are lower-level but always available.

## Where settings.json lives

- **User-level:** `~/.claude/settings.json`, applies to every Claude Code session for this user.
- **Project-level:** `.claude/settings.json` at the repo root, applies only to this repo.
- **Local-only project:** `.claude/settings.local.json`, same scope, but git-ignored. Use for personal hook tweaks that shouldn't ship to the team.

Project settings take precedence over user settings. Local-only takes precedence over project.

## Event types

| Event | Fires | Common use |
|-------|-------|------------|
| `PreToolUse` | Before any tool runs (Bash, Edit, Write, MultiEdit, etc.) | Block dangerous commands, warn about patterns, redirect to safer alternatives |
| `PostToolUse` | After a tool returns | Lint the edit, run the test the user just saved, log the action |
| `UserPromptSubmit` | When the user sends a prompt | Inject context, normalize phrasing, enforce checklist |
| `Stop` | When the agent wants to stop | Force checklist verification, require tests run, demand commit |
| `SubagentStop` | When a dispatched subagent finishes | Verify subagent output before integrating |
| `SessionStart` | New session begins | Auto-load context (e.g. CLAUDE.md highlights, recent PRs) |
| `Notification` | Claude Code notifies user | Forward to Slack, ntfy, etc. |
| `PreCompact` | Before context compression | Persist anything you don't want summarized |

## settings.json schema

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "shell-command-here",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

**Fields:**

- `matcher` (optional, `PreToolUse` / `PostToolUse` only), regex against the tool name. `"Bash"` / `"Edit|Write|MultiEdit"` / `"."` (all). Omit for events that don't have a tool.
- `command`, the shell command to run. May reference `${CLAUDE_PLUGIN_ROOT}` if shipping inside a plugin.
- `timeout`, seconds before the hook is killed (default 60). Keep small (5-10) for `PreToolUse` to avoid latency.
- Multiple hook entries inside `hooks: [...]` run sequentially.

## What the hook sees and returns

**stdin (JSON):**

`PreToolUse` / `PostToolUse`:

```json
{
  "tool_name": "Bash",
  "tool_input": { "command": "rm -rf /" }
}
```

For `Edit` / `Write` / `MultiEdit` the input has `file_path`, `new_text`, `old_text`, `content` (varies by tool).

`UserPromptSubmit`:

```json
{ "user_prompt": "deploy to prod" }
```

`Stop`:

```json
{ "stop_hook_active": true, "transcript_path": "/path/to/transcript.jsonl" }
```

**stdout (JSON, optional):**

```json
{
  "decision": "approve" | "block",
  "reason": "shown to the model when blocked",
  "systemMessage": "shown to the model regardless of decision",
  "additionalContext": "appended to the next model turn"
}
```

**Exit codes:**

- `0`, allow.
- `2`, block, with stderr shown to the model as the block reason.
- Anything else, error, allow operation, surface stderr as a warning.

**Always exit 0 for non-blocking warnings.** Only exit 2 when you genuinely want to stop the tool call.

## Patterns

### Block a dangerous command

`~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.command' | grep -qE 'rm\\s+-rf\\s+/' && { echo 'Blocked: rm -rf on a root path' >&2; exit 2; } || exit 0",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### Warn but allow (no exit 2)

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_input.command' | grep -qE 'chmod\\s+777' && echo '{\"systemMessage\":\"chmod 777 detected, narrow permissions instead.\"}' || true",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### Lint after every edit

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "FILE=$(jq -r '.tool_input.file_path'); case \"$FILE\" in *.ts|*.tsx) npx eslint --fix \"$FILE\" || true ;; *.py) ruff check --fix \"$FILE\" || true ;; esac",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

### Stop-checklist enforcement

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo '{\"systemMessage\":\"Before stopping: tests passed? build green? PR description drafted?\"}'",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### Inject context on every prompt

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo '{\"additionalContext\":\"Today is '$(date +%Y-%m-%d)'. Project status: see CLAUDE.md.\"}'",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

## Workflow

### 1. Pick the event

- Block / warn before a tool runs → `PreToolUse`.
- React after a tool runs → `PostToolUse`.
- Shape what the model sees on prompt → `UserPromptSubmit`.
- Force checks before the agent stops → `Stop`.

### 2. Write the matcher

Only `PreToolUse` / `PostToolUse` take `matcher`. Regex against the tool name. Common matchers:

- `Bash`
- `Edit|Write|MultiEdit`
- `.` (everything)

### 3. Write the command

Read stdin with `jq`. Decide allow / block / warn. Return JSON or use exit code.

### 4. Test

Edit settings, then run a Bash command Claude Code intercepts. If the hook misbehaves, check `~/.claude/logs/` (or the IDE's debug output).

### 5. Tune

- Time out fast (`timeout: 5`) for `PreToolUse`, every blocked tool call adds latency.
- Always `exit 0` unless you really want to block.
- Use `systemMessage` for advisory, `decision: "block"` + `reason` for hard blocks.

## Common pitfalls

- **Forgetting `exit 0` after a non-blocking message.** Any non-zero exit aborts the tool by default.
- **Blocking too broadly.** A `Bash` matcher with no command regex blocks every shell command. Always filter inside the hook script.
- **Long-running commands.** `PreToolUse` runs synchronously, keep it under a second. Defer expensive checks to `PostToolUse`.
- **Quoting hell.** JSON-in-JSON is painful. For anything beyond a one-liner, write a script file and have the hook invoke it: `command: "/path/to/check.sh"`.
- **Not testing the JSON shape.** Print `jq .` of the input once during development so you know exactly which field the tool puts data in (Bash has `command`, Edit has `file_path` + `new_text`, etc.).

## Pairs with

- `conversation-analyzer`, mine the current session for behaviors worth hooking. Its output (event + pattern + suggested message) maps directly onto these `settings.json` entries.
- `hookify` plugin (separate install), DSL-driven rules; install the upstream plugin to get the `writing-hookify-rules` skill. Engine-dependent.

## Quick reference

| Want to ... | Event | How |
|-----------|-------|-----|
| Block a dangerous Bash command | `PreToolUse` (matcher `Bash`) | grep stdin → `exit 2` |
| Warn but allow | `PreToolUse` | print `{"systemMessage":"..."}` → exit 0 |
| Lint after edit | `PostToolUse` (matcher `Edit|Write|MultiEdit`) | run linter on `tool_input.file_path` |
| Add date / context every prompt | `UserPromptSubmit` | print `{"additionalContext":"..."}` |
| Enforce stop checklist | `Stop` | print `{"systemMessage":"..."}` |
| Forward notifications | `Notification` | post payload to webhook |

For full schema and edge cases, see Claude Code's official hook docs.
