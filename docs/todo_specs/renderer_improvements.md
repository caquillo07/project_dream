# Renderer Improvements

Low-effort, high-value improvements to our SDL3 GPU usage.
Sourced from reviewing a community SDL3 GPU wrapper (Discord, 2026-04).

None of these require architectural changes — they're localized improvements
to existing code in `renderer.odin`.

---

## 1. SPIR-V Reflection for Shader Resource Counts

**Problem:** `load_shader` takes manual `num_uniform_buffers` and `num_samplers` params.
Get them wrong and things silently break. Every new shader means hand-counting bindings.

**Fix:** Use `ShaderCross_ReflectGraphicsSPIRV` (if available in our bindings) to read
resource counts directly from the compiled SPIR-V. The metadata is already in the binary.

**Before:**
```odin
mesh_vert_shader := load_shader("build/shaders/mesh.vert.spv", .VERTEX, 1, 0)
mesh_frag_shader := load_shader("build/shaders/mesh.frag.spv", .FRAGMENT, 0, 1)
```

**After:**
```odin
mesh_vert_shader := load_shader("build/shaders/mesh.vert.spv", .VERTEX)
mesh_frag_shader := load_shader("build/shaders/mesh.frag.spv", .FRAGMENT)
// resource counts read from SPIR-V automatically
```

**Prerequisite:** Check if our `shadercross.odin` bindings expose `ReflectGraphicsSPIRV`.
If not, we need to add the binding.

**Priority:** High — eliminates a class of silent bugs.

---

## 2. Debug Naming for GPU Resources

**Problem:** In RenderDoc / GPU debuggers, all our textures, buffers, and pipelines show
up as anonymous handles. Hard to tell which is which.

**Fix:** Pass `name` strings via SDL properties when creating resources.
SDL has properties like `sdl.PROP_GPU_TEXTURE_CREATE_NAME_STRING`,
`sdl.PROP_GPU_BUFFER_CREATE_NAME_STRING`, `sdl.PROP_GPU_GRAPHICSPIPELINE_CREATE_NAME_STRING`.

**Scope:** Add optional `name` param to `load_texture`, `renderer_upload_vertex_buffer`,
and the pipeline creation procs. Only used in debug builds (`when ODIN_DEBUG`).

**Priority:** Medium — not urgent, very helpful when debugging rendering issues.

---

## 3. MAILBOX Present Mode

**Problem:** We use VSYNC which blocks until vblank. Fine for now, but adds input latency.

**Fix:** Try MAILBOX first (tear-free, lower latency), fall back to VSYNC.

```odin
if !sdl.SetGPUSwapchainParameters(dev, window, .SDR, .MAILBOX) {
    log.warn("MAILBOX not supported, falling back to VSYNC")
    sdl.SetGPUSwapchainParameters(dev, window, .SDR, .VSYNC)
}
```

**Note:** MAILBOX means the GPU renders frames that may never display (replaced before
vblank). Uses more power. Consider making this a setting alongside vsync on/off.

**Priority:** Low — nice to have, not blocking anything.

---

## 4. GPU Device Info Logging

**Problem:** We don't log what GPU/driver we're running on. Makes it harder to debug
reports from different machines later.

**Fix:** On init, query `sdl.GetGPUDeviceProperties()` and log device name + driver version.

```odin
props := sdl.GetGPUDeviceProperties(device)
defer sdl.DestroyProperties(props)
device_name := sdl.GetStringProperty(props, sdl.PROP_GPU_DEVICE_NAME_STRING, "unknown")
driver_name := sdl.GetStringProperty(props, sdl.PROP_GPU_DEVICE_DRIVER_NAME_STRING, "unknown")
log.infof("GPU: %s, Driver: %s", device_name, driver_name)
```

**Priority:** Low — 5-line addition, do it whenever.

---

## 5. Typed Transfer Buffer Mapping

**Problem:** `renderer_upload_vertex_buffer` does `mem.copy` from a temp slice into a
mapped `rawptr`. Works fine but requires building data first, then copying.

**Fix:** Map returns `[^]T` so you can write directly into GPU-mapped memory.
Mainly useful for data that changes every frame (debug lines, streaming geometry).

```odin
gpu_upload_mapped :: proc($T: typeid, tbuf: ^sdl.GPUTransferBuffer, cycle: bool) -> [^]T {
    ptr := sdl.MapGPUTransferBuffer(platform.renderer.device, tbuf, cycle)
    return cast([^]T) ptr
}
```

**Priority:** Low — current approach works. Revisit when we have per-frame streaming
vertex data (particles, animated debug vis, etc).

---

## 6. Arena Temp Memory Marks (Sub-Arenas)

**Problem:** During init we do throwaway allocations (shader bytecode, temp strings for
SDL calls, etc). Currently these sit in scratch and we rely on the first frame's
`free_all(scratch)` to clean them up. Works, but the cleanup is implicit and distant
from the allocation site.

**Pattern:** `mem.begin_arena_temp_memory` / `mem.end_arena_temp_memory` saves and restores
an arena's offset. Anything allocated between the two calls is popped instantly.

```odin
// Example: temp cstring for an SDL call, allocated on permanent arena, freed immediately
mark := mem.begin_arena_temp_memory(&permanent_arena)
name_c := strings.clone_to_cstring(name, permanent_allocator)
sdl.SetStringProperty(props, sdl.PROP_GPU_TEXTURE_CREATE_NAME_STRING, name_c)
mem.end_arena_temp_memory(mark)
// name_c memory is reclaimed, permanent arena offset restored
```

**Use cases:**
- Init-time throwaway work (shader loading, string conversion) without polluting scratch
- Any proc that needs a small temp allocation within a long-lived arena
- Mid-frame temp work that shouldn't wait for end-of-frame scratch clear

**Note:** Odin's `mem.Arena` supports this natively. No new code needed, just a pattern
to apply. Requires using `mem.Arena` (not `vmem.Arena`) — check if our virtual memory
arenas support the same API or if we need a thin adapter.

**Priority:** Low — current approach works. Learn the pattern, apply when it fits naturally.

---

## Not Borrowing

These were in the reference file but don't fit our style:

- **Vtable wrappers for command buffer / render pass** — Heap alloc per frame for OOP
  syntax. We call SDL directly, that's correct.
- **Re-defined SDL enums/structs** — 1200 lines of type aliases that require cast/transmute
  at every boundary. Just use `sdl.` types.
- **Device wrapper struct** — We have our own arena system, don't need another one.
- **Configurable error callbacks** — Our `log_sdl_fatal` / `log_sdl_error` are simpler.
- **Compute pipeline wrappers** — YAGNI. We don't need compute yet.
