package main

import "core:path/filepath"

import sdl "vendor:sdl3"

import gltf "../ext-libs/glTF2"
import log "core:log"

//  meshes:        [body_mesh, armor_mesh, belt_mesh, eyes_mesh]
//  materials:     [leather_material, eye_material]
//  mesh_material: [0, 0, 0, 1]
//                  ^  ^  ^  ^
//                  |  |  |  └─ eyes_mesh uses eye_material (index 1)
//                  |  |  └──── belt_mesh uses leather_material (index 0)
//                  |  └─────── armor_mesh uses leather_material (index 0)
//                  └────────── body_mesh uses leather_material (index 0)
Model :: struct {
	meshes:        []Model_Mesh,
	materials:     []Model_Material,
	mesh_material: []int, // maps which materials[i] meshes[i] holds

	// Skeleton (todo Phase 6.5 — nil for static models)
	bones:         []Bone,
	bind_pose:     []Transform,

	// Runtime animation state (todo Phase 6.5)
	current_pose:  []Transform,
	bone_matrices: []matrix[4, 4]f32,
}

Model_Mesh :: struct {
	vertices:      []Model_Vertex,
	indices:       []u32,

	// todo - phase 7 will abstract these into handles
	vertex_buffer: ^sdl.GPUBuffer,
	index_buffer:  ^sdl.GPUBuffer,
}

Model_Vertex :: struct {
	position:     Vec3,
	uv:           Vec2,
	normal:       Vec3,
	// every model can influences by at _most_ 4 bones, glTF spec max.
	bone_ids:     [4]u8, // 256 max bones per skeleton, enough for us now...
	bone_weights: [4]f32,
}

Model_Material :: struct {
	base_color_texture: Texture,
	color_tint:         Vec4,
	metallic_factor:    f32,
	roughness_factor:   f32,
}

Mesh_Uniforms :: struct {
	view_proj:  matrix[4, 4]f32,
	model:      matrix[4, 4]f32,
	color_tint: Vec4,
}

Bone :: struct {}

Transform :: struct {}

load_model :: proc(path: string) -> (Model, bool) {
	m, ok := load_model_from_file(path)
	if !ok do return {}, ok

	for &mesh in m.meshes {
		mesh.vertex_buffer = renderer_upload_buffer(mesh.vertices, .VERTEX)
		mesh.index_buffer = renderer_upload_buffer(mesh.indices, .INDEX)
	}
	return m, true
}

