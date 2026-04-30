# MoonHug

Unity-inspired game engine + editor written entirely in **Odin**. Uses raylib for graphics, ImGui for editor UI. Data-oriented architecture with handle-based object pooling and prebuild code generation. Active vertical-slice project.

- Repo: https://github.com/MoonHug-Editor/moonhug
- Location: ~/code/ext/moonhug/

## Why It's Here

**This is the most relevant reference we have.** Same language (Odin), similar philosophy (data-oriented, explicit, no clever abstractions), and it solves problems we'll hit head-on: billboard sprites in 3D, scene serialization, transform hierarchies, component systems, asset pipelines. It's basically a working example of how to structure an Odin game project.

## Stealable Ideas

### Architecture / Data Structures

- **Generational pool (slot array)**: Fixed-capacity array of `{generation, alive, data}` slots + freelist. Stale handles fail gracefully via generation mismatch. Predictable memory, no allocations in hot loops. This is the foundational data structure — use it for entities, components, everything.
- **Generational handles with type keys**: `Handle{index, generation, type_key}` — single table lookup for dispatch, no vtables, cache-friendly iteration. Perfect for our needs.
- **`Ref` = `PPtr` + `Handle`**: PPtr (`{local_id, guid}`) is the on-disk reference, Handle is the runtime resolved version. Handle never serialized. Resolved once at load time. This is exactly Unity's PPtr pattern and it works.
- **Local_ID per scene file**: File-scoped counter, no GUIDs needed for in-file references. Only cross-file refs need a GUID. Smaller JSON, simpler logic.
- **`Owned` vs `Ref`**: Distinct types for "I own this, destroy it when I die" vs "I just reference this." Compile-time clarity about ownership.

### Rendering

- **Billboard sprite via transform corners (no shader)**: Compute the 4 quad corners directly from the transform's quaternion rotation:
  ```odin
  rot := quat_to_matrix3(transform.rotation)
  right := rot[0]
  up := rot[1]
  p0 = pos - right*half_w - up*half_h
  // ...
  ```
  Then draw as a textured quad. No special billboard shader needed. This is exactly what we want for our creature/NPC sprites.
- **Pixels-per-unit constant**: `PIXELS_PER_UNIT :: 100.0` — sprite world size is texture pixels divided by this. Standard Unity convention, easy to reason about.
- **Render layer mask**: Per-sprite layer bits, camera filters by mask. Cheap way to separate world/UI/effects sprites.

### Scene Format

- **Flat arrays per component type, JSON**: Scene file = `{root, next_local_id, transforms[], sprite_renderers[], ...}`. Save = walk hierarchy, copy to flat arrays. Load = create handles, resolve `local_id -> Handle` map, walk references. Simple, hand-editable, cacheable.
- **Children/parents via PPtr**: Cross-file references work transparently. Same code for prefabs and inline objects.

### Asset Pipeline

- **GUID + .meta sidecar files**: Each asset gets a UUID stored in `asset.png.meta` (importer settings + guid). GUIDs survive renames/moves. Texture cache is `map[GUID]Texture`. Lazy load on first reference.

### Component Pattern

- **`using base: CompData`**: Embed common fields, attach to transforms, dispatch via type_key. No inheritance hierarchy. Clean Odin idiom.
- **`reset_X` / `on_validate_X` procs**: Called when component added (set defaults) or modified (clamp values). Simple convention, no framework code.

### Animation / Tweens

- **Tween union with composites**: `TweenUnion :: union { Tween, Sequence, Parallel, TweenMoveToLocal, ... }`. Sequences run children in order, Parallels run simultaneously. Hierarchical, serializable, no allocations at run time. Maps perfectly to "walk to X, play idle, turn around" NPC behaviors.

## What We're NOT Taking

