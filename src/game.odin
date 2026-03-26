package main
// Game Config
//	Entities
MaxEntities :: 1024
EntityIDNull :: 0
EntityIDPlayer :: 1

game: Game

Game :: struct {
	// Debug camera state
	debug_mode:   bool,
	debug_cam:    Debug_Camera,
	saved_cam:    Camera,


	// Input state
	input:        Game_Input,
	debug_timing: Debug_Timing,
	entities:     [MaxEntities]Entity,
}

Game_Input :: struct {
	move_up:    Button_State,
	move_down:  Button_State,
	move_left:  Button_State,
	move_right: Button_State,
	action_a:   Button_State, // confirm / interact
	action_b:   Button_State, // cancel / back
	dt:         f32,
}

get_player :: proc() -> ^Entity {
	return &game.entities[EntityIDPlayer]
}

entity_null :: proc() -> Entity {
	return game.entities[EntityIDNull]
}
