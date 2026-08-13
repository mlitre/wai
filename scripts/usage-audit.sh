#!/usr/bin/env bash
# Measures the wai roster against real transcripts instead of against intent.
#
# Two signals, in order of trust:
#   1. Disk artifacts, what an artifact left behind (plans, specs, PR
#      descriptions, handoffs). One-shot bootstrap skills have no recent
#      invocations by design, so invocation count alone under-reports them.
#   2. Invocation counts, "skill":"..." and "subagent_type":"..." occurrences
#      in the transcript JSONL.
#
# Emits a dated report to reports/usage-audit-<YYYY-MM-DD>.md. Diff two reports
# to see whether an artifact added since the last run ever fired.
#
# Usage: scripts/usage-audit.sh [--transcripts <dir>] [--out <file>] [--stdout]
# Exit 0 = report written. Exit 2 = no transcripts found.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
plugin="$repo_root/plugins/wai"
transcripts="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
today="$(date +%F)"
out="$repo_root/reports/usage-audit-$today.md"
to_stdout=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --transcripts) transcripts="$2"; shift 2 ;;
    --out)         out="$2"; shift 2 ;;
    --stdout)      to_stdout=1; shift ;;
    *) echo "usage: $0 [--transcripts <dir>] [--out <file>] [--stdout]" >&2; exit 64 ;;
  esac
done

if [[ ! -d "$transcripts" ]]; then
  echo "error: transcript directory not found: $transcripts" >&2
  exit 2
fi

mapfile -t jsonl < <(find "$transcripts" -name '*.jsonl' -type f)
if (( ${#jsonl[@]} == 0 )); then
  echo "error: no .jsonl transcripts under $transcripts" >&2
  exit 2
fi

# Counts keyed by name. grep over the raw JSONL rather than a jq walk: the key
# appears once per invocation regardless of where it sits in the record shape,
# which survives transcript-format churn that a path-based query would not.
counts_for() {
  local key=$1
  grep -hoE "\"$key\":\"[^\"]*\"" "${jsonl[@]}" 2>/dev/null \
    | sed -E "s/\"$key\":\"//; s/\"$//" \
    | sort | uniq -c | sort -rn
}

# Artifact names on disk, mirroring check-index.sh.
disk_names() {
  find "$plugin/skills" -mindepth 2 -maxdepth 2 -name SKILL.md \
    -exec sh -c 'basename "$(dirname "$1")"' _ {} \;
  find "$plugin/agents" -mindepth 1 -maxdepth 1 -name '*.md' \
    -exec sh -c 'basename "$1" .md' _ {} \;
}

# Files an artifact left behind. A directory that never appears is the strongest
# evidence an artifact is dead; a directory full of files outranks a low
# invocation count.
count_files() {
  local pattern=$1
  # shellcheck disable=SC2086
  find $HOME -maxdepth 6 -path "$pattern" -type f 2>/dev/null | wc -l | tr -d ' '
}

skill_counts="$(counts_for skill || true)"
agent_counts="$(counts_for subagent_type || true)"

# Roster entries with no invocation anywhere in the corpus. Strips the plugin
# prefix so wai:grill-me matches the on-disk grill-me.
seen="$(printf '%s\n%s\n' "$skill_counts" "$agent_counts" \
        | sed -E 's/^ *[0-9]+ //; s/^wai://' | sort -u)"
silent="$(comm -23 <(disk_names | sort -u) <(echo "$seen"))"

report="$(cat <<EOF
# Usage audit, $today

Corpus: ${#jsonl[@]} transcripts under \`$transcripts\`.
Roster: $(disk_names | wc -l | tr -d ' ') artifacts on disk in \`plugins/wai/\`.

Read the disk-artifact table first. Invocation counts under-report one-shot
bootstrap artifacts, which fire once per repo and then never again.

## Disk artifacts

| Output | Files |
|--------|-------|
| plans | $(count_files '*/plans/*.md') |
| specs | $(count_files '*/specs/*.md') |
| PR descriptions | $(count_files '*/.claude/pr-descriptions/*.md') |
| handoffs | $(count_files '*/handoffs/*.md') |
| diagnosis reports | $(count_files '*/plans/*diagnose*.md') |

## Skill invocations

\`\`\`
$skill_counts
\`\`\`

## Subagent dispatches

\`\`\`
$agent_counts
\`\`\`

## Silent roster entries

On disk, zero invocations in this corpus. Check the disk-artifact table before
cutting any of these, and check whether the artifact predates the corpus.

\`\`\`
${silent:-(none)}
\`\`\`
EOF
)"

if (( to_stdout )); then
  echo "$report"
  exit 0
fi

mkdir -p "$(dirname "$out")"
tmp="$(mktemp "$out.XXXXXX")"
printf '%s\n' "$report" > "$tmp"
mv "$tmp" "$out"
echo "wrote $out"
