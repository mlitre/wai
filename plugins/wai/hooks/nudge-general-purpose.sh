#!/usr/bin/env bash
# PreToolUse on Agent/Task. When subagent_type is general-purpose, print the wai
# roster and allow the call. Advisory only, never blocks. See docs/adr/0002.
#
# Fail open: any parse problem exits 0 silently. A hook that errors on every
# agent dispatch is worse than the imbalance it is trying to fix.

set -u

# No jq, no nudge.
command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0

subagent_type=$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null) || exit 0
[ "$subagent_type" = "general-purpose" ] || exit 0

read -r -d '' message <<'EOF' || true
general-purpose dispatched. wai ships narrower agents that usually fit better:

- investigate + fix, full toolbelt, no plan needed -> wai:wai-implementer (freeform mode), one dispatch per finding when you have a list
- understand how existing code works, file:line traces -> wai:codebase-analyzer
- locate files -> the built-in Explore agent
- review a diff -> wai:code-reviewer
- external or current information with sources -> wai:web-search-researcher
- surgical 1-2 file mechanical edit -> wai:cavecrew-builder (no Bash, so it cannot build or test)

general-purpose is still the right call when the task genuinely needs the full toolbelt across many phases. Proceeding either way.
EOF

jq -cn --arg m "$message" '{systemMessage: $m}' 2>/dev/null || exit 0
exit 0
