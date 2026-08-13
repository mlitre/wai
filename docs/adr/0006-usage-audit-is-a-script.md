# The usage audit is a script, and the second toolchain exception

`scripts/usage-audit.sh` measures the roster against real transcripts: invocation counts from `"skill":"..."` and `"subagent_type":"..."` across `~/.claude/projects/**/*.jsonl`, plus the disk-artifact counts that outrank them, emitted as a dated report under `reports/`.

`CLAUDE.md` says this repo has no toolchain by design. That rule is deliberately broken here for the second time, after `check-index.sh`.

The 2026-08-13 usage audit cut the roster from 56 artifacts to 38 and produced every ADR numbered 0001 through 0004. It was the highest-leverage work this repo has done, and it existed only as a paragraph of prose describing how to redo it. A method that has to be hand-rebuilt is a method whose next run is not comparable to its last, which makes the trend, the only thing that actually falsifies a roster decision, unavailable.

The trigger was adding eight artifacts and materially reworking four in one pass. Every one of them is an untested hypothesis about what gets used, and the measurement is the only thing that can kill them later.

## Considered Options

Keeping the method as prose was the status quo and is what the rule prescribes. Rejected: the first re-run would reconstruct the queries at whatever fidelity the reconstruction achieved, and a roster measurement that is not comparable across runs cannot detect the drift it exists to detect.

Making the script fetch or parse structured JSON with `jq` was rejected in favor of `grep` over raw JSONL. The keys appear once per invocation wherever they sit in the record, so a path-based query buys precision at the cost of breaking whenever Anthropic reshapes a transcript record.

## Consequences

The script depends on a transcript format that is not ours and can change without notice. That is a real maintenance liability the prose paragraph did not have, and the mitigation is the grep-not-jq choice above plus the fact that a broken audit is loud rather than silent: no matches means an empty section, not a wrong number.

Two toolchain exceptions now exist. The rule stands as written for anything that builds, bundles, or tests the markdown; both exceptions lint or measure the repo against itself, which is the line. A third exception should be argued on that same basis or the rule should be rewritten.
