---
name: zoom-out
description: Give a higher-level map of an area of code, modules, callers, data flow, instead of diving into a single file. Use when user says "give me a map", "higher-level view", "I don't know this area", "zoom out", "what's the bigger picture", or asks how a system fits together at architectural level.
inspired-by: mattpocock/skills/engineering/zoom-out
---

# Zoom Out

The default failure mode is to go file-by-file. This skill forces a layer of abstraction.

When invoked, produce a map of the relevant area:

- **Modules**, names + what each one does in one sentence.
- **Callers**, who invokes whom. Real call sites, file:line.
- **Data flow**, what enters the system, how it's transformed, what leaves.
- **External boundaries**, DB, network, filesystem, OS calls.
- **Project glossary**, use the project's domain vocabulary throughout. If `.claude/wai.json` has a `context_md` path, read it for the canonical terms.

## Output shape

```
# Map, <area>

## Modules
- `path/to/module.ext`, <one-sentence purpose>
- `path/to/other.ext`, <one-sentence purpose>

## Call graph (relevant slice)
<entry point> at file:line
  → <function> at file:line
    → <function> at file:line
  → <function> at file:line

## Data flow
<input> → <transform> → <output>

## External boundaries
- <DB / HTTP / fs / OS> at file:line

## Open questions
<things even the map can't answer, needs a human or deeper read>
```

## Rules

- **No file dumps.** A map is not the code. If you find yourself pasting more than 5 lines from any one file, you've zoomed back in.
- **Real refs only.** Every claim gets a `file:line`. No "auth happens in the middleware layer somewhere".
- **Domain vocabulary.** Use the project's glossary. "Customer" if that's what the project calls it; not "user". Read `CONTEXT.md` (or the configured `context_md`) for the canonical terms if it exists.
- **One layer up.** If they ask about a function, map the *module* the function lives in. If they ask about a module, map the *subsystem*. Don't go two layers up, that's a different question.
