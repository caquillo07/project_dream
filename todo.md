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
- [x] Shader loading (GLSL -> SPIR-V, runtime transpilation via ShaderCross)
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
- [x] Camera struct (target, distance, fixed pitch — HGSS/Link's Awakening style)
- [x] View-projection computed per frame from camera state
- [x] Scroll wheel zoom (clamped min/max)
- [x] Temporary WASD target panning (replaced by player follow in Phase 5)
- [x] Debug free camera (F1 toggle, save/restore follow camera, mouse look, WASD+E/Q fly)

### Phase 4 — Sprite Pipeline + Billboard
- [x] Sprite vertex shader (generate quad from vertex index, billboard math)
- [x] Sprite fragment shader (texture sample, alpha test)
- [x] Sprite pipeline (no backface culling, nearest-neighbor filtering)
- [x] Load a sprite sheet texture (stb_image)
- [x] Single sprite rendered as billboard in 3D world

### Phase 4.5 — Code Cleanup & Architecture
- [x] Renderer extracted (Render_State, init/deinit, begin_frame/end_frame, resize_viewport)
- [x] Projection matrix lives in Render_State, updated on resize
- [x] Samplers in renderer (nearest_repeat, nearest_clamp)
- [x] load_texture / load_texture_from_pixels / unload_texture helpers
- [x] Pipeline_Kind enum + table in Render_State
- [x] Game struct (entities, input, debug state)
- [x] Entity struct (kind, position, direction, speed), flat array, null at 0, player at 1
- [x] File split: renderer.odin, game.odin, entity.odin, camera.odin, sprite.odin, model.odin, math.odin
- [x] Sprite.rect fixed to Vec4
- [x] Pipelines stored in renderer.pipelines table, released in deinit_renderer
- [x] Switched from stb_image to core:image/png (native Odin, arena-friendly)
- [x] Polymorphic renderer_upload_vertex_buffer ([]$T — no rawptr, no manual size)
- [x] load_texture overload set, dropped redundant size params from load_texture_from_pixels
- [x] Cleaned up redundant u32 casts, stale comments, debug logs
- [x] Move follow camera into Game struct (folded into Phase 4.75)
- [x] Init player entity once at startup (folded into Phase 4.75)
- [x] Entity_ID kept for future use (entities referencing each other)

### Phase 4.75 — Game Layer Split (Casey Style)
- [x] Game_Input: separated from Game_State, scroll/mouse delta, mouse buttons, debug toggle buttons
- [x] Game_State: view_proj/camera_right/camera_up output fields, vsync/quit_game signals
- [x] game_update_and_render(game, input, dt, window_w, window_h): all game logic, zero SDL
- [x] Game owns projection (FOV, near, far, aspect) — platform passes window dimensions
- [x] Event loop: platform accumulates scroll/mouse into Game_Input, no game logic
- [x] Debug toggle: game handles F1 via Button_State, platform reacts to state change (SDL mouse mode)
- [x] VSync/quit: game sets bools, platform reacts (Handmade Hero state-signal pattern)
- [x] THE ONE CALL: if !global_pause { game_update_and_render(...) }
- [x] Draw section reads game state (view_proj, cam vectors, entity positions)
- [x] global_pause toggle (P key)
- [x] Verified: game.odin has zero SDL imports, clean platform/game boundary

### Phase 5 — Player Movement + Animation
- [x] WASD moves player entity on XZ plane (normalized diagonal movement)
- [x] Camera follows player position (camera.target = player.position)
- [x] Direction detection from movement vector (dominant axis, 4-direction for sprite facing)
- [x] Player faces last movement direction when idle (direction only updates when moving)
- [x] Animation state on entity (timer, frame index, playing flag — SpriteAnimation on Entity)
- [x] Sprite frame table (idle/walk rects per direction from nate.png 33x33 grid)
- [x] Walk animation: cycle frames while moving at 6 FPS, reset on idle
- [x] Wire sprite_rect from entity animation state to draw call (direction + frame drives rect)

### Phase 5.5 — Debug Visualization (Frustum + Camera)
- [x] Debug line shader (position + color, no texture)
- [x] Debug line pipeline (LINES topology, no backface cull, depth on)
- [x] Compute follow camera frustum corners (inverse view_proj, 8 world-space points)
- [x] Draw frustum wireframe (12 lines: 4 near, 4 far, 4 connecting)
- [x] Draw camera eye position marker
- [x] Only draw when debug_mode is active (viewing saved follow camera)

### Phase 6 — 3D Model Loading + Rendering
- [ ] glTF parser (load .glb/.gltf — meshes, materials, node hierarchy)
- [ ] Upload model mesh data to GPU (vertex buffer, index buffer)
- [ ] Draw static model with mesh pipeline (model matrix from entity transform)
- [ ] Texture from glTF material (base color) applied to model
- [ ] Place a test model in the world (tree, rock, or building)
- [ ] Multiple model instances with different positions
- [ ] Entity draws either sprite OR model based on entity kind

### Phase 6.25 — Renderer Cleanup
- [ ] SPIR-V reflection for shader resource counts (drop manual num_samplers/num_uniform_buffers)
- [ ] Debug naming for GPU resources (textures, buffers, pipelines — visible in RenderDoc)
- [ ] GPU device info logging on init (device name, driver version)
- [ ] MAILBOX present mode with VSYNC fallback
- [ ] Typed transfer buffer mapping (for future per-frame streaming vertex data)
- [ ] Learn arena temp memory marks pattern (check vmem.Arena support)

Spec: `docs/todo_specs/renderer_improvements.md`

### Phase 6.5 — Model Animation (Skeletal)
- [ ] Parse glTF skeleton (joints, inverse bind matrices)
- [ ] Parse glTF animations (keyframes, interpolation)
- [ ] Skinning shader (joint matrices in uniform/SSBO)
- [ ] Play animation on model entity (idle, walk)
- [ ] Animation blending/crossfade between clips

### Phase 7 — Hot Reload + Rewind
- [ ] Game layer render commands (game produces draw list, platform consumes — the DLL boundary)
- [ ] Game layer as shared library (separate compilation unit)
- [ ] Platform struct (input, dt, memory arenas, platform services)
- [ ] Hot reload: recompile game DLL, reload function pointers, memory persists
- [ ] Rewind: snapshot/restore Game_State for step-back debugging

---

## Current Status

**Completed:**
- Phase 1 — Platform Layer
- Phase 2 — Mesh Pipeline + Ground Plane
- Phase 3 — 3D Camera
- Phase 4 — Sprite Pipeline + Billboard
- Phase 4.5 — Code Cleanup & Architecture
- Phase 4.75 — Game Layer Split (Casey Style)
- Phase 5 — Player Movement + Animation
- Phase 5.5 — Debug Visualization (Frustum + Camera)

**In Progress:**
- Phase 6 — 3D Model Loading + Rendering

**Up Next:**
- Phase 6.5 — Model Animation (Skeletal)
- Phase 7 — Hot Reload + Rewind

**Backlog:**
- Custom logger system (see src/logger.odin for format ideas)
- Tiger Style: add arena hard-limit assertions (crash in debug if permanent/cache/scratch exceed budget)
- Tiger Style: assertion pass over existing code (entity bounds, camera matrix NaN, tile validity)
- Tiger Style: audit naming for MSB order (see docs/references/tiger_style.md)
- Tiger Style: input recording/replay for deterministic debugging (natural fit at Phase 7)

**Blocked:**
- (none)

---

## Learnings
- ShaderCross: runtime SPIR-V transpilation, ~5ms warm / ~290ms cold (macOS caches Metal shaders on disk)
- ShaderCross: entrypoint is `"main"` (not `"main0"` like spirv-cross CLI output)
- `os.read_entire_file` in Odin dev-2026-03 requires explicit allocator parameter
- `sdl.SubmitGPUCommandBuffer` returns bool — must handle it or Odin errors
- Always submit command buffer before `continue` to avoid GPU resource leaks
- `context.temp_allocator` defaults to a hidden allocator we don't control — set it to our scratch arena
- `sdl.SetWindowRelativeMouseMode` returns bool — must handle with `_ =`
- Follow camera: position derived from target + spherical offset (distance * sin/cos pitch) — don't store position directly
- Billboard sprites need camera right/up vectors — compute alongside view_proj each frame
- Sprite pipeline: no vertex buffer, quad from gl_VertexIndex, triangle strip (4 verts)
- stb_image: `stbi.load` returns `[^]byte`, free with `stbi.image_free`, force RGBA with channel=4
- Replaced stb_image with core:image/png — native Odin, supports arena allocators, no C malloc
- Odin parametric polymorphism (`[]$T`) eliminates rawptr + manual size_of for GPU uploads
- `load_texture` overload set (proc{from_file, from_pixels}) — idiomatic Odin for function overloading
- For `[]byte` slices, `len()` IS byte count (size_of(byte)==1) — but for typed slices use `len * size_of(T)`
- Game->platform communication via bools in Game_State (quit_game, vsync) — rewind-safe, hot-reload-safe, no function pointers needed
- Accumulate mouse/scroll deltas across events, apply once per frame in game layer — avoids compounding bug
- Game owns projection (FOV, near/far) — platform just passes window dimensions
- Watch for sneaky `platform.*` globals leaking into game layer procs that take `game: ^Game_State`

---

## Completion Checklist

Before archiving this sprint:
- [ ] All phases marked complete
- [ ] docs/references/ guides written for major features
- [ ] progress_tracker.md updated with summary + learnings
- [ ] Archive: `mv todo.md docs/sprints/completed/YYYY-MM_name.md`
