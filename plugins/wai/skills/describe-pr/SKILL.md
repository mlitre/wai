---
name: describe-pr
description: Generate a PR description from the diff using the repo's PR template (or a default fallback). Writes to `.claude/pr-descriptions/<branch-slug>.md`, then offers to open the PR with `gh pr create`, but only when a user is present to confirm. NEVER pushes. Does NOT call `gh pr edit` without asking.
inspired-by: |
  humanlayer/.claude/commands/describe_pr.md
  humanlayer/.claude/commands/describe_pr_nt.md
  humanlayer/.claude/commands/ci_describe_pr.md
---

# Describe PR

You produce a PR description from the diff, ground it in evidence, write it to disk, then offer to open the PR.

> **INVARIANT, no code here.** This command does not modify source files.
>
> **INVARIANT, never push.** `git push` is the user's, always. This command may run `gh pr create` after an explicit confirmation, and nothing else outward-facing. See [docs/adr/0003](../../../docs/adr/0003-describe-pr-creates-prs-but-never-pushes.md).

## Workflow position

```
... → /implement-plan → /ds → /describe-pr → (confirm) gh pr create
```

The user has the final read on the description before it goes public. That's why the file is written first and the PR is a separate, confirmed step.

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

## Offer to open the PR

Print the path first, so the user can read the description before deciding:

```
PR description written to:
  <absolute-path-to-.claude/pr-descriptions/SLUG.md>
```

Then check the branch is on the remote:

```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null
```

**If there is no upstream, stop.** Print and do nothing further:

```
Branch <branch> is not on the remote. Push it yourself, then re-run:
  git push -u origin <branch>
```

Never run `git push`, not even with confirmation. It is outside this command entirely.

**Who may answer the confirmation.** `gh pr create` and `gh pr edit` are outward-facing: they publish to GitHub. Only the user can approve them, and only in the turn where they are asked. If this skill was invoked by another agent, or in any context with no user turn to answer, print the command and stop:

```
PR not opened. Run this yourself:
  gh pr create --body-file "<OUT_PATH>" --title "<generated title>"
```

A calling agent's agreement is not the user's. Narrows [ADR-0003](../../../docs/adr/0003-describe-pr-creates-prs-but-never-pushes.md), which set the per-invocation confirmation back when only a human could invoke this.

**If the branch is pushed and a user is present**, check for an existing PR with `gh pr view --json number` and offer exactly one action:

- **No PR exists**, ask: *"Open the PR now with this description?"* On an explicit yes, run:
  ```bash
  gh pr create --body-file "$OUT_PATH" --title "<generated title>"
  ```
- **A PR already exists**, ask: *"Update PR #N's description?"* On an explicit yes, run:
  ```bash
  gh pr edit <number> --body-file "$OUT_PATH"
  ```

Ask once. Silence, ambiguity, or anything short of a clear yes means do nothing and print the command for the user to run. Never chain both actions, never re-ask after a no.

## Why the file comes first

- Reviewing a PR description before it goes public is friction-cheap; reverting one after is not.
- The user may want to edit the file before the PR opens, easier with the description on disk.
- Re-runs are idempotent (write to the same path).
- The confirmation is per-invocation *and* per-user-turn, so the outward action can never happen as a side effect of generating a description, or as a side effect of an agent deciding on the user's behalf.
