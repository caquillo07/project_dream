# Progress Tracker

Newest entries first.

---

## 2026-03-27 — Phase 4.75: Game Layer Split (Casey Style)

**What:** Clean platform/game boundary — game layer has zero SDL imports, all game logic flows through `game_update_and_render()`.

**Platform/game boundary:**
- game_update_and_render(game, input, dt, window_w, window_h) — THE ONE CALL
- Game_State output fields: view_proj, camera_right, camera_up (platform reads for drawing)
- Game_State signal bools: vsync, quit_game (platform reacts after the call)
- Game_Input: movement, actions, debug toggles, mouse/scroll deltas, mouse buttons
- Platform watches state changes (prev_debug_mode pattern) and calls SDL accordingly
- game.odin imports only core:log, core:math, core:math/linalg — zero SDL

**Game owns projection:**
- FOV, near/far planes are game constants (GameFOV, GameNearPlane, GameFarPlane)
- Platform passes window_width/height, game computes proj internally
- Renderer no longer stores or computes projection matrix

**Input restructure:**
- All keyboard input through gather_input (F1, V, Escape wired as Button_States)
- Mouse scroll/delta accumulated per-frame, applied once in game layer (fixes compounding bug)
- Natural scrolling handled (FLIPPED direction check)
- global_pause toggle (P key, platform-level)

**Key files:** src/game.odin, src/main.odin, src/renderer.odin

---

## 2026-03-22 — Phase 4.5: Code Cleanup & Architecture

**What:** Major refactor to organize codebase for Phase 5+ development.

**Renderer extraction:**
- Render_State struct (device, window, pipelines, depth, samplers, projection)
- Pipeline_Kind enum + table — pipelines stored in renderer.pipelines[.Mesh/.Sprite]
- init_renderer / deinit_renderer, begin_frame / end_frame
- resize_viewport (depth buffer + projection), vsync toggle
- load_shader, load_texture (overload set), unload_texture
- renderer_upload_vertex_buffer with polymorphic `[]$T` (no rawptr, no manual size)
- Switched from stb_image (C, malloc) to core:image/png (native Odin, arena-friendly)

**Game state:**
- Game struct (entities, input, debug state) as package-level global
- Entity fat struct (kind, position, direction, speed), flat array [1024]
- Index 0 = null entity, index 1 = player (Handmade Hero style)
- File split: renderer.odin, game.odin, entity.odin, camera.odin, sprite.odin, model.odin, math.odin

**Key files:** src/renderer.odin, src/game.odin, src/entity.odin

---

## 2026-03-16 — Cross-Platform Shader Pipeline (ShaderCross)

**What:** Replaced macOS-only offline shader compilation with runtime SPIR-V transpilation via SDL_ShaderCross.

- Wrote Odin foreign bindings for ShaderCross (src/shadercross.odin, ~40 lines)
- Simplified justfile: `glslc → .spv` only (removed spirv-cross, xcrun metal, metallib steps)
- Device creation now queries ShaderCross for supported GPU shader formats (no hardcoded .METALLIB)
- `load_shader` uses `ShaderCross_CompileGraphicsShaderFromSPIRV` instead of `CreateGPUShader`
- Entrypoint changed from `"main0"` to `"main"` (ShaderCross handles the rename internally)
- Shader compilation timing: ~5ms warm cache, ~290ms cold (macOS caches Metal shaders on disk)
- Ship .spv files — one artifact runs on macOS (Metal), Linux (Vulkan), Windows (D3D12)
- HiDPI: depth buffer and projection use pixel dimensions via `GetWindowSizeInPixels`
- VSync toggle (V key, debug mode only) via `SetGPUSwapchainParameters`
- Depth buffer recreated on window resize (WINDOW_PIXEL_SIZE_CHANGED event)

**Key files:** src/shadercross.odin, src/main.odin, justfile

---

## 2026-03-13 — Sprint 1: Phase 4 Complete (Sprite Pipeline + Billboard)

**What:** Added the sprite rendering system — 2D billboard sprite in the 3D world.

- Sprite shaders: vertex shader generates quad from gl_VertexIndex (no vertex buffer), billboard math using camera right/up vectors, UV from sprite rect with half-pixel inset
- Fragment shader: texture sample + alpha test (discard < 0.5) for crisp pixel art
- Sprite pipeline: triangle strip, no backface culling, NEAREST filter, CLAMP_TO_EDGE, depth on
- First real texture loading from disk via stb_image (nate.png sprite sheet, 364x724, 33x33 cells)
- Sprite_Uniforms struct matching std140 layout (view_proj, camera vectors, sprite transform, atlas info)
- Camera right/up vectors computed per frame for both follow and debug cameras
- Added `odinfmt -w` to build pipeline via justfile

**Key files:** shaders/sprite.vert.glsl, shaders/sprite.frag.glsl, assets/sprites/nate.png

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
