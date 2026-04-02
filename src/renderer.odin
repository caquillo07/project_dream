package main

import "core:bytes"
import "core:c"
import "core:fmt"
import "core:image/png"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import sdl "vendor:sdl3"

Pipeline_Kind :: enum {
	Mesh,
	Sprite,
	DebugLines,
	DebugTriangles,
}

Render_State :: struct {
	pixel_width:            u32,
	pixel_height:           u32,
	device:                 ^sdl.GPUDevice,
	window:                 ^sdl.Window,
	pipelines:              [Pipeline_Kind]^sdl.GPUGraphicsPipeline,
	depth_texture:          ^sdl.GPUTexture,
	nearest_repeat_sampler: ^sdl.GPUSampler, // NEAREST+REPEAT (meshes)
	nearest_clamp_sampler:  ^sdl.GPUSampler, // NEAREST+CLAMP (sprites)
	swapchain_format:       sdl.GPUTextureFormat,
}

Texture :: struct {
	sdl_texture: ^sdl.GPUTexture,
	width:       u32,
	height:      u32,
}

init_renderer :: proc() {
	// Create window
	platform.renderer.window = sdl.CreateWindow("Project Dream", WINDOW_WIDTH, WINDOW_HEIGHT, {.RESIZABLE})
	if platform.renderer.window == nil {
		log_sdl_fatal("Failed to create window")
	}

	// Init ShaderCross — runtime SPIR-V transpilation to native GPU format
	if !ShaderCross_Init() {
		log.fatalf("Failed to init ShaderCross: %s", sdl.GetError())
		panic("ShaderCross init failed")
	}

	shader_formats := ShaderCross_GetSPIRVShaderFormats()
	log.infof("ShaderCross supported formats: %v", shader_formats)

	platform.renderer.device = sdl.CreateGPUDevice(shader_formats, ODIN_DEBUG, nil)
	if platform.renderer.device == nil {
		log_sdl_fatal("Failed to create GPU device")
	}

	// Claim window for GPU rendering
	if !sdl.ClaimWindowForGPUDevice(platform.renderer.device, platform.renderer.window) {
		log_sdl_fatal("Failed to claim window")
	}
	// Get actual pixel dimensions (may differ from logical on HiDPI/Retina)
	pixel_w, pixel_h: c.int
	assert(sdl.GetWindowSizeInPixels(platform.renderer.window, &pixel_w, &pixel_h))
	log.infof("Window: %dx%d logical, %dx%d pixels", WINDOW_WIDTH, WINDOW_HEIGHT, pixel_w, pixel_h)

	platform.renderer.pixel_height = u32(pixel_h)
	platform.renderer.pixel_width = u32(pixel_w)

	// VSync on by default
	// todo when we are saving settings, make sure to make this load that state
	assert(sdl.SetGPUSwapchainParameters(platform.renderer.device, platform.renderer.window, .SDR, .VSYNC))

	platform.renderer.swapchain_format = sdl.GetGPUSwapchainTextureFormat(
		platform.renderer.device,
		platform.renderer.window,
	)
	log.infof("using swapchain format: %v", platform.renderer.swapchain_format)

	// Depth buffer
	platform.renderer.depth_texture = sdl.CreateGPUTexture(
		platform.renderer.device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .D32_FLOAT,
			width = u32(platform.renderer.pixel_width),
			height = u32(platform.renderer.pixel_height),
			layer_count_or_depth = 1,
			num_levels = 1,
			usage = {.DEPTH_STENCIL_TARGET},
		},
	)
	if platform.renderer.depth_texture == nil {
		log_sdl_fatal("Failed to create depth texture")
	}

	platform.renderer.nearest_repeat_sampler = sdl.CreateGPUSampler(
		platform.renderer.device,
		sdl.GPUSamplerCreateInfo {
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			address_mode_u = .REPEAT,
			address_mode_v = .REPEAT,
		},
	)
	if platform.renderer.nearest_repeat_sampler == nil {
		log_sdl_fatal("Failed to create sampler")
	}

	platform.renderer.nearest_clamp_sampler = sdl.CreateGPUSampler(
		platform.renderer.device,
		sdl.GPUSamplerCreateInfo {
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
		},
	)
	if platform.renderer.nearest_clamp_sampler == nil {
		log_sdl_fatal("Failed to create sprite sampler")
	}

	// Pipelines

	// Load shaders (into scratch — bytes only needed until ShaderCross compiles them)
	shader_count: int
	shader_start := sdl.GetPerformanceCounter()

	// Create mesh pipeline
	mesh_vert_shader := load_shader("build/shaders/mesh.vert.spv", .VERTEX, 1, 0)
	defer sdl.ReleaseGPUShader(platform.renderer.device, mesh_vert_shader)
	shader_count += 1
	mesh_frag_shader := load_shader("build/shaders/mesh.frag.spv", .FRAGMENT, 0, 1)
	defer sdl.ReleaseGPUShader(platform.renderer.device, mesh_frag_shader)
	shader_count += 1

	platform.renderer.pipelines[.Mesh] = create_mesh_pipeline(mesh_vert_shader, mesh_frag_shader)

	// Sprite pipeline
	sprite_vert_shader := load_shader("build/shaders/sprite.vert.spv", .VERTEX, 1, 0)
	defer sdl.ReleaseGPUShader(platform.renderer.device, sprite_vert_shader)
	shader_count += 1
	sprite_frag_shader := load_shader("build/shaders/sprite.frag.spv", .FRAGMENT, 0, 1)
	defer sdl.ReleaseGPUShader(platform.renderer.device, sprite_frag_shader)
	shader_count += 1

	platform.renderer.pipelines[.Sprite] = create_sprite_pipeline(sprite_vert_shader, sprite_frag_shader)

	// Debug lines pipeline
	debug_line_vert_shader := load_shader("build/shaders/debug_line.vert.spv", .VERTEX, 1, 0)
	defer sdl.ReleaseGPUShader(platform.renderer.device, debug_line_vert_shader)
	shader_count += 1
	debug_line_frag_shader := load_shader("build/shaders/debug_line.frag.spv", .FRAGMENT, 0, 0)
	defer sdl.ReleaseGPUShader(platform.renderer.device, debug_line_frag_shader)
	shader_count += 1

	platform.renderer.pipelines[.DebugLines] = create_debug_line_pipeline(debug_line_vert_shader, debug_line_frag_shader)
	platform.renderer.pipelines[.DebugTriangles] = create_debug_triangle_pipeline(debug_line_vert_shader, debug_line_frag_shader)

	// Report shader compilation time
	shader_elapsed := elapsed_ms(shader_start)
	log.infof("Shader compilation: %.2fms (%d shaders)", shader_elapsed, shader_count)
}

