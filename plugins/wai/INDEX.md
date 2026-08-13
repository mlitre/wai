# wai Index

Catalog of every artifact the plugin ships. One line per artifact, alphabetical within each section. For workflow context (what runs in which step), see [WORKFLOW.md](./WORKFLOW.md). For upstream credits + rewrite notes, see [../../SOURCES.md](../../SOURCES.md).

## Skills

- **caveman**, Ultra-compressed communication mode (intensity levels: `lite`, `full`, `ultra`). One of three caveman-output surfaces; see also `cavecrew-builder`, `code-reviewer`.
- **cleanup-worktrees**, Prune git worktrees whose PRs already merged. Surfaces uncommitted/unpushed work first.
- **commit**, Conventional Commits, no AI attribution. Interactive by default; auto-fires on commit intent.
- **create-standards-checker**, Factory skill, generates a domain-specialized `<domain>-standards-compliance-checker` agent into `.claude/agents/` + seeds `.claude/compliance-specs.json`.
- **diagnose**, Disciplined diagnosis loop for hard bugs. Output is a Diagnosis Report only; trivial fix → `cavecrew-builder`, non-trivial → `/create-plan`.
- **ds**, Browser-based code review for the working tree (Diffscape). Engine exception, runs a local Node server. See [DIFFSCAPE.md](./DIFFSCAPE.md).
- **git-guardrails-claude-code**, Installs a Claude Code hook that blocks destructive git commands (push, reset --hard, clean, etc.).
- **grill-me**, Interview-style stress test of a plan or design. Auto-engages docs mode (glossary challenge, ADR offers) when `CONTEXT.md` exists.
- **handoff**, Compact the current session into a handoff doc; written to the OS temp directory so it doesn't pollute the workspace.
- **improve-codebase-architecture**, Architecture review producing an HTML report of deepening candidates, then a grilling loop on the picked one.
- **pr-triage**, Single-table digest of authored + review-assigned PRs with an "Action on me?" verdict per row.
- **setup**, One-time per-repo bootstrap. Writes `.claude/wai.json`, opt-in scaffolds `CONTEXT.md` + `docs/adr/`, injects WORKFLOW spine into `CLAUDE.md`.
- **tdd**, Canonical TDD reference (Iron Law, tracer bullets, verify-fail/verify-pass gates). Auto-applied inside `/implement-plan` via `wai-implementer`.
- **to-spec**, Produce a spec via interview or synthesize mode. Default writes local file; `--tracker` publishes a PRD issue.
- **using-subagents**, Primer for dispatching subagents, prompt-craft, model selection, verification.
- **write-a-skill**, Meta-skill for authoring skills with progressive disclosure + bundled resources.
- **writing-native-hooks**, Write `settings.json` hooks directly (no engine). Covers all 8 events.

## Agents

- **cavecrew-builder**, Surgical 1-2 file editor with hard refuse for 3+ file scope. Caveman-format diff receipts.
- **codebase-analyzer**, Explains HOW specific code works. Reads files, traces data flow, documents control flow with `file:line` references.
- **code-reviewer**, General code review against project CLAUDE.md with 0-100 confidence scoring (verbose default, compressed mode on caller request). Self-dispatches `silent-failure-hunter` / `pr-test-analyzer` / `comment-analyzer` / `type-design-analyzer` per heuristic; also serves as the `/implement-plan` quality-review step.
- **comment-analyzer**, Read-only audit of code comments for accuracy, completeness, and long-term value.
- **pr-test-analyzer**, Reviews a PR's test coverage for behavioral completeness with 1-10 criticality rubric.
- **silent-failure-hunter**, Hunts for silent failures, swallowed errors, and inappropriate fallback behavior. Zero tolerance.
- **type-design-analyzer**, Reviews type design with 1-10 ratings on encapsulation, invariant expression, usefulness, enforcement.
- **web-search-researcher**, Researches modern/niche topics with quotes, source links, and publication dates.
- **wai-implementer**, Implements a single DAG task from a wai plan. TDD invariant baked in. Dispatched by `/implement-plan`.
- **wai-spec-reviewer**, Reviews implementer output against task spec only. Pass/fail verdict, 1-2 line reason.

## Commands

- **/create-plan**, Build a DAG plan (`### T<n>` + `depends_on:` + checkbox steps). Parses cleanly into `/implement-plan`, `to-issues`, `/validate-plan`.
- **/describe-pr**, Generate a PR description from the diff using the repo's PR template. Writes `.claude/pr-descriptions/<branch-slug>.md`. No push, no `gh pr edit`.
- **/diagnose**, Run the `diagnose` skill's loop against a bug description (default) or against a PR's failing GitHub Actions logs (`--from-ci <pr>`).
- **/fix-findings**, Walk a flat findings list (handoff doc, review output, diagnosis report). Same chain as `/implement-plan`, fully parallel, no dependencies.
- **/implement-plan**, Walk the DAG. Dispatches `wai-implementer` → `wai-spec-reviewer` → `code-reviewer` per task, parallel up to `parallel_cap`. Retry-once → quarantine.
- **/iterate-plan**, Surgical edits to an existing implementation plan with new feedback.
- **/local-review**, Set up a worktree for reviewing a colleague's branch (`/local-review <user>:<branch>`).
- **/resume-handoff**, Resume work from a handoff document, read it, verify codebase state still matches, propose a plan, then start.
- **/setup**, Invoke the `setup` skill. `--update` re-injects WORKFLOW spine only.
- **/spec-registry**, CRUD CLI for `.claude/compliance-specs.json`. Subcommands: `list`, `check`, `add`, `update`, `remove`, `init`, `where`.
- **/to-spec**, Invoke the `to-spec` skill. Flags: `--interview` / `--synthesize` / `--tracker`.
