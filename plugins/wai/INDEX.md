# wai Index

Catalog of every artifact the plugin ships. One line per artifact, alphabetical within each section. For workflow context (what runs in which step), see [WORKFLOW.md](./WORKFLOW.md). For upstream credits + rewrite notes, see [../../SOURCES.md](../../SOURCES.md). For decisions, see [../../docs/adr/](../../docs/adr/).

The plugin also ships hooks: three for Diffscape (see [DIFFSCAPE.md](./DIFFSCAPE.md)) and a `PreToolUse` nudge that suggests this roster when `general-purpose` is dispatched (see [WORKFLOW.md](./WORKFLOW.md#hooks)).

## Skills

- **caveman**, Ultra-compressed communication mode (intensity levels: `lite`, `full`, `ultra`). One of three caveman-output surfaces; see also `cavecrew-builder`, `code-reviewer`.
- **codebase-design**, Single home for the deep-module vocabulary (module, interface, seam, adapter, depth, leverage, locality) plus `DEEPENING.md` and `DESIGN-IT-TWICE.md`. `tdd` and `improve-codebase-architecture` point here instead of restating it.
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
- **resolving-merge-conflicts**, Resolve an in-progress merge or rebase hunk by hunk, by intent traced to each side's primary source. Never aborts.
- **rigorous-pr-review**, The review standard: review rules, structural standards, driving questions, remedy shapes, language lenses, test-strategy and approval bars, plus the twelve-smell baseline in sibling `SMELLS.md`. Read by the `code-reviewer` agent; invoke directly for an inline review with no dispatch.
- **setup**, One-time per-repo bootstrap. Writes `.claude/wai.json`, writes the workflow pointer into `CLAUDE.local.md` and excludes it via `.git/info/exclude`, opt-in scaffolds `CONTEXT.md` + `docs/adr/`.
- **tdd**, Canonical TDD reference (Iron Law, tracer bullets, verify-fail/verify-pass gates). Auto-applied by `wai-implementer` in both modes.
- **teach**, Multi-session teaching over a stateful workspace at `~/.claude/teach/<subject>/`, outside any repo.
- **to-questionnaire**, Turn a branch the user can't resolve alone into a Markdown questionnaire for the person who can. Named exit from `grill-me`.
- **to-spec**, Produce a spec via interview or synthesize mode. Writes a local file under `specs/`. Hard gate before any code.
- **using-subagents**, Primer for dispatching subagents, prompt-craft, model selection, verification.
- **wait-what**, Re-pitch a message that didn't land: diagnose the miss, supply the missing premise, change altitude. Never restates.
- **wizard**, Generate a resumable bash wizard for steps only a human can perform (secrets, vendor dashboards, cutovers).
- **writing-for-agents**, Standards doc for any document an agent consumes: context pointers, the two loads, the information hierarchy, completion criteria, leading words, pruning. Sibling `SKILL-MECHANICS.md` carries skill frontmatter, the invocation choice, and router skills. Replaced `write-a-skill`.
- **writing-native-hooks**, Write `settings.json` hooks directly (no engine). Covers all 8 events.

## Agents

- **cavecrew-builder**, Surgical 1-2 file editor with hard refuse for 3+ file scope. Caveman-format diff receipts.
- **codebase-analyzer**, Explains HOW specific code works. Reads files, traces data flow, documents control flow with `file:line` references.
- **code-reviewer**, The subagent review surface. Applies the `rigorous-pr-review` standard, adds scope resolution, specialist dispatch, folding, and an orchestrator-parseable output contract. Reports two verdicts, Standards and Spec, side by side and never merged. High-bar review against project CLAUDE.md plus structural standards (simplify-before-adding, 1000-line tripwire, high-confidence findings only), 0-100 confidence scoring, verbose default with compressed mode on request. Self-dispatches `silent-failure-hunter` / `pr-test-analyzer` / `comment-analyzer` / `type-design-analyzer` per heuristic; also the quality gate in `/implement-plan` and `/fix-findings`.
- **comment-analyzer**, Read-only audit of code comments for accuracy, completeness, and long-term value.
- **pr-test-analyzer**, Reviews a PR's test coverage for behavioral completeness with 1-10 criticality rubric.
- **silent-failure-hunter**, Hunts for silent failures, swallowed errors, and inappropriate fallback behavior. Zero tolerance.
- **type-design-analyzer**, Reviews type design with 1-10 ratings on encapsulation, invariant expression, usefulness, enforcement.
- **web-search-researcher**, Researches modern/niche topics with quotes, source links, and publication dates.
- **wai-implementer**, Writes and fixes code with tests. Freeform mode (ad-hoc "investigate and fix this") or DAG mode (a `T<n>` plan task). TDD invariant baked in.
- **wai-spec-reviewer**, The spec axis. Two modes: plan mode (implementer report + task spec, dispatched by `/implement-plan`) and standalone mode (spec + diff, no report, dispatched by `code-reviewer`). Pass/fail verdict, 1-2 line reason.

## Commands

- **/create-plan**, Build a DAG plan (`### T<n>` + `depends_on:` + checkbox steps). Parses cleanly into `/implement-plan`.
- **/describe-pr**, Generate a PR description from the diff using the repo's PR template. Writes `.claude/pr-descriptions/<branch-slug>.md`, then offers `gh pr create` behind a confirmation. Never pushes.
- **/diagnose**, Run the `diagnose` skill's loop against a bug description (default) or against a PR's failing GitHub Actions logs (`--from-ci <pr>`).
- **/fix-findings**, Walk a flat findings list (handoff doc, review output, diagnosis report). Same chain as `/implement-plan`, fully parallel, no dependencies.
- **/implement-plan**, Walk the DAG. Dispatches `wai-implementer` → `wai-spec-reviewer` → `code-reviewer` per task, parallel up to `parallel_cap`. Retry-once → quarantine.
- **/iterate-plan**, Surgical edits to an existing implementation plan with new feedback.
- **/local-review**, Set up a worktree for reviewing a colleague's branch (`/local-review <user>:<branch>`).
- **/resume-handoff**, Resume work from a handoff document, read it, verify codebase state still matches, propose a plan, then start.
- **/setup**, Invoke the `setup` skill. `--update` refreshes the `CLAUDE.local.md` pointer only.
- **/spec-registry**, CRUD CLI for `.claude/compliance-specs.json`. Subcommands: `list`, `check`, `add`, `update`, `remove`, `init`, `where`.
- **/to-spec**, Invoke the `to-spec` skill. Flags: `--interview` / `--synthesize`.