deinit_renderer :: proc() {
	// destroy pipelines
	for pipeline in platform.renderer.pipelines {
		sdl.ReleaseGPUGraphicsPipeline(platform.renderer.device, pipeline)
	}

	sdl.ReleaseGPUSampler(platform.renderer.device, platform.renderer.nearest_clamp_sampler)
	sdl.ReleaseGPUSampler(platform.renderer.device, platform.renderer.nearest_repeat_sampler)
	sdl.ReleaseGPUTexture(platform.renderer.device, platform.renderer.depth_texture)
	sdl.DestroyGPUDevice(platform.renderer.device)
	sdl.DestroyWindow(platform.renderer.window)
	ShaderCross_Quit()
}

renderer_resize_viewport :: proc(width, height: u32) {
	sdl.ReleaseGPUTexture(platform.renderer.device, platform.renderer.depth_texture)
	platform.renderer.depth_texture = sdl.CreateGPUTexture(
		platform.renderer.device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .D32_FLOAT,
			width = width,
			height = height,
			layer_count_or_depth = 1,
			num_levels = 1,
			usage = {.DEPTH_STENCIL_TARGET},
		},
	)
	platform.renderer.pixel_height = height
	platform.renderer.pixel_width = width
	if platform.renderer.depth_texture == nil {
		log_sdl_fatal("Failed to recreate depth texture on resize")
	}
}

