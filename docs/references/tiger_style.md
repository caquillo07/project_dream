# Tiger Style — Adapted for Project Dream

Distilled from Joran Dirk Greef (TigerBeetle) on the Bug Bash podcast.
Filtered to what actually applies to a solo game project in Odin + SDL3.
Skip the distributed systems stuff. Keep the engineering discipline.

---

## The Three Pillars

Tiger Style is a tetrahedron: **performance**, **safety**, **user experience**.
Everything below supports those three. They reinforce each other — safer code
is faster to develop long-term, faster code enables better UX, predictable
UX requires safety.

---

## 1. Static Memory Allocation (We Already Do This)

Our three arenas (permanent, cache, scratch) ARE Tiger Style static allocation.
The principle: allocate everything at startup, never malloc/free at runtime.
Memory usage never changes after init.

What Joran says this buys you:
- **Forcing function for good design.** You can't lazily malloc in a component,
  so you're forced to think about data structure sizes and lifetimes up front.
- **Your program gets a "shape."** A well-defined boundary you can reason about
  and test. Without shape, you can't know if you have leaks or exhaustion.
- **Eliminates fragmentation, use-after-free, double-free.** Entire categories
  of bugs disappear.
- **Performance.** You end up with better data locality because you're forced
  to think about memory layout.

His metaphor: dynamic allocation makes software like a bouncy castle — no hard
shape, wobbling around. Static allocation gives it a fixed, testable shape.

**What we should add:**
- Assert arena usage against hard limits. If permanent exceeds its budget,
  that's a design bug — crash, don't silently grow.
- When adding new data structures, always answer: how much memory does this
  use? Is it bounded? What's the max?

---

## 2. Assertions — Including "Negative Space"

Standard assertions check what you expect. Tiger Style also checks what you
**don't** expect. You're not only verifying the contract — you're checking
for breach of the contract.

Think of it as shading in a region on a graph. Standard assertions say "we're
inside the valid region." Negative-space assertions say "we have NOT crossed
into the invalid region." Sometimes these overlap, sometimes they catch
different things.

**Examples for our game:**

```odin
// Positive: what we expect
assert(entity_count > 0, "must have at least the null entity")
assert(player.position.y >= 0, "player shouldn't fall through ground")

// Negative space: what should never be true
assert(!math.is_nan(camera.view_proj[0][0]), "view_proj contains NaN")
assert(scratch_arena.used <= scratch_arena.capacity, "scratch overflow")
assert(entity_count < MAX_ENTITIES, "entity array full")
```

**The CPRNG example (worth remembering):** TigerBeetle asserts that a 128-bit
random number is never zero. Technically zero is valid, but if you get one,
it's astronomically more likely your entropy source is busted. Assert the
*probable* invariant, not just the *theoretical* one. Choose the lesser of
two weevils.

**Fail fast.** In debug builds, crash immediately on any assertion failure.
The earlier you crash, the closer the stack trace is to the actual bug.
Don't try to "handle" or "recover from" invariant violations in game logic —
those indicate programmer error, not runtime conditions.

---

## 3. Online Verification

While the program runs, dedicate whole functions to reading state back and
checking it. Not inline assertions — entire verification passes.

This matters less for a game (state is ephemeral, resets every launch) than
for a database, but it's still useful during development:

- After loading a chunk/area, verify all tile indices are valid
- After entity update, verify no position is NaN or infinity
- Periodic debug-mode check that entity array invariants hold
  (null at 0, no gaps, counts match)

Keep these behind a debug flag. They're development tools, not shipping code.

---

## 4. Naming Conventions

### Most Significant Byte Ordering

Put the grouping noun first, qualifiers last. Related fields line up visually:

```odin
// Bad (typical)
max_entities     :: 1024
max_speed        :: 10.0
min_speed        :: 1.0
max_zoom         :: 50.0
min_zoom         :: 5.0

// Good (Tiger Style)
entity_count_max :: 1024
speed_max        :: 10.0
speed_min        :: 1.0
zoom_max         :: 50.0
zoom_min         :: 5.0
```

Now `speed_*` groups together, `zoom_*` groups together. You can scan and
instantly see relationships.

### Nouns Over Gerunds

Name things as nouns, not present participles. You need to talk about these
in conversation and nouns work in sentences.

```
// Bad: "the pipelining is full" — awkward
pipelining: bool

// Good: "the pipeline is full" — natural
pipeline: Pipeline_State
```

