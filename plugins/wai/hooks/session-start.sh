#!/usr/bin/env bash
# Pre-launch the Diffscape server at session start so /ds is instant.
# Writes server info to a well-known location the skill can find.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(pwd)"

# Only start if we're in a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi

# Check if a server is already running for this project
INFO_FILE="${PROJECT_DIR}/.ds/server-info"
if [[ -f "$INFO_FILE" ]]; then
  existing_pid=$(cat "${PROJECT_DIR}/.ds/server.pid" 2>/dev/null)
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    # Server already running
    exit 0
  fi
  # Stale server, kill it and clean up
  kill "$existing_pid" 2>/dev/null
  rm -f "$INFO_FILE" "${PROJECT_DIR}/.ds/server.pid"
fi

# Also kill any other Diffscape servers for this project dir
for pid_file in "${PROJECT_DIR}"/.ds/sessions/*/state/server.pid; do
  [[ -f "$pid_file" ]] || continue
  old_pid=$(cat "$pid_file" 2>/dev/null)
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    kill "$old_pid" 2>/dev/null
  fi
done

# Start the server (publishes .ds/server-info and .ds/server.pid itself).
# Discard stdout (the server-started JSON is already written to .ds/server-info)
# but let stderr surface so start-server.sh failures (e.g. unwritable .ds/, port
# exhaustion) are visible to the user rather than silently swallowed.
"${PLUGIN_ROOT}/scripts/start-server.sh" --project-dir "$PROJECT_DIR" >/dev/null
