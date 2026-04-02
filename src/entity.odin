package main

// todo for debugging

NateSpriteCellSize :: 33
NateWalkFPS :: f32(6.0)

// sprite_rect = {x, y, w, h} in pixels
// Row per direction: Up=0, Down=1, Left=2, Right=3
// Column 0 = idle, columns 1-2 = walk frames

nate_idle_frames := [Direction]Vec4 {
	.Up    = {0, 0, NateSpriteCellSize, NateSpriteCellSize},
	.Down  = {0, 33, NateSpriteCellSize, NateSpriteCellSize},
	.Left  = {0, 66, NateSpriteCellSize, NateSpriteCellSize},
	.Right = {0, 99, NateSpriteCellSize, NateSpriteCellSize},
}

nate_walk_frames := [Direction][2]Vec4 {
	.Up    = {{33, 0, NateSpriteCellSize, NateSpriteCellSize}, {66, 0, NateSpriteCellSize, NateSpriteCellSize}},
	.Down  = {{33, 33, NateSpriteCellSize, NateSpriteCellSize}, {66, 33, NateSpriteCellSize, NateSpriteCellSize}},
	.Left  = {{33, 66, NateSpriteCellSize, NateSpriteCellSize}, {66, 66, NateSpriteCellSize, NateSpriteCellSize}},
	.Right = {{33, 99, NateSpriteCellSize, NateSpriteCellSize}, {66, 99, NateSpriteCellSize, NateSpriteCellSize}},
}

// todo end of for debugging above

Entity_ID :: distinct i32
Entity :: struct {
	kind:             Entity_Kind,

	// player
	position:         Vec3,
	direction:        Direction,
	speed:            f32,

	// 2d Sprites
	sprite:           Sprite,
	sprite_animation: SpriteAnimation,
}

Entity_Kind :: enum {
	None,
	Player,
}

Direction :: enum {
	Down,
	Up,
	Right,
	Left,
}

