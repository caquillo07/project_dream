# 3D Model Anatomy — What a Model Actually Is

## TL;DR

A 3D model is a bag of triangles with extra data attached. Everything else is organizational sugar.

---

## The Parts

### Vertices — The Points

A vertex is a point in 3D space with metadata attached:

```
position  (Vec3)  — where in 3D space
uv        (Vec2)  — where on the texture image (0-1 range, coordinate on the texture)
normal    (Vec3)  — which direction this surface faces (for lighting)
```

A cube has 8 corners, but needs **24 vertices** because each face needs its own normals and UVs.
A vertex isn't just a position — it's position + all attributes combined. Two vertices at the
same position but with different normals are different vertices.

### Indices — How to Connect Them

Three vertices make a triangle. You could list every triangle's 3 vertices explicitly (wasteful —
shared corners get duplicated), or use an **index buffer**: a list of integers that says
"triangle 1 uses vertices 0, 1, 2; triangle 2 uses vertices 2, 1, 3."

A cube: 24 vertices, 36 indices (12 triangles x 3 indices each).

### Texture — The Skin

A flat image (PNG/JPG) wrapped onto the triangles. UV coordinates on each vertex say "this corner
of this triangle maps to this pixel on the image." The GPU interpolates between vertices to fill
in the rest.

Think of it like wrapping paper — UVs are the instructions for where to cut and fold.

### Material — How It Looks

Describes surface properties:
- **base_color_texture** — the texture to sample
- **color_tint** — multiply the texture color by this (white = unchanged, red = tint red)
- **metallic/roughness** — PBR properties (stored for future lighting, not used yet)

A model can have multiple materials (e.g. a character's skin vs armor vs eyes).

### Mesh — A Group of Triangles Sharing a Material

One model can have multiple meshes. Each mesh has its own vertices, indices, and references one
material. A character model might have: body mesh (skin material), armor mesh (metal material),
eyes mesh (eye material).

---

## The Hierarchy

```
Loaded_Model
├── name: "bat"
├── materials: [Material_0, Material_1, ...]
└── meshes:
    ├── Loaded_Mesh_0
    │   ├── vertices: [v0, v1, v2, ...]       — position + uv + normal per vertex
    │   ├── indices: [0, 1, 2, 2, 1, 3, ...]  — which vertices form triangles
    │   └── material_index: 0                  — "use Material_0"
    └── Loaded_Mesh_1
        ├── vertices: [...]
        ├── indices: [...]
        └── material_index: 1
```

---

## What glTF Gives Us

glTF is a container format. A .glb file is a binary blob with:

- **Accessors** — typed views into raw binary data ("these 100 floats are Vec3 positions")
- **Buffer views** — byte ranges within a binary buffer
- **Buffers** — the raw bytes

The loading flow: parse glTF -> read accessors to get typed arrays -> copy into our structs -> throw away glTF data.

### glTF Accessor Example

```
Accessor #3:
  type: VEC3
  component_type: FLOAT
  count: 200
  buffer_view: 1
  byte_offset: 0
```

This says: "starting at offset 0 of buffer_view 1, read 200 items, each is 3 floats (Vec3)."
The library handles all this — we just call `buffer_slice(data, accessor_index)` and get a typed
Odin slice back (e.g. `[][3]f32`).

---

## What the GPU Sees

The GPU doesn't know about "models" or "materials." It only knows:

1. A **vertex buffer** — blob of vertex data in GPU memory
2. An **index buffer** — blob of integers in GPU memory
3. A **texture** bound to a sampler
4. **Uniforms** — view_proj matrix, model matrix, color tint, etc.
5. **Draw indexed** — use the index buffer to pull vertices and rasterize triangles

Our job: glTF file -> our structs -> GPU buffers -> draw calls.

---

## UV Flip

glTF defines UV origin at **top-left** (V=0 is top of image). SDL3 GPU matches this convention,
so **no UV flip is needed**. Pass UVs through as-is from glTF data.

The C engine reference flips in both the loader (`v = 1.0 - v`) AND the fragment shader
(`1.0 - v_uv.y`), which cancel out. We tested: flipping produces wrong results, no flip is correct.

---

## Bone Data (Phase 6.5 — Skeletal Animation)

For animated models, each vertex also carries:
- **bone_ids** ([4]u8) — which 4 bones influence this vertex
- **bone_weights** ([4]f32) — how much each bone contributes (sum to 1.0)

For static meshes: bone_ids = {0,0,0,0}, bone_weights = {1,0,0,0}.

The vertex struct includes these fields from day one so the vertex format doesn't change
when animation support lands.

---

## Our Vertex Format

```
Model_Vertex :: struct {
    position:     Vec3,       // 12 bytes
    uv:           Vec2,       //  8 bytes
    normal:       Vec3,       // 12 bytes
    bone_ids:     [4]u8,      //  4 bytes
    bone_weights: [4]f32,     // 16 bytes
}                             // 52 bytes total
```

Separate from `Mesh_Vertex` (position + uv + normal only) used for simple geometry like the
ground plane — no reason to waste 20 bytes per vertex on bone data for static environment.
