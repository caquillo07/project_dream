package main

Entity_ID :: distinct i32
Entity :: struct {
	kind:      Entity_Kind,

	// player
	position:  Vec3,
	direction: Direction,
	speed:     f32,
}

Entity_Kind :: enum {
	None,
	Player,
}

Direction :: enum {
	Up,
	Down,
	Right,
	Left,
}
