package main
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
	camera: Camera,

	// entities stuff
	entities:     [MaxEntities]Entity,

	// Debug
	//  debug camera state
	debug_mode:   bool,
	debug_cam:    Debug_Camera,
	saved_cam:    Camera,
	debug_timing: Debug_Timing,
}

Game_Input :: struct {
	move_up:      Button_State,
	move_down:    Button_State,
	move_left:    Button_State,
	move_right:   Button_State,
	action_a:     Button_State, // confirm / interact
	action_b:     Button_State, // cancel / back

	// Mouse
	// Accumulated per-frame
	scroll_delta:    f32,
	mouse_delta:     Vec2,

	// Updated per-event (like buttons)
	mouse_position:  Vec2,
	mouse_left:      Button_State,
	mouse_right:     Button_State,
}

get_player :: proc() -> ^Entity {
	return &game.entities[EntityIDPlayer]
}

entity_null :: proc() -> Entity {
	return game.entities[EntityIDNull]
}

game_update_and_render :: proc(state: ^Game_State, input: ^Game_Input, dt: f32) {

}

