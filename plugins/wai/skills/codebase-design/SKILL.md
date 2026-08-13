---
name: codebase-design
description: Shared vocabulary for designing deep modules. Use when designing or improving a module's interface, deciding where a seam goes, finding deepening opportunities, making code more testable, or when another skill needs the deep-module vocabulary.
allowed-tools: Read, Grep, Glob
inspired-by:
  - mattpocock/skills/engineering/codebase-design
---

# Codebase design

Design **deep modules**: a lot of behavior behind a small interface, placed at a clean seam, testable through that interface. Use this language wherever code is being designed or restructured. The aim is leverage for callers, locality for maintainers, testability for everyone.

This is the single home for that vocabulary. `tdd` and `improve-codebase-architecture` both point here rather than restating it.

## Glossary

Use these terms exactly. Don't substitute "component", "service", "API", or "boundary". Consistent language is the whole point.

**Module**
Anything with an interface and an implementation. Deliberately scale-agnostic: a function, class, package, or tier-spanning slice.
*Avoid*: unit, component, service.

**Interface**
Everything a caller must know to use the module correctly. The type signature, but also invariants, ordering constraints, error modes, required configuration, and performance characteristics.
*Avoid*: API, signature, both too narrow, since they refer only to the type-level surface.

**Implementation**
What is inside a module, its body of code. Distinct from **Adapter**: a thing can be a small adapter with a large implementation (a Postgres repo) or a large adapter with a small implementation (an in-memory fake). Reach for "adapter" when the seam is the topic, "implementation" otherwise.

**Depth**
Leverage at the interface: how much behavior a caller (or test) can exercise per unit of interface they have to learn. **Deep** means a large amount of behavior behind a small interface. **Shallow** means the interface is nearly as complex as the implementation.

**Seam** *(Michael Feathers)*
A place where you can alter behavior without editing in that place. The *location* at which a module's interface lives. Where to put the seam is its own design decision, distinct from what goes behind it.
*Avoid*: boundary, overloaded with DDD's bounded context.

**Adapter**
A concrete thing that satisfies an interface at a seam. Describes *role* (what slot it fills), not substance (what is inside).

**Leverage**
What callers get from depth. More capability per unit of interface learned. One implementation pays back across N call sites and M tests.

**Locality**
What maintainers get from depth. Change, bugs, knowledge, and verification concentrate in one place instead of spreading across callers. Fix once, fixed everywhere.

## Deep vs shallow

**Deep** = small interface, lots of implementation:

```
┌─────────────────────┐
│   Small Interface   │  ← few methods, simple params
├─────────────────────┤
│                     │
│ Deep Implementation │  ← complex logic hidden
│                     │
└─────────────────────┘
```

**Shallow** = large interface, little implementation. Avoid:

```
┌─────────────────────────────────┐
│        Large Interface          │  ← many methods, complex params
├─────────────────────────────────┤
│  Thin Implementation            │  ← just passes through
└─────────────────────────────────┘
```

When designing an interface, ask: can I reduce the number of methods, simplify the parameters, or hide more complexity inside?

## Principles

- **Depth is a property of the interface, not the implementation.** A deep module can be internally composed of small, mockable, swappable parts. They just are not part of the interface. A module can have **internal seams** (private to its implementation, used by its own tests) as well as the **external seam** at its interface.
- **The deletion test.** Imagine deleting the module. If complexity vanishes, it was a pass-through. If complexity reappears across N callers, it was earning its keep.
- **The interface is the test surface.** Callers and tests cross the same seam. If you want to test *past* the interface, the module is probably the wrong shape.
- **One adapter means a hypothetical seam. Two adapters means a real one.** Don't introduce a seam unless something actually varies across it.

## Designing for testability

1. **Accept dependencies, don't create them.**

   ```typescript
   // Testable
   function processOrder(order, paymentGateway) {}

   // Hard to test
   function processOrder(order) {
     const gateway = new StripeGateway();
   }
   ```

2. **Return results, don't produce side effects.**

   ```typescript
   // Testable
   function calculateDiscount(cart): Discount {}

   // Hard to test
   function applyDiscount(cart): void {
     cart.total -= discount;
   }
   ```

3. **Small surface area.** Fewer methods means fewer tests. Fewer params means simpler setup.

## Relationships

- A **Module** has exactly one **Interface**, the surface it presents to callers and tests.
- **Depth** is a property of a **Module**, measured against its **Interface**.
- A **Seam** is where a **Module**'s **Interface** lives.
- An **Adapter** sits at a **Seam** and satisfies the **Interface**.
- **Depth** produces **Leverage** for callers and **Locality** for maintainers.

## Rejected framings

- **Depth as the ratio of implementation lines to interface lines** (Ousterhout): rewards padding the implementation. Use depth-as-leverage instead.
- **"Interface" as the TypeScript `interface` keyword, or a class's public methods**: too narrow. Interface here is every fact a caller must know.
- **"Boundary"**: overloaded with DDD's bounded context. Say **seam** or **interface**.

## Going deeper

- Deepening a cluster given its dependencies: [DEEPENING.md](./DEEPENING.md), dependency categories, seam discipline, replace-don't-layer testing.
- Exploring alternative interfaces before committing: [DESIGN-IT-TWICE.md](./DESIGN-IT-TWICE.md).
