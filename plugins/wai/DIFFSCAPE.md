# Diffscape

Browser-based code review for changes made during a Claude Code session.

Invoke `/ds` and Diffscape opens a local web UI, file tree, unified or side-by-side diff with syntax highlighting, inline and file-level comments, approve or request-changes buttons. Claude long-polls in the background while you review, then picks up your decision automatically on your next prompt.

## Overview

- Generates a diff of your working tree against a baseline ref (default `HEAD`, any valid ref otherwise).
- Serves a single-page review UI on `http://localhost:<port>` via a local Node HTTP server, bound to loopback only.
- Blocks Claude on a `/api/wait-for-review` long-poll until you submit, then re-delivers the review via a `UserPromptSubmit` hook as a structured system message.
- Pre-launches the server on `SessionStart` so `/ds` is instant; auto-shuts down on idle timeout, owner-PID death, or SIGTERM.
- Suggests `/ds` unprompted once the working tree has five+ changed files (threshold configurable).
- Works in plain git repositories and GitButler workspaces.
- Vendors `diff2html` and `highlight.js`, so runtime has no network dependencies beyond Google Fonts.

## Install

Diffscape ships as the `ds` skill inside the wai plugin, install wai and `/ds` is available:

```
/plugin marketplace add github.com/mlitre/wai
/plugin install wai@wai
```

This is wai's only engine exception, everything else in the plugin is markdown-only. Diffscape brings a Node review server, three hooks, vendored JS (`diff2html`, `highlight.js`), and shell scripts. The exception is explicit; do not generalize it to other wai artifacts.

### Permissions

