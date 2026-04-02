package main

import "core:log"
import "core:math"
import "core:math/linalg"

// Game Config
GameFOV :: 45.0 * math.RAD_PER_DEG
GameNearPlane :: f32(0.1)
GameFarPlane :: f32(100.0)
GameCameraUp :: Vec3{0, 1, 0}
GameCameraRight :: Vec3{1, 0, 0}
DebugGameCameraEyeCrossSize :: f32(0.3)

//	Entities
MaxEntities :: 1024
EntityIDNull :: 0
EntityIDPlayer :: 1
PlayerMoveSpeed :: f32(5.0)

Game_State :: struct {
	view_proj:                linalg.Matrix4f32,
	camera:                   Camera,
	camera_right:             Vec3,
	camera_up:                Vec3,

	// entities stuff
	entities:                 [MaxEntities]Entity,

	// settings
	vsync:                    bool,
	quit_game:                bool,

	// Debug
	//  debug camera state
	debug_mode:               bool,
	debug_cam:                Debug_Camera,
	debug_game_cam_view_proj: linalg.Matrix4f32,
	debug_game_cam_eye:       Vec3,
	debug_frustum_corners:    [8]Vec3,
}

Game_Input :: struct {
	buttons:              [InputAction]Button_State,

	// Mouse
	// Accumulated per-frame
	mouse_scroll_delta:   f32,
	mouse_position:       Vec2,
	mouse_position_delta: Vec2,
	mouse_left:           Button_State,
	mouse_right:          Button_State,
}

// math and other stuff
Vec4 :: [4]f32
Vec3 :: [3]f32
Vec2 :: [2]f32

Color :: Vec4

ColorYellow :: Color{1, 1, 0, 1}
ColorCyan :: Color{0, 1, 1, 1}

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
	if is_key_pressed(game_input, .Cancel) {
		game.quit_game = true
	}

	if is_key_pressed(game_input, .DebugToggleVsync) {
		game.vsync = !game.vsync
	}

	// handle camera update
	aspect := f32(window_width) / f32(window_height)
	proj := linalg.matrix4_perspective_f32(GameFOV, aspect, GameNearPlane, GameFarPlane)
	if is_key_pressed(game_input, .DebugToggle) {
		game.debug_mode = !game.debug_mode
		if game.debug_mode {
			log.infof("Enabling debug mode")
			// Enter debug mode — save follow camera, init debug camera
			// at current eye position
			game.debug_cam = Debug_Camera {
				position = game.debug_game_cam_eye,
				yaw      = 0,
				pitch    = -game.camera.pitch, // looking down at target
				speed    = DebugCamSpeedDefault,
			}
		} else {
			// Exit debug mode — restore follow camera
			log.infof("Disabling debug mode")
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

		if is_key_down(game_input, .MoveUp) do game.debug_cam.position += forward * move_speed
		if is_key_down(game_input, .MoveDown) do game.debug_cam.position -= forward * move_speed
		if is_key_down(game_input, .MoveRight) do game.debug_cam.position += right * move_speed
		if is_key_down(game_input, .MoveLeft) do game.debug_cam.position -= right * move_speed
		if is_key_down(game_input, .CamFlyUp) do game.debug_cam.position.y += move_speed
		if is_key_down(game_input, .CamFlyDown) do game.debug_cam.position.y -= move_speed

		view := linalg.matrix4_look_at_f32(game.debug_cam.position, game.debug_cam.position + forward, GameCameraUp)
		game.view_proj = proj * view
		game.camera_right = right
		game.camera_up = linalg.cross(right, forward)

		// compute the game's camera frustum for debug visualization
		game.debug_frustum_corners = unproject_frustum_corners(game.debug_game_cam_view_proj)
	} else {
		// Scroll zooms follow camera
		game.camera.distance -= game_input.mouse_scroll_delta * CameraZoomSpeed
		game.camera.distance = clamp(game.camera.distance, CameraDistMin, CameraDistMax)

		move_x: f32
		move_z: f32
		if is_key_down(game_input, .MoveUp) do move_z -= 1
		if is_key_down(game_input, .MoveDown) do move_z += 1
		if is_key_down(game_input, .MoveLeft) do move_x -= 1
		if is_key_down(game_input, .MoveRight) do move_x += 1

		player := get_player(game)
		player_is_moving := move_x != 0 || move_z != 0
		if player_is_moving {
			// Normalize so diagonals aren't faster
			length := math.sqrt(move_x * move_x + move_z * move_z)
			move_x /= length
			move_z /= length

			player.position.x += move_x * PlayerMoveSpeed * dt
			player.position.z += move_z * PlayerMoveSpeed * dt

			// Pick closest 4-direction for sprite facing
			if abs(move_z) >= abs(move_x) {
				player.direction = move_z < 0 ? .Up : .Down
			} else {
				player.direction = move_x < 0 ? .Left : .Right
			}
		}

		// follow player
		game.camera.target = player.position

		offset_y := game.camera.distance * math.sin(game.camera.pitch)
		offset_z := game.camera.distance * math.cos(game.camera.pitch)
		eye := game.camera.target + {0, offset_y, offset_z}
		view := linalg.matrix4_look_at_f32(eye, game.camera.target, GameCameraUp)
		game.view_proj = proj * view
		game.camera_right = GameCameraRight
		cam_forward := Vec3{0, -math.sin(game.camera.pitch), -math.cos(game.camera.pitch)}
		game.camera_up = linalg.cross(game.camera_right, cam_forward)

		// store the camera values for debugging later
		game.debug_game_cam_eye = eye
		game.debug_game_cam_view_proj = game.view_proj

		// sprites animation update
		if player_is_moving {
			player.sprite_animation.anim_timer += dt
			frame_duration := 1.0 / NateWalkFPS
			// using for instead of if here in case we get a frame rate spike,
			// we don't play the wrong animation frame
			for player.sprite_animation.anim_timer >= frame_duration {
				player.sprite_animation.anim_timer -= frame_duration
				player.sprite_animation.anim_frame =
					(player.sprite_animation.anim_frame + 1) % len(nate_walk_frames[player.direction])
			}
			player.sprite_animation.is_playing = true
		} else {
			player.sprite_animation = {}
		}
	}
}

get_player :: proc(game: ^Game_State) -> ^Entity {
	return &game.entities[EntityIDPlayer]
}

entity_null :: proc(game: Game_State) -> Entity {
	return game.entities[EntityIDNull]
}