renderer_enable_vsync :: proc(enable: bool) {
	if !sdl.SetGPUSwapchainParameters(
		platform.renderer.device,
		platform.renderer.window,
		.SDR,
		enable ? .VSYNC : .IMMEDIATE,
	) {
		state := enable ? "enable" : "disable"
		log_sdl_warn(fmt.tprintf("failed to %s vsync", state))
	}
}

renderer_begin_frame :: proc() -> (^sdl.GPUCommandBuffer, ^sdl.GPURenderPass, bool) {
	// Acquire command buffer
	cmd := sdl.AcquireGPUCommandBuffer(platform.renderer.device)
	if cmd == nil {
		log_sdl_error("Failed to acquire GPU command buffer")
		return nil, nil, false
	}

	// Acquire swapchain texture
	swapchain_tex: ^sdl.GPUTexture
	if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd, platform.renderer.window, &swapchain_tex, nil, nil) {
		log_sdl_error("Failed to acquire GPU swapchain texture")
		_ = sdl.SubmitGPUCommandBuffer(cmd)
		return nil, nil, false
	}
	if swapchain_tex == nil {
		// Window minimized or not visible — submit empty command buffer
		_ = sdl.SubmitGPUCommandBuffer(cmd)
		return nil, nil, false
	}

	// Begin render pass — clear to dark gray, clear depth to 1.0
	color_target := sdl.GPUColorTargetInfo {
		texture     = swapchain_tex,
		load_op     = .CLEAR,
		store_op    = .STORE,
		clear_color = {0.1, 0.1, 0.1, 1.0},
	}
	depth_target := sdl.GPUDepthStencilTargetInfo {
		texture     = platform.renderer.depth_texture,
		load_op     = .CLEAR,
		store_op    = .STORE,
		clear_depth = 1.0,
	}
	render_pass := sdl.BeginGPURenderPass(cmd, &color_target, 1, &depth_target)
	return cmd, render_pass, true
}

renderer_end_frame :: proc(cmd: ^sdl.GPUCommandBuffer, render_pass: ^sdl.GPURenderPass) {
	sdl.EndGPURenderPass(render_pass)

	// Submit
	if !sdl.SubmitGPUCommandBuffer(cmd) {
		log_sdl_error("Failed to submit GPU command buffer")
	}
}

load_shader :: proc(
	spv_path: string,
	stage: sdl.GPUShaderStage,
	num_uniform_buffers: u32,
	num_samplers: u32,
	allocator: mem.Allocator = context.temp_allocator,
) -> ^sdl.GPUShader {
	code, read_err := os.read_entire_file(spv_path, allocator)
	if read_err != nil {
		log.fatalf("Failed to load shader: %s", spv_path)
		panic("shader load failed")
	}

	sc_stage: ShaderCross_ShaderStage = stage == .VERTEX ? .VERTEX : .FRAGMENT

	shader := ShaderCross_CompileGraphicsShaderFromSPIRV(
		platform.renderer.device,
		&ShaderCross_SPIRV_Info {
			bytecode = raw_data(code),
			bytecode_size = c.size_t(len(code)),
			entrypoint = "main",
			shader_stage = sc_stage,
		},
		&ShaderCross_GraphicsShaderResourceInfo {
			num_samplers = num_samplers,
			num_uniform_buffers = num_uniform_buffers,
		},
		0,
	)

	if shader == nil {
		log.fatalf("Failed to compile shader: %s: %s", spv_path, sdl.GetError())
		panic("shader compilation failed")
	}
	return shader
}

load_texture :: proc {
	load_texture_from_file,
	load_texture_from_pixels,
}

