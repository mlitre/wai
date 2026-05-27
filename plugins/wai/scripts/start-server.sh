#!/usr/bin/env bash
# Start the Diffscape review server and output connection info
# Usage: start-server.sh [--project-dir <path>] [--host <bind-host>] [--url-host <display-host>] [--foreground] [--background]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse arguments
PROJECT_DIR=""
FOREGROUND="false"
FORCE_BACKGROUND="false"
BIND_HOST="127.0.0.1"
URL_HOST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    --host)
      BIND_HOST="$2"
      shift 2
      ;;
    --url-host)
      URL_HOST="$2"
      shift 2
      ;;
    --foreground|--no-daemon)
      FOREGROUND="true"
      shift
      ;;
    --background|--daemon)
      FORCE_BACKGROUND="true"
      shift
      ;;
    *)
      echo "{\"error\": \"Unknown argument: $1\"}"
      exit 1
      ;;
  esac
done

if [[ -z "$URL_HOST" ]]; then
  if [[ "$BIND_HOST" == "127.0.0.1" || "$BIND_HOST" == "localhost" ]]; then
    URL_HOST="localhost"
  else
    URL_HOST="$BIND_HOST"
  fi
fi

# Some environments reap detached/background processes. Auto-foreground when detected.
if [[ -n "${CODEX_CI:-}" && "$FOREGROUND" != "true" && "$FORCE_BACKGROUND" != "true" ]]; then
  FOREGROUND="true"
fi

# Windows/Git Bash reaps nohup background processes. Auto-foreground when detected.
if [[ "$FOREGROUND" != "true" && "$FORCE_BACKGROUND" != "true" ]]; then
  case "${OSTYPE:-}" in
    msys*|cygwin*|mingw*) FOREGROUND="true" ;;
  esac
  if [[ -n "${MSYSTEM:-}" ]]; then
    FOREGROUND="true"
  fi
fi

# Kill any existing Diffscape servers for this project
if [[ -n "$PROJECT_DIR" ]]; then
  for pid_file in "${PROJECT_DIR}"/.ds/sessions/*/state/server.pid; do
    [[ -f "$pid_file" ]] || continue
    old_pid=$(cat "$pid_file" 2>/dev/null)
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null
    fi
    rm -f "$pid_file"
  done
fi

# Generate unique session directory
SESSION_ID="$$-$(date +%s)"

if [[ -n "$PROJECT_DIR" ]]; then
  SESSION_DIR="${PROJECT_DIR}/.ds/sessions/${SESSION_ID}"
else
  SESSION_DIR="/tmp/ds-${SESSION_ID}"
fi

STATE_DIR="${SESSION_DIR}/state"
PID_FILE="${STATE_DIR}/server.pid"
LOG_FILE="${STATE_DIR}/server.log"

mkdir -p "$STATE_DIR"

# Kill any existing server
if [[ -f "$PID_FILE" ]]; then
  old_pid=$(cat "$PID_FILE")
  kill "$old_pid" 2>/dev/null
  rm -f "$PID_FILE"
fi

# Resolve the harness PID (grandparent of this script).
OWNER_PID="$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ')"
if [[ -z "$OWNER_PID" || "$OWNER_PID" == "1" ]]; then
  OWNER_PID="$PPID"
fi

SERVER_SCRIPT="${SCRIPT_DIR}/../server/index.js"

# Foreground mode execs node directly and never returns, so it cannot publish
# .ds/server-info or .ds/server.pid after launch. That's acceptable: --foreground
# is used only in CI/Windows auto-fallback contexts where session-start.sh is not
# the caller (the hook uses the default background mode).
if [[ "$FOREGROUND" == "true" ]]; then
  echo "$$" > "$PID_FILE"
  env DS_DIR="$SESSION_DIR" DS_HOST="$BIND_HOST" DS_URL_HOST="$URL_HOST" DS_OWNER_PID="$OWNER_PID" DS_PROJECT_DIR="$PROJECT_DIR" node "$SERVER_SCRIPT"
  exit $?
fi

# Start server in background
nohup env DS_DIR="$SESSION_DIR" DS_HOST="$BIND_HOST" DS_URL_HOST="$URL_HOST" DS_OWNER_PID="$OWNER_PID" DS_PROJECT_DIR="$PROJECT_DIR" node "$SERVER_SCRIPT" > "$LOG_FILE" 2>&1 &
SERVER_PID=$!
disown "$SERVER_PID" 2>/dev/null
echo "$SERVER_PID" > "$PID_FILE"

# Wait for server-started message
for i in {1..50}; do
  if grep -q "server-started" "$LOG_FILE" 2>/dev/null; then
    alive="true"
    for _ in {1..20}; do
      if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        alive="false"
        break
      fi
      sleep 0.1
    done
    if [[ "$alive" != "true" ]]; then
      echo "{\"error\": \"Server started but was killed. Retry with: $0 --project-dir ${PROJECT_DIR:-/tmp} --foreground\"}"
      exit 1
    fi
    started_line=$(grep "server-started" "$LOG_FILE" | head -1)
    if [[ -n "$PROJECT_DIR" ]]; then
      mkdir -p "${PROJECT_DIR}/.ds"
      echo "$started_line" > "${PROJECT_DIR}/.ds/server-info"
      if [[ -f "${STATE_DIR}/server.pid" ]]; then
        cp "${STATE_DIR}/server.pid" "${PROJECT_DIR}/.ds/server.pid"
      fi
    fi
    echo "$started_line"
    exit 0
  fi
  sleep 0.1
done

echo '{"error": "Server failed to start within 5 seconds"}'
exit 1
