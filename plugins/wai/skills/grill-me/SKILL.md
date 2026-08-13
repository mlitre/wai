---
name: grill-me
description: Interview the user relentlessly about a plan or design until every branch of the decision tree is resolved, one question at a time. Challenges the repo's glossary and offers ADRs when `CONTEXT.md` and `docs/adr/` exist. Use when the user wants a plan or design stress-tested, or says grill me, interview me, or challenge this.
inspired-by: mattpocock/skills/grill-me + mattpocock/skills/engineering/grill-with-docs
---

# Grill Me

Interview the user relentlessly about every aspect of this plan until you reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time. Wait for feedback on each before continuing.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Always-on grilling craft

These behaviors apply on every grilling session, regardless of whether the repo has docs.

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account', do you mean the Customer or the User? Those are different things." Never let an ambiguous term ride.

### Stress-test with concrete scenarios

When domain relationships or interfaces come up, invent specific scenarios that probe edge cases and force the user to be precise about boundaries. "Suppose the user cancels at the same instant the payment webhook fires, which side wins?"

### Branches that aren't the user's to resolve

Some branches resolve to "I need to ask someone else". Those are the ones that quietly stall: they land in a session summary and nobody carries them to the person who holds the answer.

When a branch resolves that way, offer `to-questionnaire`. It turns the open branch into a Markdown document aimed at the one person who can close it, filled in async or worked through in a meeting. Offer once, per branch, at the moment it surfaces. If the user declines, note the branch as open in the final summary and move on.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it. "Your code cancels entire Orders, but you just said partial cancellation is possible, which is right?" Treat this as the primary way to ground claims, not the secondary.

## Domain awareness, when `CONTEXT.md` exists

These behaviors activate only when the repo already has a `CONTEXT.md` (or `CONTEXT-MAP.md` for multi-context repos). If neither file exists, skip this entire section, do not create it during the session. The user opts into docs mode by creating the file themselves once.

### Repo layout

Single context, one root `CONTEXT.md`:

```
/
├── CONTEXT.md
├── docs/
│   └── adr/
│       ├── 0001-event-sourced-orders.md
│       └── 0002-postgres-for-write-model.md
└── src/
```

Multi-context, `CONTEXT-MAP.md` at the root points to per-context `CONTEXT.md` files:

```
/
├── CONTEXT-MAP.md
├── docs/
│   └── adr/                          ← system-wide decisions
├── src/
│   ├── ordering/
│   │   ├── CONTEXT.md
│   │   └── docs/adr/                 ← context-specific decisions
│   └── billing/
│       ├── CONTEXT.md
│       └── docs/adr/
```

Read the relevant `CONTEXT.md`(s) at the start of the grilling session.

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as voiding the order before payment, but you seem to mean refunding after capture, which is it?"

### Update `CONTEXT.md` inline

When a term is resolved, update `CONTEXT.md` right there. Don't batch these up, capture them as they happen. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

`CONTEXT.md` should be totally devoid of implementation details. Do not treat it as a spec, a scratch pad, or a repository for implementation decisions. Glossary and nothing else.

### Offer ADRs sparingly

Only offer to create an ADR when all three are true:

1. **Hard to reverse**, the cost of changing your mind later is meaningful.
2. **Surprising without context**, a future reader will wonder "why did they do it this way?".
3. **The result of a real trade-off**, there were genuine alternatives and you picked one for specific reasons.

If any of the three is missing, skip the ADR.

Additional constraint: only offer the ADR if `docs/adr/` already exists in the repo. If it doesn't, mention the candidate decision in the final summary and let the user decide whether to set up the directory themselves. **Never lazily create `docs/adr/` mid-session.**

When offering and accepted, use the format in [ADR-FORMAT.md](./ADR-FORMAT.md).
