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

## Naming Rules

Adapted from Tiger Style. See `docs/references/tiger_style.md` for full rationale.

**MSB ordering.** Most significant word first, qualifiers last. Related fields
line up visually in source:

```odin
entity_count_max :: 1024   // not max_entity_count
speed_max        :: 10.0   // not max_speed
speed_min        :: 1.0    // not min_speed
```

**Nouns, not gerunds.** `pipeline`, not `pipelining`. You say "the pipeline is full"
in conversation — name it that way in code.

**Don't abbreviate.** `physical_size`, not `p_size`. Exception: universally
understood abbreviations (`dt`, `fps`, `uv`, `fov`).

**Symmetrical names match in weight.** `source`/`target` (2+2 syllables), not
`src`/`destination` (1+4).

**Don't overload across layers.** If a word means something in entities AND
in the renderer, rename one so it's always clear which layer you mean.

**Include units when ambiguous.** `camera_fov_degrees`, `tile_size_pixels`,
`speed_units_per_sec`.

---

## Assertions

Assert liberally. Check not only what you expect, but what you **don't** expect
(negative space). In debug builds, crash immediately on violation.

```odin
// Positive: what we expect
assert(entity_count > 0)

// Negative space: what should never be true
assert(!math.is_nan(view_proj[0][0]))
assert(scratch.used <= scratch.capacity)
```

- Arena limits are hard limits. Exceeding one is a design bug, not a runtime condition.
- Assertion failures in game logic indicate programmer error. Don't "handle" them.
- Debug builds: crash. Release builds: log + continue (games shouldn't crash on players).
- When adding a new data structure, answer: how much memory? Is it bounded? What's the max?

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
- [ ] **Naming.** MSB order, no abbreviations, nouns not gerunds, units when ambiguous.
- [ ] **Assertions.** Are preconditions and invariants asserted? Including negative space?

---

## Exceptions

Branches named `prototype-*`, `spike-*`, or `poc-*` are exempt from all of the above.
They exist to learn, not to ship. They will be thrown away. Mark them clearly:

```odin
// PROTOTYPE: this allocates like crazy, will be rewritten with arenas
```

When the spike is done, the learning feeds back into production code written properly.
The spike code itself gets deleted, not "cleaned up."
