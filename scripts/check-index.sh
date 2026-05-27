#!/usr/bin/env bash
# Lints plugins/wai/INDEX.md against the artifact tree.
# Flags artifacts present in skills/, agents/, or commands/ but missing from
# INDEX.md, and vice versa. No generation, no edits, just a diff.
#
# Usage: scripts/check-index.sh
# Exit 0 = clean. Exit 1 = drift.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
plugin="$repo_root/plugins/wai"
index="$plugin/INDEX.md"

if [[ ! -f "$index" ]]; then
  echo "error: $index missing" >&2
  exit 2
fi

# Names on disk
disk_skills=$(find "$plugin/skills" -mindepth 2 -maxdepth 2 -name SKILL.md \
              -exec sh -c 'basename "$(dirname "$1")"' _ {} \; | sort -u)
disk_agents=$(find "$plugin/agents" -mindepth 1 -maxdepth 1 -name '*.md' \
              -exec sh -c 'basename "$1" .md' _ {} \; | sort -u)
disk_commands=$(find "$plugin/commands" -mindepth 1 -maxdepth 1 -name '*.md' \
                -exec sh -c 'basename "$1" .md' _ {} \; | sort -u)

# Names listed in INDEX.md sections
section() {
  awk -v sec="$1" '
    /^## / { in_sec = ($0 == sec); next }
    in_sec && /^- \*\*/ {
      sub(/^- \*\*\/?/, ""); sub(/\*\*.*$/, ""); print
    }
  ' "$index" | sort -u
}

index_skills=$(section "## Skills")
index_agents=$(section "## Agents")
index_commands=$(section "## Commands")

drift=0
report() {
  local label=$1; local left=$2; local right=$3
  local missing extra
  missing=$(comm -23 <(echo "$left") <(echo "$right"))
  extra=$(comm -13 <(echo "$left") <(echo "$right"))
  if [[ -n "$missing" ]]; then
    echo "MISSING from INDEX ($label):"
    echo "$missing" | sed 's/^/  - /'
    drift=1
  fi
  if [[ -n "$extra" ]]; then
    echo "EXTRA in INDEX, not on disk ($label):"
    echo "$extra" | sed 's/^/  - /'
    drift=1
  fi
}

report "Skills"   "$disk_skills"   "$index_skills"
report "Agents"   "$disk_agents"   "$index_agents"
report "Commands" "$disk_commands" "$index_commands"

if (( drift == 0 )); then
  echo "INDEX.md in sync with plugins/wai/{skills,agents,commands}/."
  exit 0
fi
exit 1
