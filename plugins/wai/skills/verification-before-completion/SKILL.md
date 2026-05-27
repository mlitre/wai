---
name: verification-before-completion
description: Use when about to claim work is complete, fixed, or passing, before committing or opening a PR. Requires running verification commands and confirming output before any success claim. Evidence before assertions, always.
inspired-by: github.com/obra/superpowers/skills/verification-before-completion
---

# Verification Before Completion

Claiming work is complete without verification is dishonesty, not efficiency.

**Core principle:** evidence before claims. Always.

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you haven't run the verification command *in this message*, you cannot claim it passes.

## The gate

```
BEFORE claiming any status or expressing satisfaction:

1. IDENTIFY: what command proves this claim?
2. RUN:      execute the full command, fresh, complete.
3. READ:     full output. Check exit code. Count failures.
4. VERIFY:   does output confirm the claim?
             - NO → state actual status with evidence.
             - YES → state claim with evidence.
5. ONLY THEN: make the claim.

Skip any step = lying, not verifying.
```

## Common failures

| Claim | Requires | Not sufficient |
|-------|----------|----------------|
| Tests pass | Test command output: 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Test of the original symptom: passes | Code changed, assumed fixed |
| Regression test works | Red-green cycle verified | Test passes once |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Requirements met | Line-by-line checklist | Tests passing |

## Red flags, stop

- Using "should", "probably", "seems to".
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!").
- About to commit / push / open a PR without verification.
- Trusting agent success reports.
- Relying on partial verification.
- Thinking "just this once".
- Tired and wanting the work over.
- Any wording implying success without having run verification.

## Rationalizations

| Excuse | Reality |
|--------|---------|
| "Should work now" | Run the verification. |
| "I'm confident" | Confidence ≠ evidence. |
| "Just this once" | No exceptions. |
| "Linter passed" | Linter ≠ compiler. |
| "Agent said success" | Verify independently. |
| "I'm tired" | Exhaustion ≠ excuse. |
| "Partial check is enough" | Partial proves nothing. |
| "Different words, so the rule doesn't apply" | Spirit over letter. |

## Key patterns

**Tests:**

```
YES: [run test command] [see: 34/34 pass] "All tests pass"
NO:  "Should pass now" / "Looks correct"
```

**Regression tests (red-green):**

```
YES: write → run (pass) → revert fix → run (MUST FAIL) → restore → run (pass)
NO:  "I've written a regression test" without red-green verification
```

**Build:**

```
YES: [run build] [exit 0] "Build passes"
NO:  "Linter passed", linter doesn't check compilation
```

**Requirements:**

```
YES: re-read plan → checklist → verify each → report gaps or completion
NO:  "Tests pass, phase complete"
```

**Agent delegation:**

```
YES: agent reports success → check VCS diff → verify changes → report actual state
NO:  trust agent report
```

## When to apply

Always before:

- Any variation of success / completion claim.
- Any expression of satisfaction.
- Any positive statement about work state.
- Committing, PR creation, task completion.
- Moving to the next task.
- Delegating to agents.

The rule applies to:

- Exact phrases.
- Paraphrases and synonyms.
- Implications of success.
- Any communication suggesting completion or correctness.

## Bottom line

No shortcuts. Run the command. Read the output. *Then* claim the result. Non-negotiable.
