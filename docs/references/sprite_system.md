# Sprite System

## Overview

2D sprites rendered as billboards in the 3D world. The sprite always faces the camera. No vertex buffer — the quad is generated entirely in the vertex shader from `gl_VertexIndex`.

---

## Billboard Concept

A billboard is a flat quad that always faces the camera. Instead of having a fixed orientation in the world, it's constructed each frame using the camera's right and up vectors:

```
        cam_up
          ^
          |
    +-----+-----+
    |             |
    |   sprite    |  ← always perpendicular to view direction
    |             |
    +------+------+
           |
        cam_right -->
```

The quad is anchored at the bottom center (feet on the ground), not at the center. This means Y offset goes from 0 to 1 (not -0.5 to +0.5), while X offset goes from -0.5 to +0.5.

---

## No Vertex Buffer — Quad from gl_VertexIndex

The sprite pipeline has **zero vertex buffers**. The 4 corners of the quad are generated from the vertex index using bit manipulation:

```glsl
// Triangle strip: 0=BL, 1=BR, 2=TL, 3=TR
vec2 corner = vec2(gl_VertexIndex & 1, gl_VertexIndex >> 1);
```

| Index | `& 1` (X) | `>> 1` (Y) | Corner |
|-------|-----------|------------|--------|
| 0     | 0         | 0          | Bottom-left |
| 1     | 1         | 0          | Bottom-right |
| 2     | 0         | 1          | Top-left |
| 3     | 1         | 1          | Top-right |

With `TRIANGLESTRIP`, these 4 vertices produce 2 triangles: (0,1,2) and (2,1,3).

### Why this works

SDL3 GPU API draws with `DrawGPUPrimitives(render_pass, 4, 1, 0, 0)` — 4 vertices, 1 instance. The vertex shader receives `gl_VertexIndex` = 0..3 and generates the position from that. No buffer to create, upload, or bind.

---

## Billboard Math

Each sprite's world position is offset by the camera's right and up vectors to create the quad:

```glsl
vec3 offset = u_camera_right * u_sprite_size.x * (corner.x - 0.5)
            + u_camera_up * u_sprite_size.y * corner.y;

vec3 world_pos = u_sprite_pos + offset;
gl_Position = u_view_proj * vec4(world_pos, 1.0);
```

- **X**: `(corner.x - 0.5)` centers horizontally (-0.5 to +0.5)
- **Y**: `corner.y` anchors at bottom (0 to 1) — sprite's feet stay at `sprite_pos`
- **sprite_size**: width and height in world units

### Camera vectors

The camera's right and up vectors must be computed alongside `view_proj` each frame. See [camera_system.md](camera_system.md#billboard-vectors) for the math.

---

## Sprite Sheet UV Mapping

The sprite sheet is an atlas of frames. Each frame is defined by a rect `{x, y, w, h}` in pixel coordinates. The vertex shader converts to normalized UVs:

```glsl
vec2 uv_min = (u_sprite_rect.xy + vec2(0.5)) / u_atlas_size;
vec2 uv_max = (u_sprite_rect.xy + u_sprite_rect.zw - vec2(0.5)) / u_atlas_size;
v_uv = mix(uv_min, uv_max, vec2(corner.x, 1.0 - corner.y));
```

### Half-pixel inset

The `+ vec2(0.5)` and `- vec2(0.5)` inset the UV range by half a pixel on each side. This prevents **atlas bleeding** — when the GPU samples at the edge of a sprite frame, it could pick up texels from the adjacent frame. The half-pixel inset keeps sampling safely within the frame.

### Y flip

`1.0 - corner.y` flips the V coordinate because in our vertex layout, corner.y=0 is the bottom of the sprite (ground level) but in the texture, row 0 is the top.

---

## Alpha Test

The fragment shader does a hard alpha cutoff for crisp pixel art edges:

```glsl
vec4 tex_color = texture(u_texture, v_uv);
if (tex_color.a < 0.5) {
    discard;
}
frag_color = tex_color;
```

`discard` tells the GPU to skip this fragment entirely — no color write, no depth write. This gives clean transparent regions without needing alpha blending (which would require depth sorting).

---

## Sprite_Uniforms (std140)

Must match the shader's uniform block exactly. std140 alignment rules: `vec3` occupies 16 bytes (padded to vec4 alignment).

```odin
Sprite_Uniforms :: struct {
    view_proj:    matrix[4, 4]f32,  // 64 bytes
    camera_right: [3]f32,           // 12 bytes
    _pad0:        f32,              //  4 bytes (std140 padding)
    camera_up:    [3]f32,           // 12 bytes
    _pad1:        f32,              //  4 bytes
    sprite_pos:   [3]f32,           // 12 bytes
    _pad2:        f32,              //  4 bytes
    sprite_size:  [2]f32,           //  8 bytes
    atlas_size:   [2]f32,           //  8 bytes
    sprite_rect:  [4]f32,           // 16 bytes (x, y, w, h in pixels)
}
```

Total: 144 bytes.

---

## Pipeline Differences from Mesh

| Setting | Mesh Pipeline | Sprite Pipeline |
|---------|---------------|-----------------|
| Vertex input | 1 buffer, 3 attributes | None (0 buffers, 0 attributes) |
| Primitive type | TRIANGLELIST | TRIANGLESTRIP |
| Cull mode | BACK | NONE |
| Depth test | Yes (LESS_OR_EQUAL) | Yes (LESS_OR_EQUAL) |
| Depth write | Yes | Yes |
| Sampler filter | NEAREST | NEAREST |
| Sampler address | REPEAT | CLAMP_TO_EDGE |

Sprites use CLAMP_TO_EDGE to prevent wrapping artifacts at atlas edges. The ground uses REPEAT so the checkerboard tiles.

---

## Texture Loading with stb_image

First real texture from disk. Uses Odin's `vendor:stb/image`:

```odin
import stbi "vendor:stb/image"
import "core:c"

width, height, channels: c.int
pixels := stbi.load("assets/sprites/nate.png", &width, &height, &channels, 4)
if pixels == nil {
    // stbi.failure_reason() returns a cstring describing what went wrong
}
defer stbi.image_free(pixels)
```

- `4` as the last argument forces RGBA output regardless of source format
- Returns `[^]byte` — a multi-pointer to the pixel data
- Must free with `stbi.image_free`, not our arena allocator
- Upload to GPU via transfer buffer (same pattern as procedural textures)

### Nate sprite sheet

- File: `assets/sprites/nate.png`
- Atlas size: 364x724 pixels
- Cell size: 33x33 pixels
- Idle down frame: `{0, 33, 33, 33}` (x=0, y=33, w=33, h=33)

---

## Key Files

- `shaders/sprite.vert.glsl` — billboard vertex shader
- `shaders/sprite.frag.glsl` — alpha test fragment shader
- `src/main.odin` — pipeline creation, texture loading, draw call
- `assets/sprites/nate.png` — sprite sheet
