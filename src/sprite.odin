package main

// Must match sprite.vert.glsl SpriteUniforms (std140 layout)
Sprite_Uniforms :: struct {
	view_proj:    matrix[4, 4]f32,
	camera_right: Vec3,
	_pad0:        f32,
	camera_up:    Vec3,
	_pad1:        f32,
	sprite_pos:   Vec3,
	_pad2:        f32,
	sprite_size:  Vec2,
	atlas_size:   Vec2,
	sprite_rect:  Vec4, // x, y, w, h in pixels
}

Sprite :: struct {
	rect: Vec4,
	size: Vec2,
	tint: Vec4,
}

SpriteAnimation :: struct {
	// animations
	anim_timer: f32,
	anim_frame: int,
	is_playing: bool,
}
