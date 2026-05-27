---
name: to-issues
description: Mirror a wai DAG plan to the project issue tracker. Per-plan opt-in, does NOT auto-fire from `/create-plan`. Reads the DAG (T<n>/depends_on/checkbox steps), creates one issue per task, back-writes `Depends on #N` to bodies, then back-writes `issue: #N` to the local plan. Use when user says "open issues from this plan", "mirror plan to tracker", or runs `to-issues plans/...`.
inspired-by: mattpocock/skills/engineering/to-issues
---

# To Issues

Convert a wai DAG plan into per-task tracker issues. One issue per task. Dependencies preserved. Local plan back-written with issue numbers so downstream tooling (and humans) can cross-reference.

> **INVARIANT, no source edits.** This skill writes to the tracker and adds `issue: #N` lines to the plan file. It does not edit source files. See `plugins/wai/WORKFLOW.md`.

## Tracker setup

Reads `.claude/wai.json`:

```json
{
  "tracker": "github",
  "tracker_repo": "owner/repo",
  "labels": {
    "task": "type:task"
  }
}
```

If `tracker` is missing or unset, abort:

> No tracker configured. Run `/setup` first, or pass an explicit `--repo owner/name`.

If `tracker` is `none`, abort:

> Tracker explicitly disabled. Re-run `/setup` to enable, or pass `--repo`.

## Invocation

```
to-issues plans/<file>.md           # mirror this plan
to-issues plans/<file>.md --dry-run # show what would happen
to-issues plans/<file>.md --repo owner/name  # override .claude/wai.json
```

## Parse contract (must match `/create-plan` T3 output)

A task in the plan looks exactly like:

```markdown
### T7, task title here
depends_on: [T3, T5]

- [ ] step 1
- [ ] step 2
```

After `to-issues` runs, the same task carries an `issue: #N` line:

```markdown
### T7, task title here
depends_on: [T3, T5]
issue: #142

- [ ] step 1
- [ ] step 2
```

### Parser pseudocode

```
in_tasks_section = false
for line in plan:
  if line == "## Tasks":      in_tasks_section = true; continue
  if line.startswith("## "):  in_tasks_section = false; continue
  if not in_tasks_section:    continue
  if matches r"### T(\d+), (.+)": new task, id, title
  if matches r"depends_on:\s*\[(.*)\]": list of T-ids
  if matches r"issue:\s*#(\d+)": existing issue number (skip on re-run)
  if matches r"- \[ \]" or "- \[x\]": checkbox step
```

Re-runs: tasks that already have an `issue: #N` line are skipped (don't double-publish). Idempotent.

## Process

### 1. Parse the plan

Read the file fully. Extract tasks via the parser above. Capture:

- Goal section (used as the cross-issue "Parent" context).
- Each task's id, title, depends_on, checkbox steps, existing `issue:` if any.

If any task is missing `depends_on:`, abort with the specific task id, the plan is malformed.

### 2. Show the breakdown + confirm

```
Plan: plans/<file>.md
Tracker: <tracker_repo>
Tasks to publish: <count> (skipping <skip-count> that already have issue numbers)

T1  <title>          (root)
T2  <title>          (root)
T3  <title>          ← T1
...

Proceed?
```

Wait for confirmation. `--dry-run` skips the publish and just prints this.

### 3. First pass, create one issue per task

For each unpublished task, in topological order (dependencies first so issue numbers exist when referenced):

```bash
gh issue create \
  --repo "$TRACKER_REPO" \
  --title "$TITLE" \
  --body-file "$TMP_BODY" \
  --label "$TASK_LABEL"
```

Body template:

```markdown
## Source

Task **T<n>** from `plans/<file>.md`.

## What to build

<task title>

<checkbox steps verbatim from the plan>

## Depends on

(filled in by second pass, see below)

## Acceptance

- All checkbox steps complete.
- Spec compliance reviewed (`wai-spec-reviewer` pass).
- Code quality reviewed (`code-reviewer` pass).
```

Capture the new issue number per task into `{T<n>: #N}` map.

### 4. Second pass, back-write `Depends on` to issue bodies

For each task with non-empty `depends_on`, edit the issue body to fill in the "Depends on" section with the resolved issue numbers:

```bash
gh issue edit "$NEW_ISSUE" --repo "$TRACKER_REPO" --body "$UPDATED_BODY"
```

Replace the placeholder section with:

```markdown
## Depends on

- #<dep-issue-number> (T<n>: <dep-title>)
- #<dep-issue-number> (T<m>: <dep-title>)
```

Or, if `depends_on: []`, write:

```markdown
## Depends on

None, can start immediately.
```

### 5. Third pass, back-write `issue: #N` to the plan file

Edit `plans/<file>.md` with `Edit` (one edit per task). Insert `issue: #N` between `depends_on:` and the first checkbox step. Atomic per-task.

After all edits, show the user the path and a count summary:

```
Published <N> issues to <tracker_repo>:
  T1 → #<a>
  T2 → #<b>
  ...

Back-wrote issue numbers to plans/<file>.md.

Cross-check on tracker:
  <tracker URL filter for the label>
```

## Failure modes

- **`gh` auth missing** → surface error, stop. User runs `gh auth login`.
- **Network failure mid-publish** → some tasks have issues, others don't. The next run is idempotent (skips already-published tasks) so re-running picks up where you stopped.
- **Plan malformed** → name the offending task id + line, abort. Don't try to repair.
- **Dependency cycle in `depends_on`** → topological sort fails. Print the cycle, abort.

## Hard rules

- **Read the DAG format only.** No phases. If the plan still uses phases, abort with a pointer to `/create-plan`.
- **Idempotent.** Re-running on the same plan must not duplicate issues.
- **Atomic edits to the plan file.** Use `Edit`, one task at a time.
- **No tracker writes if `--dry-run` is set.**
- **Don't close or modify parent issues** if the plan was derived from one.

## Why this replaces the old to-issues

The previous version assumed a free-form plan with vertical-slice issues. The new format is structured (DAG), so the parse is deterministic and the back-link to the plan file (`issue: #N`) survives plan iteration, `/iterate-plan` can add new tasks, re-run `to-issues`, and only the new tasks get published.
