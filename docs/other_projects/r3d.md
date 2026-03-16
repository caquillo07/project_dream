# r3d

Raylib-based 3D rendering extension. C11. Bolts a deferred rendering pipeline, PBR materials, skeletal animation, and collision helpers onto raylib.

- Repo: https://github.com/Bigfoot71/r3d
- Location: ~/code/ext/r3d/

## Why It's Here

Best reference we have for mesh animation (full skeletal system with GPU skinning, animation trees, blending) and hand-rolled collision/kinematics for character controllers. The kinematics system alone is enough for a Pokemon/Link's Awakening-tier game.

## Stealable Ideas

- **Quake-style sweep-then-slide collision**: Sweep shape along velocity, on hit apply safe movement up to contact minus epsilon, slide remainder along surface. Simple, proven, good enough for our game. See `r3d_kinematics.c`.
- **Skinning via 1D texture**: Bone matrices uploaded as `GL_RGBA16F` 1D texture (4 texels per bone = one 4x4 matrix). Cheap to update, shader just does texture lookups by bone index. Clever alternative to UBO/SSBO.
- **Animation state machine with BFS pathfinding**: States as nodes, transitions as edges with crossfade time. To change state, BFS finds shortest path and auto-crossfades through intermediates. Prevents pop when going from Walk -> Jump when there's no direct edge.
- **Bone masking for partial blending**: Bit mask (up to 256 bones) controls which bones a blend node affects. Upper/lower body splits without separate animation trees.
- **Shader embedding at build time**: Python script converts GLSL -> C headers. Zero runtime file I/O for shaders. We could do the same with our SDL3 GPU shaders.
- **Environment config via struct pointer macros**: `R3D_ENVIRONMENT_SET(tonemap.mode, X)` — direct struct writes, no getter/setter ceremony. Grug-approved.

## Full Summary

### Architecture

```
include/r3d/          Public API (one header per subsystem)
src/
  modules/            Core engine plumbing (driver, render, shader, texture, target, light, env)
  common/             Shared internals (animation helpers, frustum, image utils)
  importer/           Assimp-based loaders (glTF, FBX, COLLADA, OBJ, IQM)
  r3d_*.c             High-level feature implementations
shaders/              60+ GLSL files, embedded into the binary at build time
external/             glad, tinycthread, uthash, vendorable raylib + assimp
```

Rendering pipeline: Hybrid deferred + forward. Opaque geometry through G-buffers then deferred lighting. Transparent objects get a separate forward pass. Frustum culling before draw submission.

### Mesh Animation

Files: `src/common/r3d_anim.c`, `src/r3d_animation_player.c`, `src/r3d_animation_tree.c`

**Data model**: Skeleton (bone hierarchy + bind poses + 1D GPU texture), Animation (channels per bone, 3 tracks each: translation, rotation, scale as sorted keyframe arrays), Vertices carry `boneIds[4]` and `weights[4]`.

**Per-frame playback**:
1. Binary-search keyframe tracks, interpolate (Lerp for pos/scale, Slerp for rotation)
2. Forward pass over bone array: `localPose[i] * modelPose[parent]` -> model space
3. Compute `invBind[i] * modelPose[i]`, upload to 1D texture for GPU skinning

**Animation tree** — node graph with: Animation (leaf), Blend2 (weighted lerp/slerp), Add2 (additive layering), Switch (crossfade N inputs), State Machine (BFS pathfinding between states).

### Physics / Kinematics

Files: `src/r3d_kinematics.c`, `include/r3d/r3d_kinematics.h`

**Not a physics engine** — collision detection + response toolkit. You own gravity, velocity, the game loop.

**Shapes**: Capsule (primary), Sphere, AABB, Triangle mesh.

**Features**: Collision checks (bool), penetration tests (depth + normal + MTV), sweep tests (continuous, time-of-impact), slide operations (sweep + response in one call), depenetration, raycasting (Moller-Trumbore), grounding checks.

**No spatial partitioning** — brute-force all triangles. Fine for small-to-medium scenes. For our overworld, chunk geometry and only feed nearby chunks.

### Build

CMake 3.8+, C11, Python 3.6+ for shader embedding. Dependencies: raylib 5.5+, Assimp 6.0.2+ (both vendorable), GLAD, tinycthread, uthash.