- **Prebuild code generation framework**: Cool but adds two-stage build complexity. Hand-write dispatch tables for now — fewer moving parts, easier to debug. Reconsider if/when the boilerplate actually hurts.
- **Full ImGui editor**: We're not building an editor. Our "editor" is the codebase itself.
- **Immediate-mode rlgl rendering**: We're on SDL3 GPU. Batch our quads properly from day one.
- **`@(component)` attribute system**: Same reasoning as the codegen — write the pool/registry by hand, it's like 50 lines.

## Full Summary

### Tech Stack

- **Language**: Odin
- **Graphics**: raylib + low-level rlgl for custom rendering
- **UI**: odin-imgui (editor only)
- **Serialization**: `core:encoding/json`
- **Math**: `core:math/linalg`

### Architecture

```
prebuild/    Code generators (run before main compile)
engine/      Core runtime (no editor deps)
  pool.odin           Generational slot array
  transform.odin      Spatial hierarchy + component ownership
  scene.odin          Scene runtime + global registry
  components.odin     Base CompData, attachment
  render.odin         Sprite renderer (billboard mode)
  tween.odin          Animation/tweening
  asset_pipeline.odin Import system, GUID resolution
  serialization/      Union marshaling, GUID handling
app/         Game code (zero editor deps)
editor/      Full ImGui editor (depends on everything)
```

The split is clean: `engine/` and `app/` have zero editor dependencies, so a shipped game is just those two. Editor is purely additive.

### Pool / Handle System

```odin
Pool :: struct($T: typeid, $N: int = 1024) {
    slots: [N]struct { generation: u16, alive: bool, data: T }
    freelist: [N]u32
    free_head: int
}

Handle :: struct {
    index: u32,
    generation: u16,
    type_key: TypeKey,
}
```

Each component type gets its own monomorphic pool. World struct is auto-generated to contain all pools. Handles route through a dispatch table (`pool_table[type_key]`) for type-erased operations.

### Transform Hierarchy

```odin
Transform :: struct {
    local_id: Local_ID,
    name: string,
    is_active: bool,
    position, rotation, scale: ...,
    parent: Ref,
    children: [dynamic]Ref,
    components: [dynamic]Owned,
    layer_mask: u32,
}
```

Recursive `transform_world()` walks up to root, composing parent transforms. No cached world matrices (would need invalidation). Fine for small/medium scenes.

### Sprite Rendering

`render_sprite_renderers(layer_mask)` iterates the SpriteRenderer pool, looks up the texture by GUID, computes 4 quad corners from the transform's rotation matrix, and draws via `rlgl` immediate-mode quads. Per-sprite tint color (RGBA) for palette swaps.

### Scene Serialization

Scenes are JSON files with this structure:

```json
{
  "root": 1,
  "next_local_id": 14,
  "transforms": [
    { "local_id": 1, "name": "Root", "position": [0,0,0],
      "rotation": [0,0,0,1], "scale": [1,1,1],
      "children": [{"pptr": {"local_id": 2, "guid": "..."}}],
      "components": [{"local_id": 3}] }
  ],
  "sprite_renderers": [
    { "local_id": 7, "texture": "3fa8c2...", "color": [1,1,1,1] }
  ]
}
```

`scene_load_single_path()` for level transitions, `scene_load_additive_path()` for overlays.

### Phase System

Functions tagged with `@(update={order=N})` get registered into a generated dispatch table. Negative orders run before zero, positive after. Allows pre/post hooks without hardcoding the loop. The prebuild generator scans tagged procs and generates `phases_generated.odin`.

### Tween Composition

```odin
TweenUnion :: union #no_nil {
    Tween, Parallel, Sequence,
    TweenMoveToLocal, TweenRotateToLocal, TweenScaleToLocal,
}
```

Composites own their children. Each tween gets a `delay` field. Run via `tween_run("AnimName", context)`, processed via `tween_tick_running(dt)`. Pre-serialized as bytes and cloned at run time — zero allocation when starting an animation.

### What's Missing

From the project's own roadmap:
- Physics / collision detection
- Render batching
- Skeletal animation
- Undo/redo in editor
- Scene gizmos
- Nested prefabs
- Shader system