A plugin's own `settings.json` currently only accepts the `agent` and `subagentStatusLine` keys, it can't ship a permission allowlist. To skip first-run approval prompts, drop the following into `~/.claude/settings.json` or your project's `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(git rev-parse:*)",
      "Bash(git diff:*)",
      "Bash(curl * http://localhost:*)",
      "Write(.ds/**)"
    ]
  }
}
```

`permissions.allow` arrays concatenate across settings scopes, so this merges cleanly with any existing entries. Note: the skill's server-liveness probe (a compound `if ... node -e ... curl ... fi` one-liner) won't match any simple `Bash(...)` prefix rule, approve it once per session and Claude Code will remember it.

## Usage

### Command

| Invocation | Baseline |
|---|---|
| `/ds` | `HEAD` (uncommitted changes) |
| `/ds main` | branch `main` |
| `/ds abc1234` | specific commit |
| `/ds origin/feature` | any valid git ref |

The skill validates the baseline with `git rev-parse <baseline> --` before running `git diff`, then either reuses the pre-launched server or cold-starts one.

### Review UI

| Feature | |
|---|---|
| File sidebar | Per-file `⟨EXT⟩` type icons, `+N -N` stats, comment-count pills, live filter input, scroll-spy highlighting, collapse toggle |
| Diff viewer | Unified / side-by-side toggle (persisted in `localStorage` as `ds-view-mode`), per-file collapse with proportional stats bar, hunk-context expansion via `↕ Expand` on hunk headers |
| Inline comments | Click any line number to attach a comment to that line; Ctrl/Cmd+Enter to save, Escape to cancel |
| File-level comments | "Comment" button in each file header |
| Comment editing | Every comment supports Edit / Delete; bodies render basic markdown (backtick, `**bold**`, `*italic*`) |
| Syntax highlighting | Per-language colouring on every diff cell via highlight.js (`github-dark` theme) |
| Review submission | "Review Summary" modal with decision + optional summary; POSTs the full review payload to the server |
| GitButler | Detected automatically from `.git/gitbutler/`; a `GB` badge appears next to the branch name |

### Keyboard shortcuts

| Key | Action |
|---|---|
| `j` / `k` | Next / previous file |
| `a` | Open Approve modal |
| `x` | Open Request Changes modal |
| `/` | Focus sidebar file search |
| `e` | Collapse / expand focused file |
| `Escape` | Close submitted overlay → review modal → open comment form (priority order) |

## How it works

Six pieces coordinate across four processes:

| Piece | Trigger | Role |
|---|---|---|
| `SessionStart` hook, `hooks/session-start.sh` | Claude Code session start | Launches (or reuses) the review server, writes `.ds/server-info` |
| `PostToolUse` hook, `hooks/suggest-review.js` | After each `Edit` / `Write` / `MultiEdit` | Checks `git diff --shortstat HEAD`; nudges Claude to suggest `/ds` at ≥ 5 files changed |
| `UserPromptSubmit` hook, `hooks/check-review.js` | Every user prompt | Atomically claims `review.json` if the server has one, delivers it to Claude as a `systemMessage` |
| `/ds` skill, `skills/ds/SKILL.md` | User invokes `/ds` | Parses baseline, writes `diff.patch` + `review-meta.json`, long-polls `/api/wait-for-review`, handles the review result |
| Review server, `server/index.js` | Launched by the SessionStart hook | Serves the UI and the review API; idle timeout, owner-PID watchdog, atomic review claim |
| Browser UI, `ui/` | Loaded by the user | Reads the diff, records comments, POSTs the review back |

### File-mediated handoff

State is exchanged via three files under `<project>/.ds/sessions/<id>/state/`:

| File | Producer | Consumer |
|---|---|---|
| `diff.patch` | `/ds` skill (step 6) | Server's `/api/diff` |
| `review-meta.json` | `/ds` skill (step 6) | Server's `/api/diff` (baseline label + cwd) |
| `review.json` | Server's `POST /api/review` | `/api/wait-for-review` long-poll *and* `check-review.js` hook, synchronised by an atomic rename-before-read so exactly one consumer receives it |

Top-level pointers `<project>/.ds/server-info` and `<project>/.ds/server.pid` let both the hook and the skill locate the current session's state directory without scanning.

### Lifecycle

The server is started in the background with `nohup`, writes its PID file, and logs the `server-started` JSON line once it's listening on an OS-assigned port. It shuts itself down on any of:

- Idle timeout (default 20 min; every inbound request and every long-poll tick refresh the clock).
- Owner-PID watchdog, when launched with `DS_OWNER_PID`, signal `0` is sent every 30 s; on `ESRCH` the server exits.
- `SIGTERM` / `SIGINT`.
- Explicit `scripts/stop-server.sh <session_dir>`.

On startup the server sweeps sibling sessions older than 24 h whose PID is unreachable, garbage-collecting abandoned state directories.

## HTTP API

The server is bound to `127.0.0.1` by default. All routes return JSON unless they serve a static UI asset.

| Method | Path | Purpose |
|---|---|---|
| `GET` / `HEAD` | `/api/heartbeat` | `204`; resets the idle timer. The UI pings every 60 s. |
| `GET` | `/api/diff` | Returns `{ baseline, rawDiff, git: { branch, baselineLabel, isGitButler, projectName }, version }`. |
| `GET` | `/api/file-context?file=&start=&end=` | Returns a line range from a file inside the locked project dir. Path-traversal guarded (`403` on escape, `404` on missing). |
| `POST` | `/api/review` | Accepts `{ decision, summary, comments[] }`; stamps a `timestamp` and writes `review.json`. |
| `GET` | `/api/status` | Returns `{ submitted, review, version }`. |
| `GET` | `/api/wait-for-review` | Long-poll up to 9 min; returns `{delivered:true,review}` or `{delivered:false,reason:"timeout"}`. Atomically claims `review.json` on delivery. |
| `GET` | `/`, `/index.html`, `/styles.css`, `/app.js`, `/vendor/<path>` | Static UI assets (traversal-guarded). |

Review payload shape (what `/api/review` accepts and what `check-review.js` delivers):

```json
{
  "decision": "approve",
  "summary": "optional string or null",
  "comments": [
    { "id": "c1", "file": "src/foo.ts", "line": 42,   "body": "...", "type": "inline"     },
    { "id": "c2", "file": "src/bar.ts", "line": null, "body": "...", "type": "file-level" }
  ]
}
```

## Configuration

All variables are optional unless marked required. The three user-tunable ones are `DS_SUGGEST_THRESHOLD`, `DS_IDLE_TIMEOUT_MS`, and (for custom deployments) `DS_HOST` / `DS_URL_HOST`.

| Variable | Default | Purpose |
|---|---|---|
| `DS_SUGGEST_THRESHOLD` | `5` | Minimum changed-file count at which `suggest-review.js` nudges toward `/ds`. |
| `DS_IDLE_TIMEOUT_MS` | `1200000` (20 min) | Idle window before the server exits. Must parse as a finite positive number, else the default is used. |
| `DS_HOST` | `127.0.0.1` | Bind address. |
| `DS_URL_HOST` | `localhost` | Host used when constructing the shown URL. Auto-derives from `DS_HOST` when unset. |
| `DS_DIR` | **required** | Session root (set by `start-server.sh`; don't set manually). |
| `DS_OWNER_PID` | `0` (watchdog off) | PID the server watches for liveness (set by `start-server.sh`). |
| `DS_PROJECT_DIR` | *(none)* | Locked project root used to sandbox `/api/file-context` reads (set by `start-server.sh`). |

Set the user-tunable vars in your shell or in a Claude Code `env` settings block.

## Layout

### In the repo (paths relative to `plugins/wai/`)

```
hooks/hooks.json             Hook registration (wai plugin manifest references it)
hooks/session-start.sh       SessionStart: pre-launch the server
hooks/check-review.js        UserPromptSubmit: deliver a submitted review
hooks/suggest-review.js      PostToolUse: nudge toward /ds
skills/ds/SKILL.md           /ds orchestration
scripts/start-server.sh      Server launcher
scripts/stop-server.sh       Server teardown
scripts/tests/               Shell-based integration tests
server/index.js              Review HTTP server
ui/index.html                UI shell
ui/app.js                    UI client logic
ui/styles.css                Dark theme + diff2html / highlight.js overrides
vendor/diff2html/            Bundled diff2html (min.js + min.css)
vendor/highlight.js/         Bundled highlight.js + github-dark theme
```

### At runtime

Created under the user's project directory, not the plugin directory:

```
<project>/.ds/server-info               Latest server-started JSON (top-level pointer)
<project>/.ds/server.pid                Latest server PID (top-level pointer)
<project>/.ds/sessions/<id>/state/      Per-session state
    diff.patch                            Raw diff written by the skill
    review-meta.json                      baseline + cwd + timestamp
    review.json                           Review payload (claimed atomically on read)
    server.pid                            Canonical PID for that session
    server.log                            Server stdout / stderr
    server-info                           Canonical server-started JSON
