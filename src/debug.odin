package main

import "core:math/linalg"

Debug_Line_Vertex :: struct {
	color:    Vec4,
	position: Vec3,
}

Debug_Line_Uniforms :: struct {
	view_proj: linalg.Matrix4f32,
}

unproject_frustum_corners :: proc(view_proj: linalg.Matrix4f32) -> [8]Vec3 {
	inv := linalg.inverse(view_proj)

	// NDC corners — Vulkan/SDL3: z range [0, 1]
	ndc_corners := [8]Vec4 {
		{-1, -1, 0, 1}, { 1, -1, 0, 1}, { 1,  1, 0, 1}, {-1,  1, 0, 1}, // near
		{-1, -1, 1, 1}, { 1, -1, 1, 1}, { 1,  1, 1, 1}, {-1,  1, 1, 1}, // far
	}

	result: [8]Vec3
	for i in 0 ..< 8 {
		p := inv * ndc_corners[i]
		result[i] = Vec3{p.x, p.y, p.z} / p.w  // perspective divide
	}
	return result
}
