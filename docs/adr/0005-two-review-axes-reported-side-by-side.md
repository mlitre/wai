# Standards and Spec are two review axes, reported side by side

`code-reviewer` now emits two verdicts, `Verdict, standards` and `Verdict, spec`, and never merges or reranks them. `wai-spec-reviewer` stays a separate agent and gains a standalone mode, so the spec axis has two dispatch surfaces (the plan walker calls it directly, `code-reviewer` calls it as a fifth specialist) but only one implementation.

A change can follow every local convention while implementing the wrong thing, or do exactly what the spec asked while breaking every idiom. Collapsing both into one ranked list lets either axis mask the other. The gap this closes is narrower than it sounds: wai already ran both axes, but only inside `/implement-plan`, so every other review path (`/local-review` on a colleague's branch, an ad-hoc pre-PR review) ran with no spec axis at all, while `specs/` sat on disk unread.

## Considered Options

Folding the spec axis into `code-reviewer` as prose was rejected on two counts. It would put two implementations of "does this match what was asked" in the repo, and `code-reviewer` filters its own findings at confidence ≥ 80, which is exactly the reranking the separation exists to prevent. "The spec asked for X and X is missing" is not a confidence judgment, so spec findings pass through unfiltered, the same exemption specialist findings already get.

Deleting `wai-spec-reviewer` and keeping one reviewer was rejected because the agent is a gate in a state machine, not a report: its one-word verdict drives retry-once-then-quarantine and propagates `blocked` to DAG descendants. It is also the cheap gate before the expensive one (82 lines, four tools, no specialists), and its do-not-trust-the-report framing is meaningless where there is no report. Running both axes in one context also reintroduces the cross-contamination that dispatching them separately avoids.

## Consequences

A standalone review can come back `pass` on standards and `fail` on spec. Nothing resolves that for the caller by design, and any caller wanting a single boolean has to decide which axis it cares about. The spec ladder (issue reference in the commit range, caller-passed path, matching file under `specs/` or `plans/`, then ask) can also come up empty, in which case the axis reports `no spec found` rather than silently passing, so absence of a spec never reads as spec compliance.
