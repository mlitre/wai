# wai Index

Catalog of every artifact the plugin ships. One line per artifact, alphabetical within each section. For workflow context (what runs in which step), see [WORKFLOW.md](./WORKFLOW.md). For upstream credits + rewrite notes, see [../../SOURCES.md](../../SOURCES.md).

## Skills

- **caveman**, Ultra-compressed communication mode (intensity levels: `lite`, `full`, `ultra`). One of three caveman-output surfaces; see also `cavecrew-builder`, `code-reviewer`.
- **claude-automation-recommender**, Codebase-aware recommender for hooks, skills, agents, MCP servers, plugins.
- **claude-md**, Audit-mode + revise-mode CLAUDE.md tooling. Audit scores every CLAUDE.md against a 6-criterion rubric; revise captures session learnings.
- **cleanup-worktrees**, Prune git worktrees whose PRs already merged. Surfaces uncommitted/unpushed work first.
- **commit**, Conventional Commits, no AI attribution. Interactive by default; auto-fires on commit intent.
- **create-standards-checker**, Factory skill, generates a domain-specialized `<domain>-standards-compliance-checker` agent into `.claude/agents/` + seeds `.claude/compliance-specs.json`.
- **diagnose**, Disciplined diagnosis loop for hard bugs. Output is a Diagnosis Report only; trivial fix → `cavecrew-builder`, non-trivial → `/create-plan`.
- **ds**, Browser-based code review for the working tree (Diffscape). Engine exception, runs a local Node server. See [DIFFSCAPE.md](./DIFFSCAPE.md).
- **finishing-a-development-branch**, Menu after implementation: merge locally, ready-for-review checklist (print-only), keep, or discard.
- **git-guardrails-claude-code**, Installs a Claude Code hook that blocks destructive git commands (push, reset --hard, clean, etc.).
- **grill-me**, Interview-style stress test of a plan or design. Auto-engages docs mode (glossary challenge, ADR offers) when `CONTEXT.md` exists.
- **handoff**, Compact the current session into a handoff doc; written to the OS temp directory so it doesn't pollute the workspace.
- **improve-codebase-architecture**, Architecture review producing an HTML report of deepening candidates, then a grilling loop on the picked one.
- **issue-triage**, Issue-tracker state machine with role-driven actions; preps issues for AFK agents.
- **prototype**, Throwaway prototype to flesh out a design (CLI for state/logic, multi-variant route for UI).
- **pr-triage**, Single-table digest of authored + review-assigned PRs with an "Action on me?" verdict per row.
- **queue**, Bash-backed inter-agent task queue. Orchestrator enqueues tasks; `/loop` workers claim each and run it in a throwaway subagent. Atomic-claim race-safe, DAG deps, retry-then-cascade, stale-claim reaper. CLI scaffolded via `/queue init`.
- **receiving-code-review**, Verify-before-implementing reviewer-feedback discipline. No performative agreement.
- **requesting-code-review**, Review-specific subagent dispatch wrapper. For full multi-agent PR audits, use `/review-pr`.
- **security-patterns**, 9 high-signal security patterns + a ready-to-paste bash-only `PreToolUse` hook.
- **setup**, One-time per-repo bootstrap. Writes `.claude/wai.json`, opt-in scaffolds `CONTEXT.md` + `docs/adr/`, injects WORKFLOW spine into `CLAUDE.md`.
- **tdd**, Canonical TDD reference (Iron Law, tracer bullets, verify-fail/verify-pass gates). Auto-applied inside `/implement-plan` via `wai-implementer`.
- **to-issues**, Mirror a wai DAG plan to the project issue tracker. Per-plan opt-in.
- **to-spec**, Produce a spec via interview or synthesize mode. Default writes local file; `--tracker` publishes a PRD issue.
- **using-git-worktrees**, Detection-first worktree creation; native tool first, `git worktree add` fallback.
- **using-subagents**, Primer for dispatching subagents, prompt-craft, model selection, verification.
- **verification-before-completion**, "Evidence before claims" discipline applied to any completion claim.
- **write-a-skill**, Meta-skill for authoring skills with progressive disclosure + bundled resources.
- **writing-native-hooks**, Write `settings.json` hooks directly (no engine). Covers all 8 events.
- **zoom-out**, Higher-level map of an unfamiliar area. Auto-fires on "give me a map" / "I don't know this area".

## Agents

- **cavecrew-builder**, Surgical 1-2 file editor with hard refuse for 3+ file scope. Caveman-format diff receipts.
- **codebase-analyzer**, Explains HOW specific code works. Reads files, traces data flow, documents control flow with `file:line` references.
- **codebase-locator**, Finds WHERE code lives. Topic mode (categorized file map) or symbol mode (Defs/Refs/Callers `path:line` table).
- **codebase-pattern-finder**, Finds existing code patterns you can model new work after. Returns concrete snippets with `file:line`.
- **code-reviewer**, General code review against project CLAUDE.md with 0-100 confidence scoring (verbose default, compressed mode on caller request). Self-dispatches `silent-failure-hunter` / `pr-test-analyzer` / `comment-analyzer` / `type-design-analyzer` per heuristic; also serves as the `/implement-plan` quality-review step.
- **code-simplifier**, Simplifies recently modified code for clarity without altering behavior.
- **comment-analyzer**, Read-only audit of code comments for accuracy, completeness, and long-term value.
- **conversation-analyzer**, Mines conversation transcripts for behaviors worth preventing with hooks or worth committing to memory.
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
- **/implement-plan**, Walk the DAG. Dispatches `wai-implementer` → `wai-spec-reviewer` → `code-reviewer` per task, parallel up to `parallel_cap`. Retry-once → quarantine.
- **/iterate-plan**, Surgical edits to an existing implementation plan with new feedback.
- **/local-review**, Set up a worktree for reviewing a colleague's branch (`/local-review <user>:<branch>`).
- **/queue**, Orchestrator ops for the task queue: `init` scaffolds the CLI, `add`/`status`/`result`/`cancel` manage tasks. Pairs with `/queue-worker` and the `queue` skill.
- **/queue-worker**, Run a `/loop` worker that drains the queue: reap → claim → dispatch a per-task subagent → complete/fail. Loop context stays clear; the worker session is disposable.
- **/research-codebase**, Map an unfamiliar codebase by spawning parallel subagents, what exists, where it lives, how it works.
- **/resume-handoff**, Resume work from a handoff document, read it, verify codebase state still matches, propose a plan, then start.
- **/review-pr**, Multi-agent PR review. Dispatches code, tests, comments, errors, types, simplify agents and aggregates findings.
- **/setup**, Invoke the `setup` skill. `--update` re-injects WORKFLOW spine only.
- **/spec-registry**, CRUD CLI for `.claude/compliance-specs.json`. Subcommands: `list`, `check`, `add`, `update`, `remove`, `init`, `where`.
- **/to-spec**, Invoke the `to-spec` skill. Flags: `--interview` / `--synthesize` / `--tracker`.
- **/validate-plan**, Validate that an implementation matches its plan. Runs success criteria, diffs actual vs plan, surfaces deviations.
