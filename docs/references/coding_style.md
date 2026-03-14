# Coding Style Guide — Project Dream

This is law. Every code review checks against this. The only exception is branches
named `prototype-*`, `spike-*`, or `poc-*` — those are throwaway and explicitly marked as such.

---

## Core Principles

### 1. Compression-Oriented Programming

Write the specific, concrete thing first. Inline it. When the same pattern appears
a third time, compress — extract a function, a struct. Abstractions emerge from
repeated usage, never from speculation.

- Write usage code first, then implement to support it
- No premature abstraction. Repeat yourself until the pattern is obvious.
- No "future-proofing." Solve today's problem.
- If you can't point to three concrete uses, it's not a pattern yet.

### 2. Simplicity

The first priority. Complex code is hard to reason about, hard to debug, hard to change.

- Straightforward control flow. Top to bottom. A debugger can step through the hot path.
- No callback spaghetti, no event systems with layers of indirection.
- No inheritance, no virtual dispatch, no "design patterns."
- If the simple version works, ship it. Add complexity only when forced by a real problem.

### 3. Respect the Machine

Don't waste cycles or memory for no reason. This isn't about micro-optimization —
it's about not being careless.

- Don't copy a texture when you can pass a pointer.
- Don't iterate a list 3 times when once will do.
- Don't allocate in a hot loop.
- If the straightforward approach is also the efficient one (it usually is), just do that.

### 4. Performance

Last on the list because if you do 1-3 right, you get 80% for free.
The remaining 20% is surgical: profiler-guided, applied to specific hot paths,
never sprinkled everywhere as premature "optimization."

---

## Memory Rules

- **No malloc/free in game code. Ever.** Arenas only.
- Memory has clear ownership and lifetime:
  - `permanent` — lives forever (game state, world data, entity storage)
  - `cache` — loaded assets (textures, sprites, models), resizable
  - `scratch` — per-frame temp, wiped every frame
- "Allocating" means pushing bytes into the right arena.
- "Freeing" means resetting an arena. Not tracking individual objects.

---

## Data-Oriented Thinking

- Think about the data: what do I have, what do I need to produce, what's the transformation.
- Structs are bags of data. Functions operate on data.
- No OOP. No class hierarchies. No "manager" objects.
- Arrays of structs over linked lists (unless you have a proven reason).
- Think about what the CPU is actually doing. Cache matters.

---

## The "Casey Test"

Before submitting code, ask: would Casey fire me for this?

He would fire you for:
- Adding an abstraction layer nobody asked for
- malloc in a hot path
- A 6-level deep call stack to draw a rectangle
- "Flexible" code that handles 10 cases when you need 1
- Copying data you could have pointed to
- A config system when a hardcoded value works fine

He would NOT fire you for:
- Duplicating 3 lines instead of extracting a function
- Hardcoding a value you might change later
- Writing a 100-line function that does one clear thing
- Using a flat array when someone says you "should" use a tree

---

## Odin-Specific Conventions

- Use Odin's built-in arena allocator where it fits (`mem.Arena`).
- Prefer multiple return values over out-parameters (Odin makes this natural).
- Use `defer` for cleanup that must happen at scope exit.
- Use `#no_bounds_check` only in profiled hot paths with proven safety.
- Use `vendor:sdl3` — don't wrap SDL in another abstraction layer.
- Explicit over implicit: no `using` on struct fields unless it genuinely improves readability.

---

## Code Review Checklist

Every piece of code (generated or handwritten) gets checked against:

- [ ] **No wasted cycles.** If it's obvious not to waste, don't waste.
- [ ] **No unnecessary allocations.** Arena or don't allocate.
- [ ] **No premature abstraction.** Is this solving a real problem right now?
- [ ] **Straight control flow.** Can you read it top to bottom?
- [ ] **Data-oriented.** Are we thinking about the data, not "objects"?
- [ ] **Casey test.** Would he fire you?
- [ ] **Simplicity.** Is there a simpler way that works?

---

## Exceptions

Branches named `prototype-*`, `spike-*`, or `poc-*` are exempt from all of the above.
They exist to learn, not to ship. They will be thrown away. Mark them clearly:

```odin
// PROTOTYPE: this allocates like crazy, will be rewritten with arenas
```

When the spike is done, the learning feeds back into production code written properly.
The spike code itself gets deleted, not "cleaned up."
