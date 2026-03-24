package main

import "base:intrinsics"
import "core:c"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import vmem "core:mem/virtual"
import sdl "vendor:sdl3"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

Button_State :: struct {
	is_down:  bool, // held down right now
	pressed:  bool, // went down this frame
	released: bool, // went up this frame
}

Debug_Timing :: struct {
	dt:       f32, // seconds
	fps:      f32,
	frame_ms: f32,
}

renderer: Render_State

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	// Init SDL
	if !sdl.Init({.VIDEO}) {
		log_sdl_fatal("Failed to init SDL")
	}
	defer sdl.Quit()

	init_renderer()
	defer deinit_renderer()

	// Game memory — growable virtual memory arenas
	// Initial block sizes are our best guess. If they grow, we log it so we can tune.
	permanent_arena: vmem.Arena
	if vmem.arena_init_growing(&permanent_arena, 64 * mem.Megabyte) != nil {
		panic("Failed to init permanent arena")
	}
	permanent_allocator := vmem.arena_allocator(&permanent_arena)
	context.allocator = permanent_allocator

	scratch_arena: vmem.Arena
	if vmem.arena_init_growing(&scratch_arena, 16 * mem.Megabyte) != nil {
		panic("Failed to init scratch arena")
	}
	scratch_allocator := vmem.arena_allocator(&scratch_arena)

	// Own all temp memory — tprintf and friends go through our scratch arena
	context.temp_allocator = scratch_allocator

	// Track arena sizes so we can warn on growth and tune initial sizes
	permanent_reserved := permanent_arena.total_reserved
	scratch_reserved := scratch_arena.total_reserved
	log.infof("Permanent arena: %s reserved", format_bytes(permanent_reserved))
	log.infof("Scratch arena: %s reserved", format_bytes(scratch_reserved))

	// Load shaders (into scratch — bytes only needed until ShaderCross compiles them)
	shader_count: int
	shader_start := sdl.GetPerformanceCounter()

	vert_shader := load_shader(renderer, "build/shaders/mesh.vert.spv", .VERTEX, 1, 0, scratch_allocator)
	shader_count += 1
	frag_shader := load_shader(renderer, "build/shaders/mesh.frag.spv", .FRAGMENT, 0, 1, scratch_allocator)
	shader_count += 1

	// Create mesh pipeline
	vert_buf_descs := [?]sdl.GPUVertexBufferDescription{{slot = 0, pitch = size_of(Mesh_Vertex), input_rate = .VERTEX}}
	vert_attrs := [?]sdl.GPUVertexAttribute {
		{location = 0, buffer_slot = 0, format = .FLOAT3, offset = u32(offset_of(Mesh_Vertex, position))},
		{location = 1, buffer_slot = 0, format = .FLOAT2, offset = u32(offset_of(Mesh_Vertex, uv))},
		{location = 2, buffer_slot = 0, format = .FLOAT3, offset = u32(offset_of(Mesh_Vertex, normal))},
	}
	color_target_descs := [?]sdl.GPUColorTargetDescription{{format = renderer.swapchain_format}}

	pipeline := sdl.CreateGPUGraphicsPipeline(
		renderer.device,
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
	defer sdl.ReleaseGPUGraphicsPipeline(renderer.device, pipeline)

	sdl.ReleaseGPUShader(renderer.device, vert_shader)
	sdl.ReleaseGPUShader(renderer.device, frag_shader)

	// Procedural checkerboard texture
	CHECKER_SIZE :: 64
	TILE_SIZE :: 8
	checker_pixels: [CHECKER_SIZE * CHECKER_SIZE * 4]u8
	for y in 0 ..< CHECKER_SIZE {
		for x in 0 ..< CHECKER_SIZE {
			is_white := ((x / TILE_SIZE) + (y / TILE_SIZE)) % 2 == 0
			color: u8 = is_white ? 200 : 80
			i := (y * CHECKER_SIZE + x) * 4
			checker_pixels[i + 0] = color // R
			checker_pixels[i + 1] = color // G
			checker_pixels[i + 2] = color // B
			checker_pixels[i + 3] = 255 // A
		}
	}

	ground_texture := load_texture_from_pixels(
		CHECKER_SIZE,
		CHECKER_SIZE,
		raw_data(checker_pixels[:]),
		size_of(checker_pixels),
	)
	defer unload_texture(ground_texture)

	// Ground quad — 6 vertices on XZ plane at Y=0
	GROUND_HALF :: f32(10.0)
	UV_TILES :: f32(5.0) // how many times the checkerboard repeats
	ground_verts := [6]Mesh_Vertex {
		// Triangle 1 (CCW when viewed from above: +Y)
		{{-GROUND_HALF, 0, -GROUND_HALF}, {0, 0}, {0, 1, 0}},
		{{-GROUND_HALF, 0, GROUND_HALF}, {0, UV_TILES}, {0, 1, 0}},
		{{GROUND_HALF, 0, GROUND_HALF}, {UV_TILES, UV_TILES}, {0, 1, 0}},
		// Triangle 2
		{{-GROUND_HALF, 0, -GROUND_HALF}, {0, 0}, {0, 1, 0}},
		{{GROUND_HALF, 0, GROUND_HALF}, {UV_TILES, UV_TILES}, {0, 1, 0}},
		{{GROUND_HALF, 0, -GROUND_HALF}, {UV_TILES, 0}, {0, 1, 0}},
	}

	vertex_buffer := sdl.CreateGPUBuffer(
		renderer.device,
		sdl.GPUBufferCreateInfo{usage = {.VERTEX}, size = size_of(ground_verts)},
	)
	if vertex_buffer == nil {
		log_sdl_fatal("Failed to create vertex buffer")
	}
	defer sdl.ReleaseGPUBuffer(renderer.device, vertex_buffer)

	// Upload ground quad to GPU with a copy pass
	vert_transfer := sdl.CreateGPUTransferBuffer(
		renderer.device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = size_of(ground_verts)},
	)
	vert_ptr := sdl.MapGPUTransferBuffer(renderer.device, vert_transfer, false)
	mem.copy(vert_ptr, &ground_verts, size_of(ground_verts))
	sdl.UnmapGPUTransferBuffer(renderer.device, vert_transfer)

	upload_cmd := sdl.AcquireGPUCommandBuffer(renderer.device)
	copy_pass := sdl.BeginGPUCopyPass(upload_cmd)
	sdl.UploadToGPUBuffer(
		copy_pass,
		sdl.GPUTransferBufferLocation{transfer_buffer = vert_transfer, offset = 0},
		sdl.GPUBufferRegion{buffer = vertex_buffer, offset = 0, size = size_of(ground_verts)},
		false,
	)
	sdl.EndGPUCopyPass(copy_pass)
	assert(sdl.SubmitGPUCommandBuffer(upload_cmd), "failed to submit ground buffer and texture upload command")
	sdl.ReleaseGPUTransferBuffer(renderer.device, vert_transfer)

	// Sprite pipeline
	sprite_vert := load_shader(renderer, "build/shaders/sprite.vert.spv", .VERTEX, 1, 0, scratch_allocator)
	shader_count += 1
	sprite_frag := load_shader(renderer, "build/shaders/sprite.frag.spv", .FRAGMENT, 0, 1, scratch_allocator)
	shader_count += 1

	sprite_pipeline := sdl.CreateGPUGraphicsPipeline(
		renderer.device,
		sdl.GPUGraphicsPipelineCreateInfo {
			vertex_shader = sprite_vert,
			fragment_shader = sprite_frag,
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
	defer sdl.ReleaseGPUGraphicsPipeline(renderer.device, sprite_pipeline)

	sdl.ReleaseGPUShader(renderer.device, sprite_vert)
	sdl.ReleaseGPUShader(renderer.device, sprite_frag)

	sprite_texture := load_texture("assets/sprites/nate.png")
	defer unload_texture(sprite_texture)

	// Camera
	cam := Camera {
		target   = {0, 0, 0},
		distance = CameraDistDefault,
		pitch    = CameraPitch,
	}

	// Frame timing
	perf_freq := sdl.GetPerformanceFrequency()
	last_counter := sdl.GetPerformanceCounter()

	// Title bar timing display — sampled every 0.5s
	TITLE_UPDATE_INTERVAL :: 0.5
	title_accumulator: f32
	title_frame_count: i32
	title_ms_sum: f32
	title_ms_min: f32 = 999.0
	title_ms_max: f32

	// Report shader compilation time
	shader_elapsed := f32(sdl.GetPerformanceCounter() - shader_start) / f32(perf_freq) * 1000.0
	log.infof("Shader compilation: %.2fms (%d shaders)", shader_elapsed, shader_count)

	// Main loop
	running := true
	for running {
		// Measure frame time
		now := sdl.GetPerformanceCounter()
		game.input.dt = f32(now - last_counter) / f32(perf_freq)
		last_counter = now

		game.debug_timing.dt = game.input.dt
		game.debug_timing.frame_ms = game.input.dt * 1000.0
		game.debug_timing.fps = game.input.dt > 0 ? 1.0 / game.input.dt : 0

		// Accumulate timing samples, update title periodically
		title_accumulator += game.debug_timing.dt
		title_frame_count += 1
		title_ms_sum += game.debug_timing.frame_ms
		title_ms_min = min(title_ms_min, game.debug_timing.frame_ms)
		title_ms_max = max(title_ms_max, game.debug_timing.frame_ms)

		if title_accumulator >= TITLE_UPDATE_INTERVAL {
			avg_ms := title_ms_sum / f32(title_frame_count)
			sdl.SetWindowTitle(
				renderer.window,
				fmt.ctprintf(
					"Project Dream | %.1fms avg | %.1f / %.1f min/max | %.0f fps",
					avg_ms,
					title_ms_min,
					title_ms_max,
					1000.0 / avg_ms,
				),
			)
			title_accumulator = 0
			title_frame_count = 0
			title_ms_sum = 0
			title_ms_min = 999.0
			title_ms_max = 0
		}

		event: sdl.Event
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				running = false
			case .KEY_DOWN:
				#partial switch event.key.scancode {
				case .ESCAPE:
					running = false
				case .F1:
					if !game.debug_mode {
						// Enter debug mode — save follow camera, init debug camera at current eye position
						game.saved_cam = cam
						offset_y := cam.distance * math.sin(cam.pitch)
						offset_z := cam.distance * math.cos(cam.pitch)
						game.debug_cam = Debug_Camera {
							position = cam.target + {0, offset_y, offset_z},
							yaw      = 0,
							pitch    = -cam.pitch, // looking down at target
							speed    = DebugCamSpeedDefault,
						}
						game.debug_mode = true
						assert(
							sdl.SetWindowRelativeMouseMode(renderer.window, true),
							"failed to set relative mouse mode",
						)
						log.infof("Debug camera ON")
					} else {
						// Exit debug mode — restore follow camera
						cam = game.saved_cam
						game.debug_mode = false
						assert(
							sdl.SetWindowRelativeMouseMode(renderer.window, false),
							"failed to set relative mouse mode",
						)
						log.infof("Debug camera OFF")
					}
				case .V:
					if game.debug_mode {
						renderer.vsync = !renderer.vsync // todo - should live on platform?
						renderer_enable_vsync(renderer.vsync)
						log.infof("VSync: %s", renderer.vsync ? "ON" : "OFF")
					}
				}
			case .MOUSE_WHEEL:
				if game.debug_mode {
					// Scroll adjusts debug camera game.speed
					game.debug_cam.speed = clamp(
						game.debug_cam.speed + event.wheel.y * 2.0,
						DebugCamSpeedMin,
						DebugCamSpeedMax,
					)
				} else {
					// Scroll zooms follow camera
					cam.distance -= event.wheel.y * CameraZoomSpeed
					cam.distance = clamp(cam.distance, CameraDistMin, CameraDistMax)
				}
			case .MOUSE_MOTION:
				if game.debug_mode {
					game.debug_cam.yaw += event.motion.xrel * MouseSensitivity
					game.debug_cam.pitch -= event.motion.yrel * MouseSensitivity
					game.debug_cam.pitch = clamp(
						game.debug_cam.pitch,
						-85.0 * math.RAD_PER_DEG,
						85.0 * math.RAD_PER_DEG,
					)
				}
			case .WINDOW_PIXEL_SIZE_CHANGED:
				log.info("WINDOW_PIXEL_SIZE_CHANGED event fired")
				new_w := u32(event.window.data1)
				new_h := u32(event.window.data2)
				if new_w > 0 && new_h > 0 {
					renderer_resize_viewport(new_w, new_h)
				}
			}
		}

		// Gather input from keyboard state
		gather_input(&game.input)

		// Camera update
		view_proj: linalg.Matrix4f32
		cam_right: Vec3
		cam_up: Vec3
		if game.debug_mode {
			// Debug free camera — WASD movement along view vectors
			forward := Vec3 {
				math.sin(game.debug_cam.yaw) * math.cos(game.debug_cam.pitch),
				math.sin(game.debug_cam.pitch),
				-math.cos(game.debug_cam.yaw) * math.cos(game.debug_cam.pitch),
			}
			right := Vec3{math.cos(game.debug_cam.yaw), 0, math.sin(game.debug_cam.yaw)}
			move_speed := game.debug_cam.speed * game.input.dt

			if game.input.move_up.is_down do game.debug_cam.position += forward * move_speed
			if game.input.move_down.is_down do game.debug_cam.position -= forward * move_speed
			if game.input.move_right.is_down do game.debug_cam.position += right * move_speed
			if game.input.move_left.is_down do game.debug_cam.position -= right * move_speed

			// todo(hector) - move these to the input layer?
			keyboard := sdl.GetKeyboardState(nil)
			if keyboard[sdl.Scancode.E] do game.debug_cam.position.y += move_speed
			if keyboard[sdl.Scancode.Q] do game.debug_cam.position.y -= move_speed

			view := linalg.matrix4_look_at_f32(game.debug_cam.position, game.debug_cam.position + forward, {0, 1, 0})
			view_proj = renderer.proj * view
			cam_right = right
			cam_up = linalg.cross(right, forward)
		} else {
			// Follow camera — WASD pans target (temporary until player exists)
			if game.input.move_up.is_down do cam.target.z -= CameraPanSpeed * game.input.dt
			if game.input.move_down.is_down do cam.target.z += CameraPanSpeed * game.input.dt
			if game.input.move_left.is_down do cam.target.x -= CameraPanSpeed * game.input.dt
			if game.input.move_right.is_down do cam.target.x += CameraPanSpeed * game.input.dt

			offset_y := cam.distance * math.sin(cam.pitch)
			offset_z := cam.distance * math.cos(cam.pitch)
			eye := cam.target + {0, offset_y, offset_z}
			view := linalg.matrix4_look_at_f32(eye, cam.target, {0, 1, 0})
			view_proj = renderer.proj * view
			cam_right = {1, 0, 0}
			cam_forward := Vec3{0, -math.sin(cam.pitch), -math.cos(cam.pitch)}
			cam_up = linalg.cross(cam_right, cam_forward)
		}

		cmd, render_pass, ok := renderer_begin_frame()
		if !ok {
			log_sdl_warn("failed to begin frame")
			continue
		}

		// Draw ground plane
		sdl.BindGPUGraphicsPipeline(render_pass, pipeline)

		uniforms := Mesh_Uniforms {
			view_proj = view_proj,
			model     = 1, // identity
		}
		sdl.PushGPUVertexUniformData(cmd, 0, &uniforms, size_of(Mesh_Uniforms))

		tex_sampler_bindings := [?]sdl.GPUTextureSamplerBinding {
			{texture = ground_texture.sdl_texture, sampler = renderer.nearest_repeat_sampler},
		}
		sdl.BindGPUFragmentSamplers(render_pass, 0, raw_data(&tex_sampler_bindings), len(tex_sampler_bindings))

		vbuf_bindings := [?]sdl.GPUBufferBinding{{buffer = vertex_buffer, offset = 0}}
		sdl.BindGPUVertexBuffers(render_pass, 0, raw_data(&vbuf_bindings), len(vbuf_bindings))
		sdl.DrawGPUPrimitives(render_pass, 6, 1, 0, 0)

		// Draw sprite
		player := get_player()
		player.position = {0, 0, 0}
		sdl.BindGPUGraphicsPipeline(render_pass, sprite_pipeline)

		sprite_uniforms := Sprite_Uniforms {
			view_proj    = view_proj,
			camera_right = cam_right,
			camera_up    = cam_up,
			sprite_pos   = player.position,
			sprite_size  = {1.5, 1.5},
			atlas_size   = {f32(sprite_texture.width), f32(sprite_texture.height)},
			sprite_rect  = {0, 33, 33, 33}, // idle down frame
		}
		sdl.PushGPUVertexUniformData(cmd, 0, &sprite_uniforms, size_of(Sprite_Uniforms))

		sprite_sampler_bindings := [?]sdl.GPUTextureSamplerBinding {
			{texture = sprite_texture.sdl_texture, sampler = renderer.nearest_clamp_sampler},
		}
		sdl.BindGPUFragmentSamplers(render_pass, 0, raw_data(&sprite_sampler_bindings), len(sprite_sampler_bindings))

		sdl.DrawGPUPrimitives(render_pass, 4, 1, 0, 0)

		renderer_end_frame(cmd, render_pass)

		// Check for arena growth — means our initial sizes were too small
		if permanent_arena.total_reserved != permanent_reserved {
			log.warnf(
				"Permanent arena grew: %s -> %s",
				format_bytes(permanent_reserved),
				format_bytes(permanent_arena.total_reserved),
			)
			permanent_reserved = permanent_arena.total_reserved
		}
		if scratch_arena.total_reserved != scratch_reserved {
			log.warnf(
				"Scratch arena grew: %s -> %s",
				format_bytes(scratch_reserved),
				format_bytes(scratch_arena.total_reserved),
			)
			scratch_reserved = scratch_arena.total_reserved
		}

		// Wipe scratch — everything allocated this frame is gone
		free_all(scratch_allocator)
	}
}

