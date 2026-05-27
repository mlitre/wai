---
name: tdd
description: Canonical TDD reference, red-green-refactor loop, Iron Law (no production code without a failing test), verify-fail / verify-pass gates, vertical-slice rule, anti-patterns. Auto-applied inside `/implement-plan` via the `wai-implementer` agent invariant. Also auto-fires on explicit "use TDD" / "red-green-refactor" requests when the user wants manual control during bug fixing.
inspired-by:
  - mattpocock/skills/engineering/tdd
  - obra/superpowers/skills/test-driven-development
---

# Test-Driven Development

## Philosophy

**Core principle**: Tests should verify behavior through public interfaces, not implementation details. Code can change entirely; tests shouldn't.

**Good tests** are integration-style: they exercise real code paths through public APIs. They describe _what_ the system does, not _how_ it does it. A good test reads like a specification, "user can checkout with valid cart" tells you exactly what capability exists. These tests survive refactors because they don't care about internal structure.

**Bad tests** are coupled to implementation. They mock internal collaborators, test private methods, or verify through external means (querying a database directly instead of using the interface). The warning sign: your test breaks when you refactor, but behavior hasn't changed. If renaming an internal function breaks tests, those tests were testing implementation, not behavior.

See [tests.md](tests.md) for examples and [mocking.md](mocking.md) for mocking guidelines.

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

If you wrote production code before the test, delete it. Start over.

- Don't keep it as "reference".
- Don't "adapt" it while writing the test.
- Don't look at it.
- Delete means delete.

If you didn't watch the test fail, you don't know if it tests the right thing. Violating the letter is violating the spirit.

## Verify-fail and verify-pass are mandatory steps

Both gates run the test suite. Both are required. Skipping either means you're not doing TDD.

**Verify RED, watch it fail:**

- Test fails (not errors).
- Failure message matches what you expect.
- Fails because the feature is missing, not because of a typo.

Test passes? You're testing existing behavior. Fix the test.
Test errors? Fix the error, re-run until it fails for the right reason.

**Verify GREEN, watch it pass:**

- Target test passes.
- Other tests still pass.
- Output is pristine (no warnings, no errors).

Test fails? Fix the code, not the test.
Other tests fail? Fix now. Don't move on.

## Anti-Pattern: Horizontal Slices

**DO NOT write all tests first, then all implementation.** This is "horizontal slicing", treating RED as "write all tests" and GREEN as "write all code."

This produces **crap tests**:

- Tests written in bulk test _imagined_ behavior, not _actual_ behavior
- You end up testing the _shape_ of things (data structures, function signatures) rather than user-facing behavior
- Tests become insensitive to real changes, they pass when behavior breaks, fail when behavior is fine
- You outrun your headlights, committing to test structure before understanding the implementation

**Correct approach**: Vertical slices via tracer bullets. One test → one implementation → repeat. Each test responds to what you learned from the previous cycle. Because you just wrote the code, you know exactly what behavior matters and how to verify it.

```
WRONG (horizontal):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

RIGHT (vertical):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
  ...
```

## Workflow

### 1. Planning

When exploring the codebase, use the project's domain glossary so test names and interface vocabulary match the project's language. Respect ADRs in the area you're touching.

Before writing any code:

- [ ] Confirm with user what interface changes are needed
- [ ] Confirm with user which behaviors to test (prioritize)
- [ ] Identify opportunities for [deep modules](deep-modules.md) (small interface, deep implementation)
- [ ] Design interfaces for [testability](interface-design.md)
- [ ] List the behaviors to test (not implementation steps)
- [ ] Get user approval on the plan

Ask: "What should the public interface look like? Which behaviors are most important to test?"

**You can't test everything.** Confirm with the user exactly which behaviors matter most. Focus testing effort on critical paths and complex logic, not every possible edge case.

### 2. Tracer Bullet

Write ONE test that confirms ONE thing about the system:

```
RED:   Write test for first behavior → test fails
GREEN: Write minimal code to pass → test passes
```

This is your tracer bullet, proves the path works end-to-end.

### 3. Incremental Loop

For each remaining behavior:

```
RED:   Write next test → fails
GREEN: Minimal code to pass → passes
```

Rules:

- One test at a time
- Only enough code to pass current test
- Don't anticipate future tests
- Keep tests focused on observable behavior

### 4. Refactor

After all tests pass, look for [refactor candidates](refactoring.md):

- [ ] Extract duplication
- [ ] Deepen modules (move complexity behind simple interfaces)
- [ ] Apply SOLID principles where natural
- [ ] Consider what new code reveals about existing code
- [ ] Run tests after each refactor step

**Never refactor while RED.** Get to GREEN first.

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Too simple to test" | Simple code breaks. The test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing, you never saw them catch the bug. |
| "Tests after achieve the same goals" | Tests-after answer "what does this do?" Tests-first answer "what should this do?" |
| "Already manually tested" | Ad-hoc ≠ systematic. No record, can't re-run, easy to forget under pressure. |
| "Deleting X hours is wasteful" | Sunk-cost fallacy. Keeping code without real tests is technical debt. |
| "Keep it as reference and write tests first" | You'll adapt it. That's testing-after. Delete means delete. |
| "Need to explore first" | Fine. Throw the exploration away. Start fresh with TDD. |
| "Test is hard, that means design is unclear" | Yes, listen to the test. Hard to test = hard to use. |
| "TDD will slow me down" | TDD is faster than debugging after. |
| "Manual is faster" | Manual doesn't prove edge cases. You'll re-test every change. |
| "Existing code has no tests" | You're improving it. Add tests to the part you're touching. |
| "TDD is dogma, I'm being pragmatic" | TDD *is* pragmatic, finds bugs before commit, prevents regressions, enables refactoring. |
| "It's about spirit, not ritual" | The ritual is the spirit. Watch-the-test-fail isn't ceremony; it's the proof. |

## Checklist Per Cycle

```
[ ] Test describes behavior, not implementation
[ ] Test uses public interface only
[ ] Test would survive internal refactor
[ ] Code is minimal for this test
[ ] No speculative features added
```
