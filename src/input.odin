package main

import sdl "vendor:sdl3"

Button_State :: struct {
	ended_down:       bool, // is the key held right now?
	half_transitions: i32, // how many times did it change state THIS frame?
}

InputAction :: enum {
	MoveUp,
	MoveDown,
	MoveLeft,
	MoveRight,
	ActionA,
	ActionB,
	Cancel,
	DebugToggle,
	DebugToggleVsync,
	CamFlyUp,
	CamFlyDown,
	GlobalGamePause,
}


is_key_down :: proc(i: ^Game_Input, a: InputAction) -> bool {
	return button_is_down(i.buttons[a])
}

is_key_pressed :: proc(i: ^Game_Input, a: InputAction) -> bool {
	return button_is_pressed(i.buttons[a])
}

is_key_released :: proc(i: ^Game_Input, a: InputAction) -> bool {
	return button_is_released(i.buttons[a])
}

button_is_pressed :: proc(b: Button_State) -> bool {
	return b.half_transitions > 1 || (b.half_transitions == 1 && b.ended_down)
}

button_is_released :: proc(b: Button_State) -> bool {
	return b.half_transitions > 1 || (b.half_transitions == 1 && !b.ended_down)
}

button_is_down :: proc(b: Button_State) -> bool {
	return b.ended_down
}

// todo - move all below to platform layer later...

key_bindings := [InputAction]sdl.Scancode {
	.MoveUp           = .W,
	.MoveDown         = .S,
	.MoveLeft         = .A,
	.MoveRight        = .D,
	.ActionA          = .SPACE,
	.ActionB          = .E,
	.Cancel           = .ESCAPE,

	// debug, editor, etc related
	.DebugToggle      = .F1,
	.DebugToggleVsync = .V,
	.CamFlyUp         = .E,
	.CamFlyDown       = .Q,
	.GlobalGamePause  = .P,
}

update_button :: proc(button: ^Button_State, is_down: bool) {
	if button.ended_down != is_down {
		button.ended_down = is_down
		button.half_transitions += 1
	}
}

reset_game_input :: proc(input: ^Game_Input) {
	input.mouse_scroll_delta = 0
	input.mouse_position_delta = {}
	input.mouse_left.half_transitions = 0
	input.mouse_right.half_transitions = 0

	for &b in input.buttons {
		b.half_transitions = 0
	}
}