### Don't Abbreviate

`physical_size` not `p_size`. `allocation_size` not `a_size`. OpenZFS had a
bug where they confused `p_size` and `a_size`. With full names, the bug would
have been obvious.

Exception: universally understood abbreviations (`dt`, `fps`, `uv`, `fov`).
If your team wouldn't need to look it up, it's fine.

### Symmetrical Names Match in Weight

If two things are related, their names should feel related:

```
// Bad: 1 syllable vs 4 syllables, 3 chars vs 11 chars
src, destination

// Good: matched weight
source, target
```

### Don't Overload Names Across Layers

If "transform" means something in the entity system AND in the renderer,
rename one. We already do this naturally — Entity has `position/direction`,
renderer deals in `model_matrix`. Keep it that way.

### Include Units When Ambiguous

```odin
camera_fov_degrees  :: 60.0
tile_size_pixels    :: 32
speed_units_per_sec :: 5.0
dt_seconds:         f32       // or just dt — universally understood
```

---

## 5. Minimize Return Dimensionality

Return `void` when possible. Then `bool`. Then simple enums. Avoid returning
integers or complex types when simpler ones suffice.

Each additional dimension in a return value goes viral through the call graph,
multiplying state space. If a function can either succeed or assert-crash,
return void.

Our `game_update_and_render` returns void — that's already Tiger Style. Keep
functions that modify state returning void and asserting their preconditions.
Reserve error returns for actual system boundaries (file loading, GPU ops).

---

## 6. Deterministic Replay (The Game Version of DST)

Full Deterministic Simulation Testing is overkill for a game. But the
underlying principle — separate deterministic logic from non-deterministic
IO — is exactly what our platform/game layer split does.

`game_update_and_render` receives input through `Game_Input`, doesn't touch
SDL directly. If we feed the same sequence of inputs, we should get the same
game state. This enables:

- **Input recording/replay** for debugging weird edge cases
- **Rewind** (Phase 7) — snapshot and restore game state
- **Deterministic demos** — record inputs, replay them perfectly

This architecture already supports it. When we build hot reload (Phase 7),
the replay capability comes almost for free.

---

## 7. The Four Primary Colors

Joran thinks about system resources as four "primary colors," each with
two "textures":

| Resource | Latency | Bandwidth |
|----------|---------|-----------|
| CPU      | instruction latency, branch mispredicts | IPC, SIMD width |
| Memory   | cache miss penalty | cache line throughput |
| Storage  | seek time, fsync | sequential read/write speed |
| Network  | round-trip time | throughput |

For our game, CPU and Memory are the two that matter. Storage only matters
during asset loading. Network doesn't exist (single player).

Think about these when designing hot paths:
- Is this loop cache-friendly? (memory bandwidth)
- Am I branching unpredictably? (CPU latency)
- Am I touching memory I don't need? (memory latency — cache misses)

---

## 8. Go Slow to Go Fast

The "hard way" (static allocation, assertions everywhere, careful naming)
feels slower day-to-day but is faster overall. TigerBeetle built a
production distributed database in 3.5 years doing it this way. Typical
estimate for that kind of work: 5-10 years.

The dynamic, loose, "just ship it" approach is easy today, hard tomorrow.
They had a case where dynamic allocation slipped into their codebase — it
cost them months of blocked features before they ripped it out.

We already live this with arenas. Extend it to assertions and naming.

---

## What NOT to Adopt

- **Full DST with fault injection** — we're not a distributed system
- **Online data scrubbing** — game state is ephemeral
- **Extreme crash-and-recover patterns** — games should not crash in front of players
- **128-bit CPRNG assertions** — we don't have a CPRNG (yet)

Tiger Style was built for mission-critical financial infrastructure.
Take the engineering discipline, leave the paranoia calibrated for
"data loss means someone loses money."

---

## Summary: What We Take

1. **Assert liberally, including negative space** — crash in debug, log in release
2. **Treat arena limits as hard limits** — exceeding is a design bug
3. **MSB naming order** — `entity_count_max`, not `max_entity_count`
4. **Nouns, not gerunds. Don't abbreviate. Include units.**
5. **Minimize return dimensionality** — void > bool > enum > int
6. **Think in primary colors** — CPU/memory latency and bandwidth
7. **Platform/game split enables deterministic replay** — invest in this at Phase 7
8. **Go slow to go fast** — the constraints are the features
