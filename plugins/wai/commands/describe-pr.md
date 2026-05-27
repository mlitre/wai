---
description: Generate a PR description from the diff using the repo's PR template (or a default fallback). Writes to `.claude/pr-descriptions/<branch-slug>.md`. Does NOT push, does NOT call `gh pr edit`. Final step prints a manual checklist.
inspired-by: |
  humanlayer/.claude/commands/describe_pr.md
  humanlayer/.claude/commands/describe_pr_nt.md
  humanlayer/.claude/commands/ci_describe_pr.md
---

# Describe PR

You produce a PR description from the diff, ground it in evidence, write it to disk. The user pushes and opens the PR manually.

> **INVARIANT, no code here.** This command does not modify source files. It writes the description file. The user pushes the branch and runs `gh pr create` themselves. See `plugins/wai/WORKFLOW.md`.

## Workflow position

```
... → /validate-plan → /review-pr → /ds → /describe-pr → manual push + gh pr create
```

The user has the final read on the description before it goes public. That's why this command stops at the file.

## Identify the branch + diff base

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
BASE=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null)
```

If `BRANCH` is the default branch (`main` / `master`), ask the user which branch to describe and stop until they answer.

A slugified branch name for the output file:

```bash
SLUG=$(echo "$BRANCH" | tr '/' '-' | tr -cd 'A-Za-z0-9-_')
OUT_PATH=".claude/pr-descriptions/${SLUG}.md"
```

## Find the template

Use the first one that exists:

1. `.github/PULL_REQUEST_TEMPLATE.md`
2. `.github/pull_request_template.md`
3. `docs/PULL_REQUEST_TEMPLATE.md`

If none exists, fall back to this default:

```markdown
## What problem(s) was I solving?

## What user-facing changes did I ship?

## How I implemented it

## How to verify it

### Manual testing

## Description for the changelog
```

Read the template fully before filling anything in.

## Gather diff data

```bash
git diff "$BASE"..HEAD
git log "$BASE"..HEAD --oneline
```

Read the full diff. For files referenced in the diff but not fully shown, read them in-context. Identify:

- Problem being solved (the "why").
- User-facing changes vs internal-only.
- Breaking changes or migration steps.

## Existing description (idempotent re-run)

If `$OUT_PATH` already exists, read it. You're updating, not creating. Preserve manual edits the user made; only overwrite sections that are clearly auto-generated and stale relative to the diff.

## Fill out the template

- One section at a time, grounded in the diff. No filler.
- "How I implemented it" should reference file paths, not paraphrase the diff.
- "Description for the changelog", one line for an external audience.
- Specific over general. "Adds retry logic to webhook handler" beats "improves reliability."

### Verification checkboxes

If the template has a "How to verify it" checklist:

- For each item, ask: can I run this here? (`make test`, `npm test`, `pytest`, etc.)
- If yes and it passes → `- [x]` with the command shown.
- If yes and it fails → `- [ ]` with the actual error quoted.
- If no (manual testing, external service) → `- [ ]` with a note for the human.

Don't mark anything `[x]` you didn't actually run.

## Write the file

```bash
mkdir -p .claude/pr-descriptions
# atomic write
cat > "${OUT_PATH}.tmp" <<'EOF'
...filled-in description...
EOF
mv "${OUT_PATH}.tmp" "$OUT_PATH"
```

## Final report, manual checklist

Print the absolute path and the next steps for the user:

```
PR description written to:
  <absolute-path-to-.claude/pr-descriptions/SLUG.md>

Next (manual):
  git push -u origin <branch>
  gh pr create --body-file <relative-path>

To update the description on an existing PR:
  gh pr edit <number> --body-file <relative-path>
```

Do not run `gh pr edit`. Do not push. Do not open the PR. Those are the user's call.

## Why file-only

- Reviewing a PR description before it goes public is friction-cheap; reverting one after is not.
- The user may want to edit the file before pushing, easier with the description on disk.
- Re-runs are idempotent (write to the same path).
- Removes a class of automation accidents (pushing the wrong description to the wrong PR).
