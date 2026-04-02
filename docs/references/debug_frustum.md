# Debug Frustum Visualization

## What It Does

When debug mode is active (F1), draws the follow camera's view frustum as a yellow wireframe
and the camera eye position as a cyan cross. Lets you see exactly what the game camera sees
from the free-fly debug camera perspective.

## Coordinate Spaces

The GPU transforms every vertex through this chain:

```
World Space  -->  Clip Space  -->  NDC
(3D scene)        (homogeneous)    (normalized screen box)
```

**World Space** — where your entities, ground, and cameras live. The coordinates you work with in game code.

**Clip Space** — result of `view_proj * position`. Homogeneous coordinates (x, y, z, w). The GPU clips anything outside the visible volume here.

**NDC (Normalized Device Coordinates)** — clip space after dividing by w. The final "flat screen" space before rasterization:
- x: -1 (left) to +1 (right)
- y: -1 (bottom) to +1 (top)
- z: 0 (near plane) to 1 (far plane) — Vulkan/Metal convention. OpenGL uses -1 to 1.

Everything inside this box is visible. Everything outside is clipped.

## Unprojecting the Frustum

The frustum is just a box in NDC. To draw it in the world, we go backwards:

```
NDC corners  -->  inverse(view_proj)  -->  perspective divide  -->  World Space
```

The 8 NDC corners (4 near, 4 far):

```
Near (z=0):  (-1,-1,0)  (1,-1,0)  (1,1,0)  (-1,1,0)
Far  (z=1):  (-1,-1,1)  (1,-1,1)  (1,1,1)  (-1,1,1)
```

For each corner:
1. Multiply by `inverse(view_proj)` — gives homogeneous clip-space point (w != 1)
2. Divide xyz by w — perspective divide gives actual world position

## Wireframe Edges

12 line segments connect the 8 corners:
- **Near quad**: 0-1, 1-2, 2-3, 3-0 (rectangle at near plane)
- **Far quad**: 4-5, 5-6, 6-7, 7-4 (rectangle at far plane)
- **Connecting**: 0-4, 1-5, 2-6, 3-7 (near corners to corresponding far corners)

## Line Thickness

SDL3 GPU API only supports 1-pixel lines (LINELIST primitive). Vulkan deprecated wide lines,
Metal and D3D12 never had them. Thicker lines would require generating screen-aligned quads
(two triangles per segment). Not worth it for debug vis.

## Key Files

- `src/debug.odin` — Debug_Line_Vertex, Debug_Line_Uniforms
- `src/game.odin` — unproject_frustum_corners, frustum computation in debug branch
- `src/main.odin` — frustum + eye marker draw calls (gated on debug_mode)
- `src/renderer.odin` — DebugLines pipeline (LINELIST, no cull, no texture)
- `shaders/debug_line.vert.glsl` — passthrough position + color with view_proj
- `shaders/debug_line.frag.glsl` — outputs interpolated color