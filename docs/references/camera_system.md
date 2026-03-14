# Camera System

## Overview

Two cameras: a **follow camera** for gameplay and a **debug free camera** for inspecting the world. F1 toggles between them. The follow camera saves/restores when entering/exiting debug mode.

---

## Follow Camera (gameplay)

The follow camera is defined by three values:

```odin
Camera :: struct {
    target:   [3]f32,  // world position we're looking at
    distance: f32,     // how far away from target
    pitch:    f32,     // angle above horizontal (radians)
}
```

### How position is derived

The camera doesn't store its own position. Instead, position is **computed** from target + distance + pitch using spherical coordinates:

```
        eye •
           /|
          / |
    dist /  | offset_y = distance * sin(pitch)
        /   |
       / α  |  (α = pitch angle)
      /_____|
    target   offset_z = distance * cos(pitch)
```

```odin
offset_y := cam.distance * math.sin(cam.pitch)  // how high above target
offset_z := cam.distance * math.cos(cam.pitch)  // how far behind target
eye := cam.target + {0, offset_y, offset_z}
```

The camera is always directly behind and above the target (no yaw rotation). This gives the fixed isometric-ish angle of Pokemon HGSS / Link's Awakening.

### View matrix

Built with `look_at`:

```odin
view := linalg.matrix4_look_at_f32(eye, cam.target, {0, 1, 0})
```

This creates a matrix that transforms world space into camera space — "if the camera were at the origin looking down -Z, where would everything be?"

### Projection matrix

Standard perspective projection, computed once:

```odin
proj := linalg.matrix4_perspective_f32(
    math.to_radians(f32(45.0)),                      // 45 degree vertical FOV
    f32(WINDOW_WIDTH) / f32(WINDOW_HEIGHT),           // aspect ratio
    0.1,                                               // near plane
    100.0,                                             // far plane
)
```

The perspective matrix transforms camera space into **clip space** — the normalized coordinate system the GPU uses. Objects further away appear smaller. The near/far planes define the visible depth range.

### view_proj

```odin
view_proj = proj * view
```

This single matrix goes from **world space → clip space** in one multiply. It's what the vertex shader uses:

```glsl
gl_Position = u_view_proj * u_model * vec4(a_position, 1.0);
```

The transform chain: **model space → world space → camera space → clip space**.

### Zoom

Scroll wheel changes `cam.distance`, clamped to `[CAMERA_DIST_MIN, CAMERA_DIST_MAX]`:

```odin
cam.distance -= event.wheel.y * CAMERA_ZOOM_SPEED
cam.distance = clamp(cam.distance, CAMERA_DIST_MIN, CAMERA_DIST_MAX)
```

Scrolling up (positive y) decreases distance = zooms in. The eye position recomputes next frame.

### Target following

Currently WASD moves `cam.target` for testing. In Phase 5 this becomes `cam.target = player.position`.

---

## Debug Free Camera (F1)

An FPS-style camera for inspecting the world. Position + orientation are independent.

```odin
Debug_Camera :: struct {
    position: [3]f32,  // where the camera is
    yaw:      f32,     // rotation around Y axis (radians)
    pitch:    f32,     // rotation up/down (radians)
    speed:    f32,     // movement speed (adjustable with scroll)
}
```

### How direction is derived

The camera's forward vector is computed from yaw and pitch using spherical coordinates:

```
          +Y (up)
           |  / forward
           | / pitch angle
           |/_________ -Z (base forward)
          /
         / yaw angle
        +X (right)
```

```odin
forward := [3]f32{
    math.sin(yaw) * math.cos(pitch),   // X component
    math.sin(pitch),                     // Y component (up/down)
    -math.cos(yaw) * math.cos(pitch),  // Z component (note: -Z is forward)
}
right := [3]f32{math.cos(yaw), 0, math.sin(yaw)}
```

At yaw=0, pitch=0: forward = {0, 0, -1} (looking down -Z axis).

**Why -Z?** Our coordinate system is right-handed: +X right, +Y up, +Z towards the viewer. So "into the screen" (forward) is -Z. This matches OpenGL/Metal conventions.

### Mouse look

Mouse movement in relative mode gives pixel deltas. Multiply by sensitivity to get rotation:

