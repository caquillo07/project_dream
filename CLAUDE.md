# Project Dream — Monster Exploration Game

## Role of Claude

Claude is a **guide and pair programmer**, not an autonomous builder.
- Do not generate entire files unprompted
- Do not refactor unless explicitly asked
- Do not add abstractions that weren't discussed
- When asked to implement something, produce the relevant chunk and explain it
- Ask clarifying questions before writing non-trivial code
- Call out scope creep. Keep the human honest.
- Do not use Claude Code's plan mode tool. Planning happens in conversation, then goes into `todo.md` and `progress_tracker.md`.
---

## What Is This?

A **3D monster-collecting exploration game** written in Odin with SDL3.
3D world with 2D billboard sprites. Think Pokemon Black2/HGSS/Cassette Beasts aesthetics,
Pokemon Legends Arceus gameplay loop, up to Link's Awakening Switch fidelity.

Solo project. Keep it realistic.

---

## Project Philosophy

- **Grug brain first.** Simple, direct, procedural. Complexity is the enemy.
- **Casey Muratori / Handmade Hero** as the structural north star.
- **No dogma.** We do real engineering. If a rule doesn't serve the problem, drop it.
- **Deterministic resource usage.** Memory and CPU behavior must be predictable.
- **Performance is a feature.** This should run embarrassingly well.

**Coding style guide:** `docs/references/coding_style.md` — all code reviews check against this.
Only branches named `prototype-*`, `spike-*`, or `poc-*` are exempt (throwaway code, explicitly marked).

---

## Language & Dependencies

- **Odin** — everything: platform layer, game layer, rendering, arenas, all of it
- **SDL3** — windowing, input, audio, GPU API (via Odin `vendor:sdl3`)
- **SDL3 GPU API** — all rendering (no raw Vulkan/Metal/D3D)
- **SPIR-V shaders** — compiled from GLSL with `glslc`, runtime cross-compiled via `SDL_gpu_shadercross`

### Dependency Rules

- No Dear ImGui
- No game engine frameworks (Unity, Godot, Raylib)
- No OOP frameworks
- No ECS libraries
- Every dependency must be pragmatically justified. "It's easier" is not enough.

---

## Structure — Handmade Hero Style

```
project_dream/
├── src/
│   ├── main.odin             # platform layer — SDL3 init, main loop, GPU, input
│   ├── game.odin             # game layer — game_update_and_render, all game logic
│   └── ...                   # other Odin files as needed
├── shaders/
│   ├── *.vert.glsl           # vertex shaders (GLSL, compiled to SPIR-V)
│   └── *.frag.glsl           # fragment shaders
├── assets/
│   ├── sprites/              # 2D sprite sheets (pixel art)
│   ├── models/               # 3D models (ground, environment)
│   └── textures/             # textures for 3D geometry
├── docs/
│   ├── references/           # technical notes, learnings, decisions
│   ├── sprints/              # sprint tracking (completed/, upcoming/)
│   └── systems/              # system-level checklists and ideas
├── todo.md                   # active sprint (always the current work)
├── progress_tracker.md       # historical log of completed work
├── justfile                  # build commands
└── CLAUDE.md                 # this file
```

Platform layer is **Odin** (SDL3 via `vendor:sdl3`). No C code unless forced.

`main.odin` is the platform file. When we need platform-specific code later:
`main_darwin.odin`, `main_linux.odin`, `main_windows.odin`. Not yet.

---

## The Golden Rule

**Platform layer calls game layer. Game layer never calls platform directly.**
Game speaks to platform only through the `Platform` struct passed into `game_update_and_render`.

---

## Architecture

### Memory — Three Arenas, No Malloc

```
permanent  — game state, world data, entity storage. never freed. default: 64MB
cache      — loaded assets (textures, sprites, models). resizable. default: 256MB
scratch    — cleared every frame. temp work only. default: 16MB
```

- No malloc/free in game layer. Ever.
- Scratch is reset at end of every frame by the platform layer.
- Arenas are Odin structs, allocated and managed in Odin.

### Platform Layer (Odin — `main.odin`)

Owns:
- SDL3 window, event loop, GPU device (via `vendor:sdl3`)
- Input gathering (keyboard, gamepad, mouse)
- GPU pipeline creation and shader loading
- Frame timing
- Memory arena commitment

Exposes to game via `Platform` struct:
- `input` — keyboard, gamepad, mouse, per-frame pressed/released state
- `dt` — frame delta time
- `memory` — the three arenas

### Game Layer (`game.odin`)

Owns:
- All game state (GameState)
- World / tile map logic
- Entity management
- Player movement and collision
- Camera logic
- Render command generation

Does NOT own:
- Threads
- File handles
- SDL anything
- GPU pipeline details

### The Frame Loop

