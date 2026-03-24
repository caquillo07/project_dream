package main

import "core:math"

CameraPitch :: 50.0 * math.RAD_PER_DEG
CameraDistMin :: f32(5.0)
CameraDistMax :: f32(30.0)
CameraDistDefault :: f32(8.0)
CameraZoomSpeed :: f32(1.5)
CameraPanSpeed :: f32(8.0) // temporary WASD panning until player exists

// Follow camera — fixed angle, follows target, scroll-wheel zoom (HGSS / Link's Awakening style)
Camera :: struct {
	target:   Vec3,
	distance: f32,
	pitch:    f32, // fixed angle from horizontal (radians)
}

DebugCamSpeedDefault :: f32(10.0)
DebugCamSpeedMin :: f32(1.0)
DebugCamSpeedMax :: f32(50.0)
MouseSensitivity :: f32(0.003)

// Debug free camera — F1 toggle, FPS-style controls
Debug_Camera :: struct {
	position: Vec3,
	yaw:      f32,
	pitch:    f32,
	speed:    f32,
}

