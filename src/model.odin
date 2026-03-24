package main

Mesh_Vertex :: struct {
	position: Vec3,
	uv:       Vec2,
	normal:   Vec3,
}

Mesh_Uniforms :: struct {
	view_proj: matrix[4, 4]f32,
	model:     matrix[4, 4]f32,
}