load_texture_from_file :: proc(path: string) -> Texture {
	img, err := png.load(path, {.alpha_add_if_missing}, context.temp_allocator)
	defer png.destroy(img)
	if err != nil {
		log.errorf("failed to load texture from image %s: %v", path, err)
		panic("texture load failed")
	}

	log.infof("Loading texture: %s", path)
	return load_texture_from_pixels(u32(img.width), u32(img.height), bytes.buffer_to_bytes(&img.pixels))
}

load_texture_from_pixels :: proc(tex_width, tex_height: u32, pixels_buf: []byte) -> Texture {
	sdl_texture := sdl.CreateGPUTexture(
		platform.renderer.device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .R8G8B8A8_UNORM,
			width = tex_width,
			height = tex_height,
			layer_count_or_depth = 1,
			num_levels = 1,
			usage = {.SAMPLER},
		},
	)
	if sdl_texture == nil {
		log_sdl_fatal("Failed to create texture")
	}

	tex_transfer := sdl.CreateGPUTransferBuffer(
		platform.renderer.device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = u32(len(pixels_buf))},
	)
	transfer_buf_ptr := sdl.MapGPUTransferBuffer(platform.renderer.device, tex_transfer, false)
	mem.copy(transfer_buf_ptr, raw_data(pixels_buf), len(pixels_buf))
	sdl.UnmapGPUTransferBuffer(platform.renderer.device, tex_transfer)

	tex_upload_cmd := sdl.AcquireGPUCommandBuffer(platform.renderer.device)
	tex_copy_pass := sdl.BeginGPUCopyPass(tex_upload_cmd)
	sdl.UploadToGPUTexture(
		tex_copy_pass,
		sdl.GPUTextureTransferInfo {
			transfer_buffer = tex_transfer,
			pixels_per_row = u32(tex_width),
			rows_per_layer = u32(tex_height),
		},
		sdl.GPUTextureRegion{texture = sdl_texture, w = u32(tex_width), h = u32(tex_height), d = 1},
		false,
	)
	sdl.EndGPUCopyPass(tex_copy_pass)
	assert(sdl.SubmitGPUCommandBuffer(tex_upload_cmd), "failed to upload texture cmd buffer")
	sdl.ReleaseGPUTransferBuffer(platform.renderer.device, tex_transfer)

	log.infof("Loaded texture: %dx%d", tex_width, tex_height)
	return {sdl_texture = sdl_texture, height = tex_height, width = tex_width}
}

unload_texture :: proc(t: Texture) {
	sdl.ReleaseGPUTexture(platform.renderer.device, t.sdl_texture)
}

renderer_pipeline :: proc(kind: Pipeline_Kind) -> ^sdl.GPUGraphicsPipeline {
	return platform.renderer.pipelines[kind]
}

renderer_upload_vertex_buffer :: proc(data: []$T) -> ^sdl.GPUBuffer {
	data_size := u32(len(data) * size_of(T))
	vertex_buffer := sdl.CreateGPUBuffer(
		platform.renderer.device,
		sdl.GPUBufferCreateInfo{usage = {.VERTEX}, size = data_size},
	)
	if vertex_buffer == nil {
		log_sdl_fatal("Failed to create vertex buffer")
	}

	// Upload to GPU with a copy pass
	vert_transfer := sdl.CreateGPUTransferBuffer(
		platform.renderer.device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = data_size},
	)
	vert_ptr := sdl.MapGPUTransferBuffer(platform.renderer.device, vert_transfer, false)
	mem.copy(vert_ptr, raw_data(data), int(data_size))
	sdl.UnmapGPUTransferBuffer(platform.renderer.device, vert_transfer)

	upload_cmd := sdl.AcquireGPUCommandBuffer(platform.renderer.device)
	copy_pass := sdl.BeginGPUCopyPass(upload_cmd)
	sdl.UploadToGPUBuffer(
		copy_pass,
		sdl.GPUTransferBufferLocation{transfer_buffer = vert_transfer, offset = 0},
		sdl.GPUBufferRegion{buffer = vertex_buffer, offset = 0, size = data_size},
		false,
	)
	sdl.EndGPUCopyPass(copy_pass)
	assert(sdl.SubmitGPUCommandBuffer(upload_cmd), "failed to submit vertex buffer upload command")
	sdl.ReleaseGPUTransferBuffer(platform.renderer.device, vert_transfer)

	return vertex_buffer
}

