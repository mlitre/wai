---
name: teach
description: Teach a subject across multiple sessions using a stateful workspace outside the repo. Use when the user wants to learn a large body of material over time (a protocol, a spec, an unfamiliar subsystem) rather than get one question answered now.
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, WebSearch, WebFetch
inspired-by:
  - mattpocock/skills/productivity/teach
---

# Teach

For a subject you will come back to: a protocol, a spec edition, an unfamiliar subsystem. Session five should know what session one covered.

## When this applies, and when it doesn't

Use this when the user will **return** to the subject across sessions and wants the ground covered systematically. If they want one question answered now, answer it in context and skip the workspace entirely. That distinction is the whole boundary: a bounded question is cheaper answered than filed.

## The workspace lives outside the repo

State goes in `~/.claude/teach/<subject-slug>/`, never inside a code repo.

Understanding of ISO 15118 or OCPP is not a property of whichever repo happened to be open when the learning started. Writing it into a repo scatters one subject across many checkouts, and the notes get deleted with the worktree.

```
~/.claude/teach/<subject>/
├── SYLLABUS.md     # the map: topics, order, status per topic
├── PROGRESS.md     # what happened per session, dated, plus open questions
└── topics/
    └── <topic>.md  # notes, worked examples, the user's own answers
```

## Process

**First session:**

1. Establish the destination. What should the user be able to *do* at the end? "Understand OCPP" is not a destination. "Read a CSMS log and tell whether the charger or the backend violated the protocol" is.
2. Assess the starting point. Ask what they already know, and check a claim or two against something concrete rather than taking the self-assessment at face value.
3. Write `SYLLABUS.md`: topics in dependency order, each with a one-line completion criterion. Confirm the order with the user before teaching anything.
4. Teach the first topic.

**Every later session:**

1. Read `PROGRESS.md` and `SYLLABUS.md` first. Never re-teach a topic marked done without being asked.
2. Open with a retrieval check on the previous topic, not a recap. If they cannot reconstruct it, that topic is not done, whatever the file says.
3. Teach the next topic.
4. Update `PROGRESS.md` and the topic's status before the session ends.

## Teaching rules

- **Ground every topic in the primary source.** For a spec, quote the clause and cite the section number. Paraphrase is where spec knowledge goes wrong, and a wrong paraphrase learned once is expensive to unlearn.
- **Check understanding by production, not recognition.** Ask them to explain it back, predict an outcome, or find the bug. "Does that make sense?" measures nothing.
- **A topic is done when its completion criterion is met**, not when it has been explained. Explaining is not learning, and marking it done is how a syllabus starts lying.
- **Record what they got wrong**, in their words, in the topic file. Those are the places to return to, and they are more useful than a record of what went smoothly.
- **Real artifacts over invented examples** whenever the subject has them: a real trace, a real message, a real file from the codebase.
