# Smell baseline

Disclosed reference for `code-reviewer`. Read it when reviewing a diff; it is the floor that applies even when a repo documents no standards of its own.

Twelve smells from Fowler's *Refactoring* (ch. 3), each written *what it is* then *how to fix*. They are leading words: twelve pretrained concepts that focus attention on a class of thing to look for, which is why they carry more weight per line than a prose reminder to "look for duplication".

Two rules bind the whole list:

- **The repo overrides.** A documented repo standard always wins. Where `CLAUDE.md` or an equivalent endorses something the baseline would flag, suppress the smell.
- **Always a judgment call.** Each entry is a labeled heuristic ("possible Feature Envy"), never a hard violation. Documented-standard breaches can be hard findings; baseline smells cannot. Skip anything tooling already enforces.

| Smell | What it is | Fix |
|---|---|---|
| **Mysterious Name** | a function, variable, or type whose name does not reveal what it does or holds | rename it, and if no honest name comes, the design is murky |
| **Duplicated Code** | the same logic shape in more than one hunk or file in the change | extract the shared shape, call it from both |
| **Feature Envy** | a method reaching into another object's data more than its own | move the method onto the data it envies |
| **Data Clumps** | the same few fields or params keep traveling together, a type wanting to be born | bundle them into one type, pass that |
| **Primitive Obsession** | a primitive or string standing in for a domain concept that deserves its own type | give the concept its own small type |
| **Repeated Switches** | the same `switch` or `if` cascade on the same type recurs across the change | replace with polymorphism, or one map both sites share |
| **Shotgun Surgery** | one logical change forces scattered edits across many files in the diff | gather what changes together into one module |
| **Divergent Change** | one file or module edited for several unrelated reasons | split so each module changes for one reason |
| **Speculative Generality** | abstraction, parameters, or hooks added for needs the spec does not have | delete it, inline back until a real need shows |
| **Message Chains** | long `a.b().c().d()` navigation the caller should not depend on | hide the walk behind one method on the first object |
| **Middle Man** | a class or function that mostly just delegates onward | cut it, call the real target directly |
| **Refused Bequest** | a subclass or implementer that ignores or overrides most of what it inherits | drop the inheritance, use composition |

Name the smell and quote the hunk. A smell without a quoted hunk is a guess.