renderer_release_vertex_buffer :: proc(buf: ^sdl.GPUBuffer) {
	sdl.ReleaseGPUBuffer(platform.renderer.device, buf)
}

@(private = "file")
create_mesh_pipeline :: proc(vertex_shader, fragment_shader: ^sdl.GPUShader) -> ^sdl.GPUGraphicsPipeline {
	vert_buf_descs := [?]sdl.GPUVertexBufferDescription{{slot = 0, pitch = size_of(Mesh_Vertex), input_rate = .VERTEX}}
	vert_attrs := [?]sdl.GPUVertexAttribute {
		{location = 0, buffer_slot = 0, format = .FLOAT3, offset = u32(offset_of(Mesh_Vertex, position))},
		{location = 1, buffer_slot = 0, format = .FLOAT2, offset = u32(offset_of(Mesh_Vertex, uv))},
		{location = 2, buffer_slot = 0, format = .FLOAT3, offset = u32(offset_of(Mesh_Vertex, normal))},
	}
	color_target_descs := [?]sdl.GPUColorTargetDescription{{format = platform.renderer.swapchain_format}}

	pipeline := sdl.CreateGPUGraphicsPipeline(
		platform.renderer.device,
		sdl.GPUGraphicsPipelineCreateInfo {
			vertex_shader = vertex_shader,
			fragment_shader = fragment_shader,
			vertex_input_state = {
				vertex_buffer_descriptions = raw_data(&vert_buf_descs),
				num_vertex_buffers = len(vert_buf_descs),
				vertex_attributes = raw_data(&vert_attrs),
				num_vertex_attributes = len(vert_attrs),
			},
			primitive_type = .TRIANGLELIST,
			rasterizer_state = {fill_mode = .FILL, cull_mode = .BACK, front_face = .COUNTER_CLOCKWISE},
			depth_stencil_state = {compare_op = .LESS_OR_EQUAL, enable_depth_test = true, enable_depth_write = true},
			target_info = {
				color_target_descriptions = raw_data(&color_target_descs),
				num_color_targets = len(color_target_descs),
				depth_stencil_format = .D32_FLOAT,
				has_depth_stencil_target = true,
			},
		},
	)
	if pipeline == nil {
		log_sdl_fatal("Failed to create graphics pipeline")
	}

	return pipeline
}

@(private = "file")
create_sprite_pipeline :: proc(vert_shader, frag_shader: ^sdl.GPUShader) -> ^sdl.GPUGraphicsPipeline {
	color_target_descs := [?]sdl.GPUColorTargetDescription{{format = platform.renderer.swapchain_format}}
	sprite_pipeline := sdl.CreateGPUGraphicsPipeline(
		platform.renderer.device,
		sdl.GPUGraphicsPipelineCreateInfo {
			vertex_shader = vert_shader,
			fragment_shader = frag_shader,
			primitive_type = .TRIANGLESTRIP,
			rasterizer_state = {fill_mode = .FILL, cull_mode = .NONE},
			depth_stencil_state = {compare_op = .LESS_OR_EQUAL, enable_depth_test = true, enable_depth_write = true},
			target_info = {
				color_target_descriptions = raw_data(&color_target_descs),
				num_color_targets = len(color_target_descs),
				depth_stencil_format = .D32_FLOAT,
				has_depth_stencil_target = true,
			},
		},
	)
	if sprite_pipeline == nil {
		log_sdl_fatal("Failed to create sprite pipeline")
	}

	return sprite_pipeline
}

