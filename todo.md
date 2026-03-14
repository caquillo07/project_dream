# Sprint: Foundation — Sprite in a 3D World

**Started:** 2026-03-13
**Status:** Not Started

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
- [ ] SDL3 init (window, GPU device, event loop)
- [ ] Frame timing (dt calculation)
- [ ] Input gathering (keyboard state, per-frame pressed/released)
- [ ] Shader loading (SPIR-V via SDL_gpu_shadercross)
- [ ] justfile with build + shader compilation commands
- [ ] Basic render loop (clear screen, present)

### Phase 2 — Mesh Pipeline + Ground Plane
- [ ] Vertex format for 3D geometry (position, UV, normal)
- [ ] Mesh pipeline (vertex shader, fragment shader, depth test)
- [ ] Hardcoded ground plane (flat quad or grid of quads)
- [ ] Basic texture loading (stb_image or SDL3 image loading)
- [ ] Textured ground visible on screen

### Phase 3 — 3D Camera
- [ ] Perspective projection matrix
- [ ] Camera struct (position, target, up)
- [ ] View-projection matrix generation
- [ ] Camera positioned at top-down-ish angle (Pokemon ORAS style)
- [ ] Uniform buffer for view-projection passed to shaders

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
- (none yet)

**In Progress:**
- (not started)

**Blocked:**
- (none)

---

## Learnings
- (captured as we go)

---

## Completion Checklist

Before archiving this sprint:
- [ ] All phases marked complete
- [ ] docs/references/ guides written for major features
- [ ] progress_tracker.md updated with summary + learnings
- [ ] Archive: `mv todo.md docs/sprints/completed/YYYY-MM_name.md`
