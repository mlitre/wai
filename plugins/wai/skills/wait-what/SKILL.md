---
name: wait-what
description: Re-pitch a message that didn't land. Use the moment the user says they don't follow, asks what something means, says a explanation was confusing, or types "wait, what".
allowed-tools: Read, Grep, Glob
inspired-by:
  - mattpocock/skills/productivity/wait-what
---

# Wait, what

The message did not land. The default response to that is a **restatement**: same explanation, more words, same missing premise, and it fails for the same reason the first attempt did.

Re-pitch instead. A pitch is a new angle, not a louder repeat.

## Process

1. **Diagnose the miss before saying anything.** Which of these failed?
   - **Missing premise.** The explanation assumed a fact, a term, or a prior decision the user does not have.
   - **Wrong altitude.** Mechanism where they needed purpose, or purpose where they needed mechanism.
   - **Unearned jargon.** A term used before it was defined, or a term that means something else in this repo.
   - **Buried subject.** The actual point arrived after three clauses of setup.

2. **Supply what was missing, first.** Lead with the premise, not with the restated conclusion.

3. **Rewrite at a different altitude.** If the first attempt was mechanism, give purpose and consequence. If it was abstract, give one concrete case with real names from the codebase.

4. **Use the project's own words.** When `CONTEXT.md` exists, take the vocabulary from it. An explanation that renames the domain makes the reader translate twice.

Plain English throughout. No new jargon introduced while explaining away old jargon.

## Rules

- Never repeat a sentence from the failed attempt. If a sentence was going to work, it already would have.
- Say the point in the first sentence. Setup after, if at all.
- One idea per paragraph.
- If the miss was your error rather than an explanation gap, say what was actually true in one sentence and move on. No apology paragraph.
- If you cannot tell which premise is missing, ask one question, then re-pitch. Guessing twice costs more than asking once.