load_model_from_file :: proc(path: string) -> (Model, bool) {
	model_file_name := filepath.base(path)
	log.infof("loading %s model from %s", model_file_name, path)

	model_data, load_err := gltf.load_from_file(path, context.temp_allocator)
	if load_err != nil {
		log.errorf("failed to load model at %s: %v", path, load_err)
		return {}, false
	}

	// mesh primitives
	total_meshes: int
	for mesh in model_data.meshes {
		total_meshes += len(mesh.primitives)
	}

	m := Model {
		meshes        = make([]Model_Mesh, total_meshes),
		materials     = make([]Model_Material, max(len(model_data.materials), 1)), // always at least one
		mesh_material = make([]int, total_meshes),
	}

	// extract meshes
	mesh_index: int
	for gltf_mesh in model_data.meshes {
		for primitive in gltf_mesh.primitives {
			// model positions
			position_index, has_position := primitive.attributes["POSITION"]
			if !has_position {
				log.warn("Mesh primitive has no POSITION attribute, skipping")
				continue
			}
			positions := read_gltf2_accessor([3]f32, model_data, position_index)

			// normals, if missing, default to UP
			normals: [][3]f32
			if normal_index, has_normal := primitive.attributes["NORMAL"]; has_normal {
				normals = read_gltf2_accessor([3]f32, model_data, normal_index)
			}
			// UVs, if missing, defaults to {0,0,0}
			uvs: [][2]f32
			if uv_index, has_uv := primitive.attributes["TEXCOORD_0"]; has_uv {
				uvs = read_gltf2_accessor([2]f32, model_data, uv_index)
			}
			// interleave into Model_Vertex
			vertices := make([]Model_Vertex, len(positions))
			for i in 0 ..< len(positions) {
				vertex := &vertices[i]
				vertex.position = positions[i]

				if len(normals) > 0 {
					vertex.normal = normals[i]
				} else {
					vertex.normal = {0, 1, 0}
				}
				if len(uvs) > 0 {
					vertex.uv = Vec2{uvs[i].x, uvs[i].y}
				}

				// for static models, {1,0,0,0} means 100% influced by 0
				vertices[i].bone_weights = {1, 0, 0, 0} // todo for animated models
			}

			// indices
			indices: []u32
			if indices_accessor_index, has_indices := primitive.indices.?; has_indices {
				accessor := model_data.accessors[indices_accessor_index]
				#partial switch accessor.component_type {
				case gltf.Component_Type.Unsigned_Short:
					raw_indices := read_gltf2_accessor(u16, model_data, indices_accessor_index)
					indices = make([]u32, len(raw_indices))
					for i in 0 ..< len(raw_indices) {
						indices[i] = u32(raw_indices[i])
					}
				case gltf.Component_Type.Unsigned_Int:
					indices = read_gltf2_accessor(u32, model_data, indices_accessor_index)
				case:
					log.fatal("unsupported glTF2 component type %v", accessor.component_type)
					panic("unimplemented")
				}
			}
			m.meshes[mesh_index] = Model_Mesh {
				vertices = vertices,
				indices  = indices,
			}

			// material mapping
			if material_index, has_material := primitive.material.?; has_material {
				m.mesh_material[mesh_index] = int(material_index)
			}
			mesh_index += 1
		}
	}

	// extract materials
	for &gltf_material, i in model_data.materials {
		model_material := &m.materials[i]
		model_material.color_tint = {1, 1, 1, 1} // default white

		if metallic_roughness, has_mr := gltf_material.metallic_roughness.?; has_mr {
			model_material.color_tint = metallic_roughness.base_color_factor
			model_material.metallic_factor = metallic_roughness.metallic_factor
			model_material.roughness_factor = metallic_roughness.roughness_factor

			// base color texture
			if texture_info, has_texture := metallic_roughness.base_color_texture.?; has_texture {
				texture := model_data.textures[texture_info.index]
				if image_index, has_image := texture.source.?; has_image {
					image := model_data.images[image_index]
					if image.uri != nil {
						switch uri_data in image.uri {
						case string:
							// external file reference
							// todo - resolve relative to glTF file path
							model_material.base_color_texture = load_texture(uri_data)
						case []byte:
							// embedded texture (GLB) - decode and upload
							model_material.base_color_texture = load_texture(uri_data)
						}
					} else if buffer_view_index, has_buffer_view := image.buffer_view.?; has_buffer_view {
						buffer_view := model_data.buffer_views[buffer_view_index]
						buf: []byte
						switch v in model_data.buffers[buffer_view.buffer].uri {
						case string:
							panic("external buffer not supported for model textures")
						case []byte:
							// embedded texture (GLB) - decode and upload
							buf = v[buffer_view.byte_offset:][:buffer_view.byte_length]
						}
						assert(len(buf) > 0, "did not expect an empty buffer")
						model_material.base_color_texture = load_texture(buf)
					}
				}
			}
		}
	}

	// If model had no materials, create a default white one
	if len(model_data.materials) == 0 {
		m.materials[0] = Model_Material {
			color_tint = {1, 1, 1, 1},
		}
	}

	log.infof("loaded %s successfully", model_file_name)
	return m, true
}

// todo(hector) - this is a get aroundt he fact that gltf2.odin does not support
//  strides... should probably upstream this at some point?

// Read accessor data from glTF buffer, handling byte_stride.
// Returns a slice of T allocated on the current allocator.
@(private = "file")
read_gltf2_accessor :: proc($T: typeid, data: ^gltf.Data, accessor_index: gltf.Integer) -> []T {
	accessor := data.accessors[accessor_index]
	assert(accessor.buffer_view != nil, "buf_iter_make: selected accessor doesn't have buffer_view")

	buf: []byte
	accessor_buffer_view := data.buffer_views[accessor.buffer_view.?]
	switch v in data.buffers[accessor_buffer_view.buffer].uri {
	case []byte:
		buf = v
	case string:
		panic("External buffer URIs not supported")
	}

	start := accessor.byte_offset + accessor_buffer_view.byte_offset
	count := int(accessor.count)
	stride := int(accessor_buffer_view.byte_stride.? or_else size_of(T))

	result := make([]T, count)
	for i in 0 ..< count {
		offset := int(start) + (i * stride)
		result[i] = (^T)(&buf[offset])^
	}
	return result
}

