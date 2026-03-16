# Marooned

FPS boomer shooter with Doom-style billboards and dungeon design. Raylib + C++.

- Repo: https://github.com/Jhyde927/Marooned
- Location: ~/code/ext/Marooned/

## Why It's Here

Good reference for billboard sprites in a 3D world, hand-rolled physics, and dungeon-image-as-level-data. Closest existing project to our "2D sprites in 3D world" visual style, just from an FPS perspective instead of top-down.

## Stealable Ideas

- **Billboard sprites with directional facing**: Front/back/side rows in spritesheet, picks row based on angle to camera. Exactly what we need for our creature/NPC sprites.
- **Dungeon image as level data**: Color-coded PNG where each pixel is a tile — enemies, doors, lights, portals all encoded as colors. Dead simple level authoring in any image editor. Could adapt for our tile world.
- **Asymmetric gravity**: 2x heavier falling vs rising for snappier jump feel. Small tweak, big difference in game feel.
- **Baked + dynamic hybrid lighting**: Static lights baked once per level, dynamic lights stamped per frame without occlusion. Cheap and good enough. Relevant for our day/night + zone lighting.
- **Transparency sorting**: All transparent draws queued, sorted by camera distance, drawn back-to-front. Standard approach we'll need for our billboard sprites.
- **Natural feel over realism**: Sine waves for weapon bob, exponential curves for input, asymmetric gravity. Recurring pattern — game feel > physical accuracy.

## Full Summary

### Physics

All custom, no external library — just C++ with raylib math.

- **Movement**: Velocity-based with acceleration/deceleration. Gravity is asymmetric — 2x heavier when falling vs rising for a snappier feel. Player uses 9-point ground sampling (center + 8 offsets) requiring 5/9 solid samples to count as grounded.
- **Collisions**: Sequential per-frame resolution — bullets first, then player vs enemies, then everything vs static geometry. Uses box-sphere (player/enemies vs walls) and ray-sphere (bullets vs characters). No constraint solver, just push-out-by-overlap.
- **Bullets**: All projectile types share gravity + velocity, but differ in behavior — blunderbuss fires 7 pellets in a cone, harpoon sticks and pulls (grapple physics at 3000 units/sec with 0.125x gravity), fireballs explode with area damage, iceballs freeze.
- **Ricochets**: Velocity reflection `v' = v - 2*dot(v,n)*n` with 60% energy retention, minimum speed threshold, and 50% random chance. Head-on hits get absorbed instead of bouncing.
- **Jump buffering**: 50ms input buffer, coyote time disabled (0s).

### First-Person Camera & Weapons

Custom camera system — not raylib's built-in.

- **Camera**: Singleton `CameraSystem` with separate rigs for player/free/cinematic/death modes. Exponential smoothing (22.0 XZ, 10.0 Y) for position following. Pitch clamped to ±30 degrees, mouse sensitivity 0.05.
- **Viewmodels**: Weapons are world-space models positioned relative to camera basis vectors (forward/right/up offsets). No separate viewmodel layer. Rotation via quaternion extracted from inverted lookat matrix. Side offset adjusts dynamically for ultrawide aspect ratios.
- **Weapon bob**: Sinusoidal — vertical `sin(t*12)` and horizontal `sin(t*6)` while moving, lerps to zero when stopped. Per-weapon amplitudes.
- **Recoil**: Forward offset reduction on fire, exponential recovery (crossbow: 20 units, blunderbuss: 15, staff: 8).
- **Firing**: Blunderbuss uses bloom-based spread (1.5-6 degrees) tied to movement state. Crossbow raycasts from screen center. Sword has a hitbox window at 0.1-0.25s into the 0.7s swing. Staff fires projectiles or melee swings.
- **Switching**: 0.3s duration with a "dip" animation that pushes the old weapon down before the new one rises.

### World Generation

Hybrid: file-based, not procedural.

- **Overworld**: Grayscale heightmap PNGs (e.g. `MiddleIsland.png`). Each pixel = height sample, scaled to 16,000x16,000 world units. Terrain is chunked into 129x129 vertex tiles, frustum-culled with a 250-chunk-per-frame cap, sorted front-to-back.
- **Dungeons**: Color-coded PNG images where each pixel is a tile (200 world units). Colors encode everything — red = skeleton, green = player start, purple = doorway, yellow = light, etc. All authored by hand in an image editor.
- **Level loading**: 20 levels defined in a hardcoded `LevelData` array. No streaming — entire level loads at once behind a fade-to-black. `InitLevel()` scans the dungeon image pixel-by-pixel to spawn walls, enemies, doors, lights, props.
- **Vegetation**: Deterministic grid placement (150-unit spacing) with height thresholds, avoidance checks (other trees, dungeon entrances, start position), random rotation/scale variation. Filtered to remove trees spawning in water.
- **Tree shadows**: Baked into a 4096x4096 shadow mask texture at level load.

### Enemy AI & UI

11 enemy types with a shared finite state machine (Idle -> Chase -> Attack -> Reposition, plus Freeze, RunAway, Harpooned, Death).

- **Detection**: Requires actual line-of-sight raycast, not just distance. Enemies remember player position for 10 seconds after losing sight. Alert system broadcasts to nearby skeletons within 3000 units for group hunts.
- **Crowd control**: Tile occupancy system prevents stacking — when two enemies want the same tile, pointer address comparison decides who repositions. Repulsion force (500-unit radius, 6000 strength) keeps groups spread out.
- **Enemy rendering**: Billboard sprites with directional facing (front/back/side rows in spritesheet), per-state animation rows.

### Rendering Pipeline

3-pass architecture with baked+dynamic hybrid lighting.

- **Pass 1 (Scene)**: Renders to intermediate texture. Order: skybox (depth disabled) -> terrain -> water -> dungeon geometry -> characters (billboards) -> bullets -> particles.
- **Pass 2 (Post-process)**: Fog shader applies vignette, damage/freeze color overlays, dungeon darkening, and contrast boost.
- **Pass 3 (Final)**: Bloom extraction (5x5 gaussian, luminance threshold 0.8), ACES or Reinhard tone mapping. UI, weapons, and minimap drawn on top.
- **Lighting**: Static lights baked once per level. Dynamic lights stamped into the lightmap every frame without occlusion. Door open/close triggers local re-bake.

### Recurring Patterns

- Enums over polymorphism, maps over complex class hierarchies
- The dungeon PNG image drives everything — enemy placement, portal groups, switch lock types, lighting, wall runs
- State machines via enums everywhere (AI, eggs, portals, camera modes)
- Update() and Draw() always separate
- Natural feel over realism (sine waves for bob, exponential curves for input, asymmetric gravity)
