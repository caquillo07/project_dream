# Progress Tracker

Newest entries first.

---

## 2026-03-13 — Sprint 1: Phases 1-3 Complete

**What:** Built the foundation — platform layer, 3D mesh pipeline, and camera system.

**Phase 1 — Platform Layer:**
- SDL3 init, GPU device (Metal/metallib), window, event loop
- Shader pipeline: GLSL → glslc → SPIR-V → spirv-cross → Metal → metallib
- Growable virtual memory arenas (permanent + scratch) with growth warnings
- Game_Input with Button_State (is_down/pressed/released), Debug_Timing
- Frame timing in title bar (sampled every 0.5s, avg/min/max/fps)
- Hello triangle proving full GPU pipeline end-to-end

**Phase 2 — Mesh Pipeline + Ground Plane:**
- Mesh_Vertex (position, UV, normal), Mesh_Uniforms (view_proj, model)
- Mesh shaders with uniform buffer (set=1) and texture sampler (set=2)
- D32_FLOAT depth buffer, depth test LESS_OR_EQUAL
- Procedural checkerboard texture (NEAREST filter, REPEAT addressing)
- 20x20 ground quad on XZ plane

**Phase 3 — 3D Camera:**
- Follow camera: fixed pitch (50°), scroll-wheel zoom, target following
- Debug free camera (F1): FPS-style WASD+E/Q fly, mouse look, save/restore
- Camera reference doc: docs/references/camera_system.md

**Key files:** src/main.odin, shaders/mesh.vert.glsl, shaders/mesh.frag.glsl

---

## 2026-03-13 — Project Setup

**What:** Created project structure, documentation, and development philosophy.

**Key decisions:**
- Odin + SDL3 (vendor:sdl3), no C unless forced
- Casey Muratori / Handmade Hero structural style (platform/game layer separation)
- Same coding philosophy as vdb project (grug brain, arenas, data-oriented, Casey test)
- 3D world with 2D billboard sprites (Pokemon Black2/HGSS/Cassette Beasts style)
- SDL3 GPU API for all rendering (SPIR-V shaders, cross-compiled at runtime)
- C prototype (sdl3_3d_engine) as the proven rendering reference to port from

**Documentation created:**
- CLAUDE.md (project instructions)
- docs/PROJECT_VISION.md (game vision and roadmap)
- docs/references/coding_style.md (coding law)
- docs/sprints/_template.md (sprint template)
- todo.md (first sprint: Foundation — Sprite in a 3D World)
