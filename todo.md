# Sprint: Foundation — Sprite in a 3D World

**Started:** 2026-03-13
**Status:** In Progress

## Goal

A 2D animated sprite (the player) moving around in a 3D world with a perspective camera following it.

## Context

This is the "day 31 equivalent" for our game. Before we can build monsters, battles, or any game systems,
we need the absolute foundation: a platform layer, a game layer, a 3D camera, a ground to walk on,
and a sprite that moves. Everything else builds on this.

The C prototype at `sdl3_3d_engine` already proved all the rendering patterns (billboard sprites,
3D camera, shader compilation, SDL3 GPU API). This sprint ports those patterns to Odin and establishes
the project's architecture.

---

## Phases

### Phase 1 — Platform Layer
- [x] SDL3 init (window, GPU device, event loop)
- [x] Frame timing (dt calculation, Debug_Timing struct)
- [x] Input gathering (Game_Input struct, per-frame pressed/released)
- [x] Shader loading (GLSL -> SPIR-V -> Metal -> metallib build pipeline)
- [x] justfile with build + shader compilation commands
- [x] Basic render loop (clear screen, present)
- [x] Memory arenas (permanent + scratch, growable, virtual memory backed)
- [x] Hello triangle (proved full GPU pipeline end-to-end)

### Phase 2 — Mesh Pipeline + Ground Plane
- [x] Vertex format for 3D geometry (position, UV, normal)
- [x] Mesh pipeline (vertex shader, fragment shader, depth test)
- [x] Hardcoded ground plane (flat quad or grid of quads)
- [x] Procedural checkerboard texture (stb_image deferred to Phase 4)
- [x] Textured ground visible on screen

### Phase 3 — 3D Camera
- [ ] Camera struct (target, distance, fixed pitch — HGSS/Link's Awakening style)
- [ ] View-projection computed per frame from camera state
- [ ] Scroll wheel zoom (clamped min/max)
- [ ] Temporary WASD target panning (replaced by player follow in Phase 5)
- [ ] Debug free camera (F1 toggle, save/restore follow camera, mouse look, WASD fly)

### Phase 4 — Sprite Pipeline + Billboard
- [ ] Sprite vertex shader (generate quad from vertex index, billboard math)
- [ ] Sprite fragment shader (texture sample, alpha test)
- [ ] Sprite pipeline (no backface culling, nearest-neighbor filtering)
- [ ] Load a sprite sheet texture
- [ ] Single sprite rendered as billboard in 3D world

### Phase 5 — Player Movement + Animation
- [ ] Player entity with world position
- [ ] WASD movement (frame-rate independent)
- [ ] Direction detection (up/down/left/right based on movement)
- [ ] Sprite animation (frame cycling based on time)
- [ ] Direction-aware animation (different frames per direction)
- [ ] Camera follows player position

### Phase 6 — Game/Platform Layer Split
- [ ] Platform struct (input, dt, memory arenas)
- [ ] game_update_and_render() — the one call
- [ ] GameState allocated from permanent arena
- [ ] Scratch arena reset every frame
- [ ] Clean separation verified: game code has zero SDL imports

---

## Current Status

**Completed:**
- Phase 1 — Platform Layer
- Phase 2 — Mesh Pipeline + Ground Plane

**In Progress:**
- Phase 3 — 3D Camera

**Blocked:**
- (none)

---

## Learnings
- spirv-cross renames `main` to `main0` in Metal output — use `"main0"` as shader entrypoint
- `os.read_entire_file` in Odin dev-2026-03 requires explicit allocator parameter
- `sdl.SubmitGPUCommandBuffer` returns bool — must handle it or Odin errors
- Always submit command buffer before `continue` to avoid GPU resource leaks
- `context.temp_allocator` defaults to a hidden allocator we don't control — set it to our scratch arena

---

## Completion Checklist

Before archiving this sprint:
- [ ] All phases marked complete
- [ ] docs/references/ guides written for major features
- [ ] progress_tracker.md updated with summary + learnings
- [ ] Archive: `mv todo.md docs/sprints/completed/YYYY-MM_name.md`