update_button :: proc(button: ^Button_State, is_down: bool) {
	was_down := button.is_down
	button.is_down = is_down
	button.pressed = is_down && !was_down
	button.released = !is_down && was_down
}

gather_input :: proc(input: ^Game_Input) {
	keyboard := sdl.GetKeyboardState(nil)

	update_button(&input.move_up, keyboard[sdl.Scancode.W])
	update_button(&input.move_down, keyboard[sdl.Scancode.S])
	update_button(&input.move_left, keyboard[sdl.Scancode.A])
	update_button(&input.move_right, keyboard[sdl.Scancode.D])
	update_button(&input.action_a, keyboard[sdl.Scancode.SPACE])
	update_button(&input.action_b, keyboard[sdl.Scancode.E]) // TODO: conflicts with debug camera fly-up (E/Q) — resolve when game actions are wired
}

format_bytes :: proc(bytes: uint) -> string {
	GB :: 1024 * 1024 * 1024
	MB :: 1024 * 1024
	KB :: 1024
	if bytes >= GB {
		return fmt.tprintf("%.2f GB", f64(bytes) / f64(GB))
	} else if bytes >= MB {
		return fmt.tprintf("%.2f MB", f64(bytes) / f64(MB))
	} else if bytes >= KB {
		return fmt.tprintf("%.2f KB", f64(bytes) / f64(KB))
	}
	return fmt.tprintf("%v B", bytes)
}

log_sdl_warn :: proc(msg: string, location := #caller_location) {
	log.warnf("%s: %s", msg, sdl.GetError(), location = location)
}

log_sdl_error :: proc(msg: string, location := #caller_location) {
	log.errorf("%s: %s", msg, sdl.GetError(), location = location)
}

log_sdl_fatal :: proc(msg: string, location := #caller_location) -> ! {
	log.fatalf("%s: %s", msg, sdl.GetError(), location = location)
	when ODIN_DEBUG {
		intrinsics.debug_trap()
	}
	panic("fatal error encountered", loc = location)
}
