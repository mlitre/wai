---
name: receiving-code-review
description: Use when receiving code review feedback, before implementing suggestions, especially if feedback seems unclear or technically questionable. Requires verification and technical rigor, not performative agreement or blind implementation.
inspired-by: github.com/obra/superpowers/skills/receiving-code-review
---

# Receiving Code Review

Code review needs technical evaluation, not emotional performance.

**Core principle:** verify before implementing. Ask before assuming. Technical correctness over social comfort.

## Response pattern

```
WHEN receiving review feedback:

1. READ:       full feedback, no reacting
2. UNDERSTAND: restate the requirement in your own words (or ask)
3. VERIFY:     check against codebase reality
4. EVALUATE:   technically sound for this codebase?
5. RESPOND:    technical ack OR reasoned pushback
6. IMPLEMENT:  one at a time, test each
```

## Forbidden responses

Never:

- "You're absolutely right!"
- "Great point!" / "Excellent feedback!"
- "Let me implement that now" (before verification)
- Any "Thanks for catching that"-style gratitude

Instead:

- Restate the technical requirement.
- Ask clarifying questions.
- Push back with technical reasoning if the suggestion is wrong.
- Just start working, actions over words.

## Unclear feedback

If any item is unclear: stop. Do not implement anything yet. Ask for clarification on the unclear items.

Reason: items may be related. Partial understanding produces wrong implementation.

Example:

```
User: "Fix 1-6"
You understand 1, 2, 3, 6. Unclear on 4, 5.

WRONG:  implement 1, 2, 3, 6 now, ask about 4, 5 later.
RIGHT:  "I understand 1, 2, 3, 6. Need clarification on 4 and 5 before proceeding."
```

## Source-specific handling

**From the user (trusted):**

- Implement after understanding.
- Still ask if scope is unclear.
- No performative agreement.
- Skip to action or technical acknowledgement.

**From external reviewers:**

Before implementing, check:

1. Technically correct for this codebase?
2. Breaks existing functionality?
3. Reason for the current implementation?
4. Works on all targeted platforms / versions?
5. Does the reviewer have full context?

If the suggestion seems wrong → push back with technical reasoning.

If you can't easily verify → say so: "I can't verify this without `[X]`. Investigate / ask / proceed?"

If it conflicts with prior user decisions → stop and discuss before changing course.

## YAGNI check on "implement properly" feedback

If a reviewer says "implement this properly":

1. Grep for actual usage.
2. If unused: "This endpoint isn't called. Remove it (YAGNI)?"
3. If used: implement properly.

## Implementation order

For multi-item feedback:

1. Clarify anything unclear first.
2. Then implement in this order:
   - Blocking issues (breakage, security).
   - Simple fixes (typos, imports).
   - Complex fixes (refactoring, logic).
3. Test each fix individually.
4. Verify no regressions.

## When to push back

Push back when:

- Suggestion breaks existing functionality.
- Reviewer lacks full context.
- Violates YAGNI (unused feature).
- Technically incorrect for the stack.
- Legacy / compatibility reasons exist.
- Conflicts with the user's architectural decisions.

How:

- Technical reasoning, not defensiveness.
- Specific questions.
- Reference working tests / code.
- Loop in the user when the question is architectural.

## Acknowledging correct feedback

```
GOOD: "Fixed. [brief description of what changed]"
GOOD: "Good catch, [specific issue]. Fixed in [location]."
GOOD: [just fix it; the diff says it]

BAD: "You're absolutely right!"
BAD: "Great point!"
BAD: "Thanks for catching that!"
BAD: any gratitude expression
```

Why no thanks: actions speak. Just fix it. The code shows you heard the feedback.

If you catch yourself about to write "Thanks": delete it. State the fix instead.

## Correcting your own pushback

If you pushed back and were wrong:

```
GOOD: "You were right, I checked [X] and it does [Y]. Implementing now."
GOOD: "Verified. You're correct. My initial read was wrong because [reason]. Fixing."

BAD: long apology
BAD: defending why you pushed back
BAD: over-explaining
```

State the correction factually. Move on.

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Performative agreement | State requirement or just act |
| Blind implementation | Verify against codebase first |
| Batch without testing | One at a time, test each |
| Assume reviewer right | Check whether it breaks things |
| Avoiding pushback | Technical correctness over comfort |
| Partial implementation | Clarify all items first |
| Can't verify, proceed anyway | State the limitation, ask |

## Examples

**Performative (bad):**

```
Reviewer: "Remove legacy code"
BAD: "You're absolutely right! Let me remove that..."
```

**Technical verification (good):**

```
Reviewer: "Remove legacy code"
GOOD: "Checking, build target is 10.15+, this API needs 13+. Legacy needed for backward compat. Either fix bundle ID or drop pre-13 support, which?"
```

**YAGNI (good):**

```
Reviewer: "Implement proper metrics tracking with database, date filters, CSV export"
GOOD: "Grepped, nothing calls this endpoint. Remove it (YAGNI)? Or am I missing usage?"
```

## GitHub thread replies

When replying to inline review comments on GitHub, reply in the comment thread:

```
gh api repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies
```

Not as a top-level PR comment.

## Bottom line

External feedback = suggestions to evaluate, not orders to follow.

Verify. Question. Then implement. No performative agreement. Technical rigor always.