```odin
debug_cam.yaw   += xrel * MOUSE_SENSITIVITY    // horizontal mouse → yaw
debug_cam.pitch -= yrel * MOUSE_SENSITIVITY    // vertical mouse → pitch (inverted: mouse up = look up)
debug_cam.pitch  = clamp(pitch, -85°, +85°)   // prevent gimbal lock at poles
```

Pitch is clamped to avoid the singularity when looking straight up or down (the `up` vector and `forward` vector would become parallel, breaking `look_at`).

### Movement

WASD moves along the camera's own axes:

```odin
W: position += forward * speed * dt   // forward
S: position -= forward * speed * dt   // backward
D: position += right * speed * dt     // strafe right
A: position -= right * speed * dt     // strafe left
E: position.y += speed * dt           // straight up (world Y)
Q: position.y -= speed * dt           // straight down (world Y)
```

E/Q move along world Y (not camera Y) — this is the UE convention and feels more natural for level inspection.

Scroll wheel adjusts `speed`, clamped to `[DEBUG_CAM_SPEED_MIN, DEBUG_CAM_SPEED_MAX]`.

### View matrix

```odin
view := linalg.matrix4_look_at_f32(position, position + forward, {0, 1, 0})
```

Same function as the follow camera, just different inputs.

---

## F1 Toggle — Save/Restore

When entering debug mode, the follow camera is saved and the debug camera is initialized at the follow camera's current eye position, looking in the same direction:

```odin
// Save
saved_cam = cam

// Init debug camera at follow camera's eye position
debug_cam.position = eye (computed from cam.target + offset)
debug_cam.yaw = 0
debug_cam.pitch = -cam.pitch  // looking down at the target
```

When exiting debug mode, the follow camera is restored exactly:

```odin
cam = saved_cam  // snap back to where you were
```

This means you can fly around, inspect anything, and F1 back to exactly where the gameplay camera was.

---

## Billboard Vectors

Both cameras compute `cam_right` and `cam_up` alongside `view_proj` each frame. These are needed by the sprite system for billboarding (see [sprite_system.md](sprite_system.md)).

### Follow camera

The follow camera has no yaw (always behind the target), so right is always world X:

```odin
cam_right = {1, 0, 0}
cam_forward := [3]f32{0, -math.sin(cam.pitch), -math.cos(cam.pitch)}
cam_up = linalg.cross(cam_right, cam_forward)
// cam_up = {0, cos(pitch), -sin(pitch)}
```

### Debug camera

The debug camera has arbitrary yaw, so right depends on orientation:

```odin
cam_right = right  // = {cos(yaw), 0, sin(yaw)}, already computed for movement
cam_up = linalg.cross(right, forward)
// cam_up = {-sin(yaw)*sin(pitch), cos(pitch), cos(yaw)*sin(pitch)}
```

### Why cross(right, forward) and not cross(forward, up)?

`cross(right, forward)` gives us the camera's true up vector — perpendicular to both the right axis and the view direction. This is what we need for billboarding: the sprite should expand along the camera's actual up, not the world up. If the camera is pitched down (as the follow camera always is), world up `{0,1,0}` would make sprites lean away from the viewer.

---

## Key Concepts

### World space vs Camera space vs Clip space

1. **Model space**: vertices as defined in the mesh (e.g., ground quad centered at origin)
2. **World space**: after `model` matrix transform (position/rotation/scale in the world)
3. **Camera space**: after `view` matrix (world as seen from camera's perspective — camera at origin, looking down -Z)
4. **Clip space**: after `projection` matrix (perspective division happens here, things far away shrink)
5. **Screen space**: GPU maps clip space to pixels

### Why `look_at` works

`look_at(eye, centre, up)` builds an orthonormal basis:
1. `forward = normalize(centre - eye)` — direction camera faces
2. `right = normalize(cross(forward, up))` — camera's right axis
3. `up = cross(right, forward)` — camera's true up (may differ from world up)

These three vectors become the rows of a rotation matrix. Combined with a translation to move the origin to `eye`, this is the view matrix.

### Why pitch is clamped

At pitch = ±90°, the forward vector becomes parallel to the up vector {0, 1, 0}. The cross product `cross(forward, up)` becomes zero, which means `look_at` can't determine the right vector. The matrix degenerates. Clamping to ±85° keeps us safely away from this singularity.