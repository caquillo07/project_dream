package main

import "core:math"
import "core:math/linalg"

// Game Config
//	Entities
MaxEntities :: 1024
EntityIDNull :: 0
EntityIDPlayer :: 1

Debug_Timing :: struct {
	fps:      f32,
	frame_ms: f32,
}

Game_State :: struct {
	view_proj:    linalg.Matrix4f32,
	camera:       Camera,
	camera_right: Vec3,
	camera_up:    Vec3,

	// entities stuff
	entities:     [MaxEntities]Entity,

	// Debug
	//  debug camera state
	debug_mode:   bool,
	debug_cam:    Debug_Camera,
	saved_cam:    Camera,
}

Game_Input :: struct {
	move_up:        Button_State,
	move_down:      Button_State,
	move_left:      Button_State,
	move_right:     Button_State,
	action_a:       Button_State, // confirm / interact
	action_b:       Button_State, // cancel / back

	// debug, editor, etc
	cam_fly_up:     Button_State,
	cam_fly_down:   Button_State,

	// Mouse
	// Accumulated per-frame
	scroll_delta:   f32,
	mouse_delta:    Vec2,

	// Updated per-event (like buttons)
	mouse_position: Vec2,
	mouse_left:     Button_State,
	mouse_right:    Button_State,
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

game_update_and_render :: proc(game: ^Game_State, game_input: ^Game_Input, dt: f32, proj: linalg.Matrix4f32) {
	// todo - old input loop, consolidate with below

	if game.debug_mode {
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

