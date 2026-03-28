package main

import "core:log"
import "core:math"
import "core:math/linalg"

// Game Config
GameFOV :: 45.0 * math.RAD_PER_DEG
GameNearPlane :: f32(0.1)
GameFarPlane :: f32(100.0)
//	Entities
MaxEntities :: 1024
EntityIDNull :: 0
EntityIDPlayer :: 1

Game_State :: struct {
	view_proj:    linalg.Matrix4f32,
	camera:       Camera,
	camera_right: Vec3,
	camera_up:    Vec3,

	// entities stuff
	entities:     [MaxEntities]Entity,

	// settings
	vsync:        bool,
	quit_game:    bool,

	// Debug
	//  debug camera state
	debug_mode:   bool,
	debug_cam:    Debug_Camera,
	saved_cam:    Camera,
}

Game_Input :: struct {
	move_up:              Button_State,
	move_down:            Button_State,
	move_left:            Button_State,
	move_right:           Button_State,
	action_a:             Button_State, // confirm / interact
	action_b:             Button_State, // cancel / back
	cancel:               Button_State,

	// debug, editor, etc
	enable_debug_toggle:  Button_State,
	debug_toggle_vsync:   Button_State,
	cam_fly_up:           Button_State,
	cam_fly_down:         Button_State,

	// Mouse
	// Accumulated per-frame
	mouse_scroll_delta:   f32,
	mouse_position:       Vec2,
	mouse_position_delta: Vec2,
	mouse_left:           Button_State,
	mouse_right:          Button_State,
}

game_init :: proc(game: ^Game_State) {
	player := &game.entities[EntityIDPlayer]
	player^ = Entity {
		kind     = .Player,
		position = {0, 0, 0},
	}

	// Cameras
	game.camera = Camera {
		target   = {0, 0, 0},
		distance = CameraDistDefault,
		pitch    = CameraPitch,
	}

	game.debug_cam = Debug_Camera{}
}

game_update_and_render :: proc(game: ^Game_State, game_input: ^Game_Input, dt: f32, window_width, window_height: u32) {
	// handle app settings
	if game_input.cancel.pressed {
		game.quit_game = true
	}

	if game_input.debug_toggle_vsync.pressed {
		game.vsync = !game.vsync
	}

	// handle camera update
	aspect := f32(window_width) / f32(window_height)
	proj := linalg.matrix4_perspective_f32(GameFOV, aspect, GameNearPlane, GameFarPlane)
	if game_input.enable_debug_toggle.pressed {
		game.debug_mode = !game.debug_mode
		if game.debug_mode {
			log.infof("Enabling debug mode")
			// Enter debug mode — save follow camera, init debug camera
			// at current eye position
			game.saved_cam = game.camera
			offset_y := game.camera.distance * math.sin(game.camera.pitch)
			offset_z := game.camera.distance * math.cos(game.camera.pitch)
			game.debug_cam = Debug_Camera {
				position = game.camera.target + {0, offset_y, offset_z},
				yaw      = 0,
				pitch    = -game.camera.pitch, // looking down at target
				speed    = DebugCamSpeedDefault,
			}
		} else {
			// Exit debug mode — restore follow camera
			log.infof("Disabling debug mode")
			game.camera = game.saved_cam
		}
	}

	// handle game
	if game.debug_mode {
		// Debug Camera
		// Scroll adjusts debug camera game.speed
		game.debug_cam.speed = clamp(
			game.debug_cam.speed + game_input.mouse_scroll_delta * 2.0,
			DebugCamSpeedMin,
			DebugCamSpeedMax,
		)

		game.debug_cam.yaw += game_input.mouse_position_delta.x * MouseSensitivity
		game.debug_cam.pitch -= game_input.mouse_position_delta.y * MouseSensitivity
		game.debug_cam.pitch = clamp(game.debug_cam.pitch, -85.0 * math.RAD_PER_DEG, 85.0 * math.RAD_PER_DEG)
		// Debug free camera — WASD movement along view vectors
		forward := Vec3 {
			math.sin(game.debug_cam.yaw) * math.cos(game.debug_cam.pitch),
			math.sin(game.debug_cam.pitch),
			-math.cos(game.debug_cam.yaw) * math.cos(game.debug_cam.pitch),
		}
		right := Vec3{math.cos(game.debug_cam.yaw), 0, math.sin(game.debug_cam.yaw)}
		move_speed := game.debug_cam.speed * dt

		if game_input.move_up.is_down do game.debug_cam.position += forward * move_speed
		if game_input.move_down.is_down do game.debug_cam.position -= forward * move_speed
		if game_input.move_right.is_down do game.debug_cam.position += right * move_speed
		if game_input.move_left.is_down do game.debug_cam.position -= right * move_speed
		if game_input.cam_fly_up.is_down do game.debug_cam.position.y += move_speed
		if game_input.cam_fly_down.is_down do game.debug_cam.position.y -= move_speed

		view := linalg.matrix4_look_at_f32(game.debug_cam.position, game.debug_cam.position + forward, {0, 1, 0})
		game.view_proj = proj * view
		game.camera_right = right
		game.camera_up = linalg.cross(right, forward)
	} else {
		// Scroll zooms follow camera
		game.camera.distance -= game_input.mouse_scroll_delta * CameraZoomSpeed
		game.camera.distance = clamp(game.camera.distance, CameraDistMin, CameraDistMax)

		// Follow camera — WASD pans target (temporary until player exists)
		if game_input.move_up.is_down do game.camera.target.z -= CameraPanSpeed * dt
		if game_input.move_down.is_down do game.camera.target.z += CameraPanSpeed * dt
		if game_input.move_left.is_down do game.camera.target.x -= CameraPanSpeed * dt
		if game_input.move_right.is_down do game.camera.target.x += CameraPanSpeed * dt

		offset_y := game.camera.distance * math.sin(game.camera.pitch)
		offset_z := game.camera.distance * math.cos(game.camera.pitch)
		eye := game.camera.target + {0, offset_y, offset_z}
		view := linalg.matrix4_look_at_f32(eye, game.camera.target, {0, 1, 0})
		game.view_proj = proj * view
		game.camera_right = {1, 0, 0}
		cam_forward := Vec3{0, -math.sin(game.camera.pitch), -math.cos(game.camera.pitch)}
		game.camera_up = linalg.cross(game.camera_right, cam_forward)
	}

}

get_player :: proc(game: ^Game_State) -> ^Entity {
	return &game.entities[EntityIDPlayer]
}

entity_null :: proc(game: Game_State) -> Entity {
	return game.entities[EntityIDNull]
}

