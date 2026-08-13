---
name: to-questionnaire
description: Turn a decision you can't answer alone into a Markdown questionnaire for the one person who can. Use when a decision is blocked on someone else's knowledge, when a grilling session hits a branch the user can't resolve, or when the user says they need to ask a colleague, a vendor, or another team.
allowed-tools: Read, Write, Grep, Glob
inspired-by:
  - mattpocock/skills/productivity/to-questionnaire
---

# To questionnaire

Some branches of a design tree are not yours to resolve. This turns one of them into a document you hand to the person who can, filled in async or worked through together in a meeting.

It is the named exit from `grill-me`. When grilling resolves a branch to "I need to ask someone", this is where that branch goes, instead of dying in a session summary.

## Grill the send, not the subject

The user cannot answer the subject. That is why the questionnaire exists. Interview them only about the **send**, which they can always answer.

1. **Who is it going to?** Role, expertise, and relationship to the user, in one exchange. This fixes the tone and how much context the document has to carry. Done when you know what the recipient knows that the user does not.

2. **What do you need back?** The specific decisions or facts the user cannot resolve alone, in one exchange. Done when you have a concrete list of what the user must walk away able to decide.

3. **Write it.** Aim every question at the gap between those two answers. Write to `questionnaires/<YYYY-MM-DD>-<slug>.md` and report the path. Done when the file exists and every item from step 2 is covered by a question.

Questions target the gap. A question the user could have answered themselves is a question wasting the recipient's one pass.

## Document structure

Order most-important-first, because async means you may only get one pass. Group under `##` headings by theme once there are more than a handful. One idea per question, never compound.

```markdown
# <Title>

**Purpose:** why this exists and the decision riding on it.

**From:** <user> **To:** <recipient> **How your answers will be used:** <where they go>

## Context

One paragraph orienting someone who was not in the user's head. Enough to answer well, not a page.

## How to answer

Deadline and rough effort. Partial answers and "I don't know" are useful: flag anything uncertain rather than skipping it.

## <Theme>

### <One question, one idea>

_Why this matters: <one line, only where the question could be misread or invite a throwaway answer>._

>

## Anything else?

Anything we didn't ask that we should know?
```

The `>` under each question is the answer stub. Leave it empty; it is where the recipient writes.