```

## Development

### Dependencies

Runtime: Node.js (server + hooks), `bash`, `git`, `curl`, `ps`, `kill`. Vendored: `diff2html`, `highlight.js`.

### Tests

Shell-based integration tests in `scripts/tests/`:

```bash
scripts/tests/run-all.sh
```

Or run individually:

| Script | Exercises |
|---|---|
| `test-server-info.sh` | `.ds/server-info` + `.ds/server.pid` publishing, cold-start after kill, orphan sweep, hook pickup of the refreshed `state_dir` |
| `test-heartbeat.sh` | `/api/heartbeat` returns 204; repeated heartbeats extend idle; idle server exits in budget; Node driver simulating the browser keeps the server alive |
| `test-parallel.sh` | Two project servers have independent idle clocks and `server-info` pointers |
| `test-security.sh` | Path-traversal rejection on `/api/file-context` and `/vendor/`; `review-meta.json` can't redirect file reads; atomic review claim is single-consumer |

`run-all.sh` runs all four and exits non-zero if any fail.

### Platform notes

`start-server.sh` auto-selects foreground mode (`exec node ...`) under `CODEX_CI` and under msys / cygwin / mingw, because those environments reap backgrounded processes. Elsewhere it runs `nohup ... &` in the background by default. Override explicitly with `--foreground` / `--background`.

## License

MIT, see the repo's [LICENSE](../../LICENSE) and the wai plugin manifest at [`plugins/wai/.claude-plugin/plugin.json`](./.claude-plugin/plugin.json).
