# Progress Tracker

Newest entries first.

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
