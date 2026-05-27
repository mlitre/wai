---
name: ds
description: "Launch Diffscape, a browser-based code review for changes. Default: diff against HEAD. Optional: /ds main, /ds <commit>"
---

# Diffscape, Code Review

Launch a browser-based code review UI showing all changes in a GitHub PR-like interface. The user can browse files, toggle between unified and side-by-side diffs, leave inline and file-level comments, then approve or request changes.

## Orchestration

Follow these steps exactly:

### 1. Parse Arguments

The user may provide a baseline ref as an argument (e.g., `/ds main`, `/ds abc1234`). If no argument is provided, default to `HEAD`.

### 2. Validate Git Repository

Run:
```bash
git rev-parse --is-inside-work-tree
```

If this fails, tell the user: "Not inside a git repository. Run `/ds` from a git repo."

### 3. Validate Baseline (if provided)

If the user provided a baseline other than HEAD, validate it:
```bash
git rev-parse <baseline> --
```

If invalid, tell the user the ref doesn't exist.

### 4. Generate Diff

Run:
```bash
git diff <baseline>
```

This captures both staged and unstaged changes relative to the baseline.

If the diff output is empty, tell the user: "No changes to review against `<baseline>`." and stop.

### 5. Start or Reuse the Server

First, check if a server is already running (pre-launched at session start):
```bash
info_file="<current working directory>/.ds/server-info"; if [ -f "$info_file" ]; then url=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$info_file','utf8')).url)" 2>/dev/null); if curl -s --max-time 1 "$url/api/status" >/dev/null 2>&1; then cat "$info_file"; else echo "dead"; fi; else echo "none"; fi
```

If the output is valid JSON with a `url`, the server is already running. Read `state_dir` and `session_dir` from the JSON.

If the output is "dead" or "none", start a new server:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/start-server.sh --project-dir <current working directory>
```

Parse the JSON output to extract:
- `url`, the browser URL
- `state_dir`, where to write diff data and read review results
- `session_dir`, for stopping the server later

### 6. Write Diff Data

Write the raw diff output to `<state_dir>/diff.patch` using the Write tool.

Write review metadata to `<state_dir>/review-meta.json`:
```json
{
  "baseline": "<baseline>",
  "cwd": "<current working directory>",
  "timestamp": <unix timestamp>
}
```

### 7. Tell the User to Open the URL

Say:
> **Code review is ready.** Open **<url>** in your browser to review the changes.
>
> You can:
> - Browse files in the sidebar
> - Toggle between unified and side-by-side diff views
> - Click on line numbers to add inline comments
> - Add file-level comments
> - **Approve** or **Request Changes** when done
>
> Review when you're ready, I'll wait here and pick up your decision automatically.

### 8. Wait for the Review

Run this bash command to block on the server's long-poll endpoint until the review is submitted:

```bash
curl -s --max-time 600 "<url>/api/wait-for-review"
```

Set the Bash tool timeout to 600000 (10 minutes). The endpoint holds the HTTP connection open until the user submits, or responds `{"delivered":false,"reason":"timeout"}` after 9 minutes (at which point the user is still reviewing, run the command again).

The response body is JSON:
- `{"delivered":true,"review":{...}}`, review was submitted; parse `review` and continue to step 9.
- `{"delivered":false,"reason":"timeout"}`, no review yet; re-run the curl.

### 9. Process the Review

Parse the `review` object from the response.

**If `decision` is `"approve"`:**
- Say: "Review approved. No changes requested."

**If `decision` is `"request-changes"`:**
- Present the comments as a structured list:

> **Review: Changes Requested**
>
> Summary: <summary if provided>
>
> Comments:
> 1. **path/to/file.js:42**, <comment body>
> 2. **path/to/other.js** (file-level), <comment body>
>
> I'll now address each comment.

- Begin addressing each comment in order.

### 10. Server Lifecycle

The server stays running for future `/ds` invocations. Do not stop it manually.