```
platform_main():
    commit memory blocks (permanent, cache, scratch)
    init SDL window + GPU device
    load shaders, create pipelines

    state = arena_push(permanent, sizeof(GameState))

    loop:
        platform_gather_input()          // SDL events -> platform.input
        dt = measure_frame_time()

        game_update_and_render(&platform, state)  // THE ONE CALL

        platform_flush_render_commands() // upload verts -> GPU draw calls
        platform_present()
        arena_reset(scratch)             // scratch dies here, every frame
```

---

## Rendering Approach

### 3D World with 2D Sprites

- **World geometry** — 3D meshes (ground tiles, buildings, trees, rocks) rendered with
  standard vertex/fragment shaders. Perspective camera, Lambertian diffuse lighting.
- **Characters & creatures** — 2D pixel-art sprites rendered as billboards (quads that
  always face the camera). Nearest-neighbor filtering for crisp pixels. Alpha test for
  transparency. Direction-aware animation (up/down/left/right frames).
- **Camera** — 3D perspective, top-down-ish angle (like Pokemon ORAS/BDSP).
  Follows the player. Not free-roam.

### Shader Compilation

GLSL -> SPIR-V (via `glslc`) -> runtime cross-compile to Metal/Vulkan/D3D12 (via `SDL_gpu_shadercross`).

Shaders live in `shaders/`. Build step compiles them to `build/shaders/*.spv`.

### Pipelines

1. **Mesh Pipeline** — static 3D geometry (ground, environment)
2. **Sprite Pipeline** — billboard 2D sprites (player, creatures, NPCs)
3. **Debug Pipeline** — debug overlay (collision boxes, gizmos) — added when needed

---

## Reference Projects

Local codebases to learn from — don't copy blindly, but use as reference when stuck.

- **`/Users/hector/code/sdl3_3d_engine`** — C prototype proving SDL3 GPU patterns.
  **This is the primary rendering reference.** Has billboard sprites, skeletal animation,
  lighting (directional, point, spotlight, day/night, zones), entity system, asset cache.
  Already proven to work. Port patterns to Odin, don't copy C code verbatim.

- **`/Users/hector/code/vdb`** — Video debugger in Odin + SDL3.
  **This is the primary Odin + SDL3 reference.** Same philosophy, same coding style,
  same platform/app layer pattern. Copy the structural approach verbatim.

- **`~/Documents/handmade_hero/handmade_hero_legacy_source/handmade_hero_day_031_source`** —
  Handmade Hero day 31. Structural north star for platform/game layer separation,
  tile-based world, canonical position system, input handling.

- **`~/Documents/handmade_hero/handmade_hero_664_source`** —
  Latest Handmade Hero. Reference for where the architecture ends up at maturity.

---

## Game Design (High Level)

### Genre & Gameplay
- Monster-collecting exploration game
- Open world, exploration-first (like Legends Arceus)
- Catching/battling is secondary to discovering the world
- Single player

### Visual Style
- 3D world with 2D billboard sprites
- Aesthetic: Pokemon Black2 / HGSS / Cassette Beasts
- Upper bound: Link's Awakening Switch (tilt-shift 3D, simple geometry)
- Stylized, colorful, NOT PBR
- Day/night cycle with zone-based lighting (outdoor, cave, interior)

### Core Pillars
1. **Exploration** — the world is full of secrets for those who look
2. **Discovery** — hidden areas, rare creatures, environmental puzzles
3. **Charm** — inviting, colorful, makes you want to explore every corner

---

## What We Are NOT Building (Yet)

- Battle system
- Monster/creature data and mechanics
- Inventory / menus / UI
- NPCs / dialogue system
- Audio / music
- Save/load
- Particle effects
- Water/environment shaders
- Multiplayer

When scope creep appears, refer to this list.

---

## Sprint Workflow

1. Plan sprint in `docs/sprints/upcoming/`
2. When starting: move to `todo.md` at project root, set status "In Progress"
3. Work through phases, update status as we go
4. On completion:
   - Write `docs/references/` guides for major features
   - Update `progress_tracker.md` with summary + learnings
   - Archive: `mv todo.md docs/sprints/completed/YYYY-MM_name.md`

---

## Known Traps

- **Shader compilation on macOS**: Need `glslc` (from Vulkan SDK or `brew install shaderc`)
  and `SDL_gpu_shadercross` for runtime SPIR-V -> Metal translation. The C engine already
  solved this — reference `build.sh` and shader loading code.

- **Billboard math**: Sprites need camera right/up vectors to construct quads facing camera.
  Reference: `sdl3_3d_engine/docs/references/SPRITE_BILLBOARDS_ANIMATIONS.md`.

- **std140 uniform alignment**: vec3 needs 16-byte alignment (pad to vec4).
  Reference: `sdl3_3d_engine/docs/references/SDL3_GPU_LIMITATIONS.md`.

- **SDL3 GPU uniform buffer sets**: Must use set 1 or 3 on Metal.
  The C engine already hit this — follow its patterns.