@(private = "file")
create_debug_line_pipeline :: proc(vert_shader, frag_shader: ^sdl.GPUShader) -> ^sdl.GPUGraphicsPipeline {
	vert_buf_descs := [?]sdl.GPUVertexBufferDescription {
		{slot = 0, pitch = size_of(Debug_Line_Vertex), input_rate = .VERTEX},
	}
	vert_attrs := [?]sdl.GPUVertexAttribute {
		{location = 0, buffer_slot = 0, format = .FLOAT3, offset = u32(offset_of(Debug_Line_Vertex, position))},
		{location = 1, buffer_slot = 0, format = .FLOAT4, offset = u32(offset_of(Debug_Line_Vertex, color))},
	}
	color_target_descs := [?]sdl.GPUColorTargetDescription{{format = platform.renderer.swapchain_format}}

	pipeline := sdl.CreateGPUGraphicsPipeline(
		platform.renderer.device,
		sdl.GPUGraphicsPipelineCreateInfo {
			vertex_shader = vert_shader,
			fragment_shader = frag_shader,
			vertex_input_state = {
				vertex_buffer_descriptions = raw_data(&vert_buf_descs),
				num_vertex_buffers = len(vert_buf_descs),
				vertex_attributes = raw_data(&vert_attrs),
				num_vertex_attributes = len(vert_attrs),
			},
			primitive_type = .LINELIST,
			rasterizer_state = {fill_mode = .FILL, cull_mode = .NONE},
			depth_stencil_state = {compare_op = .LESS_OR_EQUAL, enable_depth_test = true, enable_depth_write = true},
			target_info = {
				color_target_descriptions = raw_data(&color_target_descs),
				num_color_targets = len(color_target_descs),
				depth_stencil_format = .D32_FLOAT,
				has_depth_stencil_target = true,
			},
		},
	)
	if pipeline == nil {
		log_sdl_fatal("Failed to create debug line pipeline")
	}
	return pipeline
}

@(private = "file")
create_debug_triangle_pipeline :: proc(vert_shader, frag_shader: ^sdl.GPUShader) -> ^sdl.GPUGraphicsPipeline {
	vert_buf_descs := [?]sdl.GPUVertexBufferDescription {
		{slot = 0, pitch = size_of(Debug_Line_Vertex), input_rate = .VERTEX},
	}
	vert_attrs := [?]sdl.GPUVertexAttribute {
		{location = 0, buffer_slot = 0, format = .FLOAT3, offset = u32(offset_of(Debug_Line_Vertex, position))},
		{location = 1, buffer_slot = 0, format = .FLOAT4, offset = u32(offset_of(Debug_Line_Vertex, color))},
	}
	color_target_descs := [?]sdl.GPUColorTargetDescription {
		{
			format = platform.renderer.swapchain_format,
			blend_state = {
				enable_blend = true,
				src_color_blendfactor = .SRC_ALPHA,
				dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
				color_blend_op = .ADD,
				src_alpha_blendfactor = .ONE,
				dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
				alpha_blend_op = .ADD,
			},
		},
	}

	pipeline := sdl.CreateGPUGraphicsPipeline(
		platform.renderer.device,
		sdl.GPUGraphicsPipelineCreateInfo {
			vertex_shader = vert_shader,
			fragment_shader = frag_shader,
			vertex_input_state = {
				vertex_buffer_descriptions = raw_data(&vert_buf_descs),
				num_vertex_buffers = len(vert_buf_descs),
				vertex_attributes = raw_data(&vert_attrs),
				num_vertex_attributes = len(vert_attrs),
			},
			primitive_type = .TRIANGLELIST,
			rasterizer_state = {fill_mode = .FILL, cull_mode = .NONE},
			depth_stencil_state = {compare_op = .LESS_OR_EQUAL, enable_depth_test = true, enable_depth_write = false},
			target_info = {
				color_target_descriptions = raw_data(&color_target_descs),
				num_color_targets = len(color_target_descs),
				depth_stencil_format = .D32_FLOAT,
				has_depth_stencil_target = true,
			},
		},
	)
	if pipeline == nil {
		log_sdl_fatal("Failed to create debug triangle pipeline")
	}
	return pipeline
}

