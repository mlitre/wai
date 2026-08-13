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
# An agent is a .md with a `name:` in its frontmatter. agents/ is flat and one
# file per agent; disclosed reference lives in reference/. The check also
# catches an agent whose frontmatter is malformed.
disk_agents=$(find "$plugin/agents" -mindepth 1 -maxdepth 1 -name '*.md' \
              -exec sh -c 'grep -q "^name:" "$1" && basename "$1" .md' _ {} \; | sort -u)
# commands/ was folded into skills/: the plugin system treats both as skills,
# and only skills/ supports sibling reference files. Fail if one reappears.
if [[ -d "$plugin/commands" ]]; then
  echo "STRAY commands/ directory: plugin commands live in skills/<name>/SKILL.md" >&2
  exit 1
fi

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

# Provenance. CLAUDE.md requires both halves for every ported artifact: an
# inspired-by line in the frontmatter, and a row in SOURCES.md. Only local
# consistency is checked; upstream URLs are never fetched, so the lint stays
# offline and upstream reorganizing cannot turn this build red.
sources="$repo_root/SOURCES.md"

# Artifacts declaring an upstream, by name.
ported=$(
  find "$plugin/skills" -mindepth 2 -maxdepth 2 -name SKILL.md \
       -o -path "$plugin/agents/*.md" \
  | while read -r f; do
      # Frontmatter only: everything before the second '---'.
      if awk 'NR>1 && /^---$/{exit} NR>1' "$f" | grep -q '^inspired-by:'; then
        case "$f" in
          */SKILL.md) basename "$(dirname "$f")" ;;
          *)          basename "$f" .md ;;
        esac
      fi
    done | sort -u
)

# Names in the first cell of a SOURCES.md provenance-table row, backticked.
# Only the tables above "## Re-survey checklist" make roster claims; everything
# below it names upstream artifacts that were surveyed, ported or not. Rows
# naming a path (plugins/..., hooks/...) or a merge document something other
# than a live artifact, so they are excluded too.
sources_rows=$(
  awk '/^## Re-survey checklist/{exit} {print}' "$sources" \
  | grep -oE '^\|[^|]+\|' \
  | grep -vF '(merged into' \
  | grep -oE '`[^`]+`' \
  | sed -E 's/`//g' \
  | grep -vE '/|\.md$|\.sh$' \
  | sed -E 's/ \(Diffscape\)$//' \
  | sort -u
)

missing_row=$(comm -23 <(echo "$ported") <(echo "$sources_rows"))
if [[ -n "$missing_row" ]]; then
  echo "MISSING from SOURCES.md (artifact declares inspired-by, no row):"
  echo "$missing_row" | sed 's/^/  - /'
  drift=1
fi

all_disk=$(printf '%s\n%s\n' "$disk_skills" "$disk_agents" | sort -u)
orphan_row=$(comm -23 <(echo "$sources_rows") <(echo "$all_disk"))
if [[ -n "$orphan_row" ]]; then
  echo "ORPHAN rows in SOURCES.md (row names no artifact on disk):"
  echo "$orphan_row" | sed 's/^/  - /'
  drift=1
fi

if (( drift == 0 )); then
  echo "INDEX.md in sync with plugins/wai/{skills,agents}/."
  echo "SOURCES.md provenance in sync ($(echo "$ported" | wc -l | tr -d ' ') ported artifacts)."
  exit 0
fi
exit 1
