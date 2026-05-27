---
description: Run the `diagnose` skill's loop against a bug description (default) or against a PR's failing GitHub Actions check logs (`--from-ci <pr>`). Output is a Diagnosis Report at `plans/<YYYY-MM-DD>-diagnose-<slug>.md`. Does NOT edit code.
argument-hint: "[--from-ci <pr-number-or-url>] <bug-description-or-empty>"
---

# Diagnose

Explicit invocation surface for the `diagnose` skill, with two input modes:

1. **Default**, bug description in `$ARGUMENTS`. Run the skill's loop, write the report.
2. **`--from-ci <pr>`**, fetch failing GitHub Actions logs for the PR, treat them as the bug signal, run the same loop.

> **INVARIANT, no code here.** This command does not modify source files. It writes a Diagnosis Report. Hand-off to `cavecrew-builder` (trivial fix) or `/create-plan` (non-trivial fix) per the skill. See `plugins/wai/WORKFLOW.md`.

## Default mode

```
/diagnose <bug description>
```

- Hand the description to the `diagnose` skill.
- Skill runs Phases 1-7, feedback loop, repro, minimize, hypothesize, instrument, write Diagnosis Report, hand off.
- Report path: `plans/<YYYY-MM-DD>-diagnose-<kebab-slug>.md`.

If `$ARGUMENTS` is empty, ask:

> What bug am I diagnosing? Give me a description, or pass `--from-ci <pr-number-or-url>` to ingest CI logs.

## `--from-ci` mode

```
/diagnose --from-ci 1234
/diagnose --from-ci https://github.com/owner/repo/pull/1234
```

### 1. Resolve the PR

```bash
# pr-number or URL → branch + head sha
gh pr view "$PR" --json number,headRefName,headRefOid,commits
```

### 2. Find failing checks

```bash
gh pr checks "$PR" --json name,state,link | jq '[.[] | select(.state=="FAILURE")]'
```

If no failures, report "No failing checks on PR #$PR" and stop.

### 3. Fetch logs for each failing check

```bash
# get the run-id from the check link, then:
gh run view <run-id> --log-failed
```

`--log-failed` prints only the failed-step output (cheaper than `--log` for long runs).

### 4. Extract the failure signal

For each failing check:

- Identify the failure mode (test failure / build error / lint violation / deploy issue).
- Extract the specific error message + traceback + assertion.
- Find the file:line refs in the failure output.
- Note which job/step failed (so the skill knows which boundary to instrument).

### 5. Hand the failure signal to the `diagnose` skill

Bundle into a synthetic "bug description" with the structure:

```
Bug: <one-line failure description>
Source: PR #$PR / check `<check-name>` / step `<step-name>`
Trace:
<paste the relevant traceback>

Failing assertion: <file:line>: <assertion text>
Expected: <X>
Actual: <Y>
```

Run the `diagnose` skill against this synthetic description. Phase 1's feedback loop should be the failing test or build command itself, the loop already exists, you just need to reproduce locally.

### 6. Same hand-off

Output: `plans/<YYYY-MM-DD>-diagnose-<slug>.md` Diagnosis Report. Trivial fix → `cavecrew-builder`. Non-trivial → `/create-plan`.

## Slug heuristic

For the report filename, derive a slug from:

- The first 5-8 meaningful words of the bug description (default mode).
- `<check-name>-<step-name>` (`--from-ci` mode).
- Truncate to ~50 chars total. Lowercase, kebab-case.

Example: `plans/2026-05-26-diagnose-token-expiry-off-by-one.md`.

## Hard rules

- **No code edits.** The skill writes a report. This command surfaces the report path. Neither writes source files.
- **Don't fix while diagnosing.** "While you're in there" confounds the diagnosis. Open a separate change via the hand-off.
- **Don't trust the bug report verbatim.** Phase 2 (Reproduce) is non-skippable, you must confirm the failure mode matches what the user / CI reported.
- **`--from-ci` requires `gh` auth.** Surface the auth error if `gh pr view` / `gh run view` fails.

## Workflow position

```
bug report → /diagnose → Diagnosis Report → cavecrew-builder | /create-plan → /implement-plan → ...
```
