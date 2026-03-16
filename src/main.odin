package main

import "base:intrinsics"
import "core:c"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import vmem "core:mem/virtual"
import "core:os"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

Vec4 :: [4]f32
Vec3 :: [3]f32
Vec2 :: [2]f32

Mesh_Vertex :: struct {
	position: Vec3,
	uv:       Vec2,
	normal:   Vec3,
}

Mesh_Uniforms :: struct {
	view_proj: matrix[4, 4]f32,
	model:     matrix[4, 4]f32,
}

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

Button_State :: struct {
	is_down:  bool, // held down right now
	pressed:  bool, // went down this frame
	released: bool, // went up this frame
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

Debug_Timing :: struct {
	dt:       f32, // seconds
	fps:      f32,
	frame_ms: f32,
}

// Follow camera — fixed angle, follows target, scroll-wheel zoom (HGSS / Link's Awakening style)
Camera :: struct {
	target:   Vec3,
	distance: f32,
	pitch:    f32, // fixed angle from horizontal (radians)
}

CAMERA_PITCH :: 50.0 * math.RAD_PER_DEG
CAMERA_DIST_MIN :: f32(5.0)
CAMERA_DIST_MAX :: f32(30.0)
CAMERA_DIST_DEFAULT :: f32(8.0)
CAMERA_ZOOM_SPEED :: f32(1.5)
CAMERA_PAN_SPEED :: f32(8.0) // temporary WASD panning until player exists

// Debug free camera — F1 toggle, FPS-style controls
Debug_Camera :: struct {
	position: Vec3,
	yaw:      f32,
	pitch:    f32,
	speed:    f32,
}

DEBUG_CAM_SPEED_DEFAULT :: f32(10.0)
DEBUG_CAM_SPEED_MIN :: f32(1.0)
DEBUG_CAM_SPEED_MAX :: f32(50.0)
MOUSE_SENSITIVITY :: f32(0.003)

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	// Init SDL
	if !sdl.Init({.VIDEO}) {
		log_sdl_fatal("Failed to init SDL")
	}
	defer sdl.Quit()

	// Create window
	window := sdl.CreateWindow("Project Dream", WINDOW_WIDTH, WINDOW_HEIGHT, {.RESIZABLE})
	if window == nil {
		log_sdl_fatal("Failed to create window")
	}
	defer sdl.DestroyWindow(window)

	device := sdl.CreateGPUDevice({.METALLIB}, ODIN_DEBUG, nil)
	if device == nil {
		log_sdl_fatal("Failed to create GPU device")
	}
	defer sdl.DestroyGPUDevice(device)

	// Claim window for GPU rendering
	if !sdl.ClaimWindowForGPUDevice(device, window) {
		log_sdl_fatal("Failed to claim window")
	}

	// Get actual pixel dimensions (may differ from logical on HiDPI/Retina)
	pixel_w, pixel_h: c.int
	assert(sdl.GetWindowSizeInPixels(window, &pixel_w, &pixel_h))
	log.infof("Window: %dx%d logical, %dx%d pixels", WINDOW_WIDTH, WINDOW_HEIGHT, pixel_w, pixel_h)

	// VSync on by default
	vsync := true
	assert(sdl.SetGPUSwapchainParameters(device, window, .SDR, .VSYNC))

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

	// Load shaders (into scratch — bytes only needed until CreateGPUShader copies them)
	swapchain_format := sdl.GetGPUSwapchainTextureFormat(device, window)
	log.infof("using swapchain format: %v", swapchain_format)

	vert_shader := load_shader(device, "build/shaders/mesh.vert.metallib", .VERTEX, 1, 0, scratch_allocator)
	frag_shader := load_shader(device, "build/shaders/mesh.frag.metallib", .FRAGMENT, 0, 1, scratch_allocator)

	// Create mesh pipeline
	vert_buf_descs := [?]sdl.GPUVertexBufferDescription{{slot = 0, pitch = size_of(Mesh_Vertex), input_rate = .VERTEX}}
	vert_attrs := [?]sdl.GPUVertexAttribute {
		{location = 0, buffer_slot = 0, format = .FLOAT3, offset = u32(offset_of(Mesh_Vertex, position))},
		{location = 1, buffer_slot = 0, format = .FLOAT2, offset = u32(offset_of(Mesh_Vertex, uv))},
		{location = 2, buffer_slot = 0, format = .FLOAT3, offset = u32(offset_of(Mesh_Vertex, normal))},
	}
	color_target_descs := [?]sdl.GPUColorTargetDescription{{format = swapchain_format}}

	pipeline := sdl.CreateGPUGraphicsPipeline(
		device,
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
	defer sdl.ReleaseGPUGraphicsPipeline(device, pipeline)

	sdl.ReleaseGPUShader(device, vert_shader)
	sdl.ReleaseGPUShader(device, frag_shader)

	// Depth buffer
	depth_texture := sdl.CreateGPUTexture(
		device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .D32_FLOAT,
			width = u32(pixel_w),
			height = u32(pixel_h),
			layer_count_or_depth = 1,
			num_levels = 1,
			usage = {.DEPTH_STENCIL_TARGET},
		},
	)
	if depth_texture == nil {
		log_sdl_fatal("Failed to create depth texture")
	}
	defer sdl.ReleaseGPUTexture(device, depth_texture)

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

	ground_texture := sdl.CreateGPUTexture(
		device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .R8G8B8A8_UNORM,
			width = CHECKER_SIZE,
			height = CHECKER_SIZE,
			layer_count_or_depth = 1,
			num_levels = 1,
			usage = {.SAMPLER},
		},
	)
	if ground_texture == nil {
		log_sdl_fatal("Failed to create ground texture")
	}
	defer sdl.ReleaseGPUTexture(device, ground_texture)

	sampler := sdl.CreateGPUSampler(
		device,
		sdl.GPUSamplerCreateInfo {
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			address_mode_u = .REPEAT,
			address_mode_v = .REPEAT,
		},
	)
	if sampler == nil {
		log_sdl_fatal("Failed to create sampler")
	}
	defer sdl.ReleaseGPUSampler(device, sampler)

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
		device,
		sdl.GPUBufferCreateInfo{usage = {.VERTEX}, size = size_of(ground_verts)},
	)
	if vertex_buffer == nil {
		log_sdl_fatal("Failed to create vertex buffer")
	}
	defer sdl.ReleaseGPUBuffer(device, vertex_buffer)

	// Upload ground quad + checkerboard texture via single copy pass
	vert_transfer := sdl.CreateGPUTransferBuffer(
		device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = size_of(ground_verts)},
	)
	vert_ptr := sdl.MapGPUTransferBuffer(device, vert_transfer, false)
	mem.copy(vert_ptr, &ground_verts, size_of(ground_verts))
	sdl.UnmapGPUTransferBuffer(device, vert_transfer)

	tex_transfer := sdl.CreateGPUTransferBuffer(
		device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = size_of(checker_pixels)},
	)
	tex_ptr := sdl.MapGPUTransferBuffer(device, tex_transfer, false)
	mem.copy(tex_ptr, &checker_pixels, size_of(checker_pixels))
	sdl.UnmapGPUTransferBuffer(device, tex_transfer)

	upload_cmd := sdl.AcquireGPUCommandBuffer(device)
	copy_pass := sdl.BeginGPUCopyPass(upload_cmd)
	sdl.UploadToGPUBuffer(
		copy_pass,
		sdl.GPUTransferBufferLocation{transfer_buffer = vert_transfer, offset = 0},
		sdl.GPUBufferRegion{buffer = vertex_buffer, offset = 0, size = size_of(ground_verts)},
		false,
	)
	sdl.UploadToGPUTexture(
		copy_pass,
		sdl.GPUTextureTransferInfo {
			transfer_buffer = tex_transfer,
			pixels_per_row = CHECKER_SIZE,
			rows_per_layer = CHECKER_SIZE,
		},
		sdl.GPUTextureRegion{texture = ground_texture, w = CHECKER_SIZE, h = CHECKER_SIZE, d = 1},
		false,
	)
	sdl.EndGPUCopyPass(copy_pass)
	assert(sdl.SubmitGPUCommandBuffer(upload_cmd), "failed to submit ground buffer and texture upload command")
	sdl.ReleaseGPUTransferBuffer(device, vert_transfer)
	sdl.ReleaseGPUTransferBuffer(device, tex_transfer)

	// Sprite pipeline
	sprite_vert := load_shader(device, "build/shaders/sprite.vert.metallib", .VERTEX, 1, 0, scratch_allocator)
	sprite_frag := load_shader(device, "build/shaders/sprite.frag.metallib", .FRAGMENT, 0, 1, scratch_allocator)

	sprite_pipeline := sdl.CreateGPUGraphicsPipeline(
		device,
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
	defer sdl.ReleaseGPUGraphicsPipeline(device, sprite_pipeline)

	sdl.ReleaseGPUShader(device, sprite_vert)
	sdl.ReleaseGPUShader(device, sprite_frag)

	sprite_sampler := sdl.CreateGPUSampler(
		device,
		sdl.GPUSamplerCreateInfo {
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
		},
	)
	if sprite_sampler == nil {
		log_sdl_fatal("Failed to create sprite sampler")
	}
	defer sdl.ReleaseGPUSampler(device, sprite_sampler)

	// Load sprite sheet
	sprite_width, sprite_height, sprite_channels: c.int
	sprite_pixels := stbi.load("assets/sprites/nate.png", &sprite_width, &sprite_height, &sprite_channels, 4)
	if sprite_pixels == nil {
		log.fatalf("Failed to load sprite sheet: %s", stbi.failure_reason())
		panic("sprite load failed")
	}
	sprite_data_size := u32(sprite_width * sprite_height * 4)

	sprite_texture := sdl.CreateGPUTexture(
		device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .R8G8B8A8_UNORM,
			width = u32(sprite_width),
			height = u32(sprite_height),
			layer_count_or_depth = 1,
			num_levels = 1,
			usage = {.SAMPLER},
		},
	)
	if sprite_texture == nil {
		log_sdl_fatal("Failed to create sprite texture")
	}
	defer sdl.ReleaseGPUTexture(device, sprite_texture)

	// Upload sprite sheet to GPU
	sprite_transfer := sdl.CreateGPUTransferBuffer(
		device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = sprite_data_size},
	)
	sprite_ptr := sdl.MapGPUTransferBuffer(device, sprite_transfer, false)
	mem.copy(sprite_ptr, sprite_pixels, int(sprite_data_size))
	sdl.UnmapGPUTransferBuffer(device, sprite_transfer)

	sprite_upload_cmd := sdl.AcquireGPUCommandBuffer(device)
	sprite_copy_pass := sdl.BeginGPUCopyPass(sprite_upload_cmd)
	sdl.UploadToGPUTexture(
		sprite_copy_pass,
		sdl.GPUTextureTransferInfo {
			transfer_buffer = sprite_transfer,
			pixels_per_row = u32(sprite_width),
			rows_per_layer = u32(sprite_height),
		},
		sdl.GPUTextureRegion{texture = sprite_texture, w = u32(sprite_width), h = u32(sprite_height), d = 1},
		false,
	)
	sdl.EndGPUCopyPass(sprite_copy_pass)
	assert(sdl.SubmitGPUCommandBuffer(sprite_upload_cmd), "failed to upload sprite cmd buffer")
	sdl.ReleaseGPUTransferBuffer(device, sprite_transfer)
	stbi.image_free(sprite_pixels)

	log.infof("Loaded sprite sheet: %dx%d", sprite_width, sprite_height)

	// Camera
	cam := Camera {
		target   = {0, 0, 0},
		distance = CAMERA_DIST_DEFAULT,
		pitch    = CAMERA_PITCH,
	}
	proj := linalg.matrix4_perspective_f32(math.to_radians(f32(45.0)), f32(pixel_w) / f32(pixel_h), 0.1, 100.0)

	// Debug camera state
	debug_mode: bool
	debug_cam: Debug_Camera
	saved_cam: Camera

	// Frame timing
	perf_freq := sdl.GetPerformanceFrequency()
	last_counter := sdl.GetPerformanceCounter()

	// Input state
	input: Game_Input
	debug_timing: Debug_Timing

	// Title bar timing display — sampled every 0.5s
	TITLE_UPDATE_INTERVAL :: 0.5
	title_accumulator: f32
	title_frame_count: i32
	title_ms_sum: f32
	title_ms_min: f32 = 999.0
	title_ms_max: f32

	// Main loop
	running := true
	for running {
		// Measure frame time
		now := sdl.GetPerformanceCounter()
		input.dt = f32(now - last_counter) / f32(perf_freq)
		last_counter = now

		debug_timing.dt = input.dt
		debug_timing.frame_ms = input.dt * 1000.0
		debug_timing.fps = input.dt > 0 ? 1.0 / input.dt : 0

		// Accumulate timing samples, update title periodically
		title_accumulator += debug_timing.dt
		title_frame_count += 1
		title_ms_sum += debug_timing.frame_ms
		title_ms_min = min(title_ms_min, debug_timing.frame_ms)
		title_ms_max = max(title_ms_max, debug_timing.frame_ms)

		if title_accumulator >= TITLE_UPDATE_INTERVAL {
			avg_ms := title_ms_sum / f32(title_frame_count)
			sdl.SetWindowTitle(
				window,
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
					if !debug_mode {
						// Enter debug mode — save follow camera, init debug camera at current eye position
						saved_cam = cam
						offset_y := cam.distance * math.sin(cam.pitch)
						offset_z := cam.distance * math.cos(cam.pitch)
						debug_cam = Debug_Camera {
							position = cam.target + {0, offset_y, offset_z},
							yaw      = 0,
							pitch    = -cam.pitch, // looking down at target
							speed    = DEBUG_CAM_SPEED_DEFAULT,
						}
						debug_mode = true
						assert(sdl.SetWindowRelativeMouseMode(window, true), "failed to set relative mouse mode")
						log.infof("Debug camera ON")
					} else {
						// Exit debug mode — restore follow camera
						cam = saved_cam
						debug_mode = false
						assert(sdl.SetWindowRelativeMouseMode(window, false), "failed to set relative mouse mode")
						log.infof("Debug camera OFF")
					}
				case .V:
					if debug_mode {
						vsync = !vsync
						_ = sdl.SetGPUSwapchainParameters(device, window, .SDR, vsync ? .VSYNC : .IMMEDIATE)
						log.infof("VSync: %s", vsync ? "ON" : "OFF")
					}
				}
			case .MOUSE_WHEEL:
				if debug_mode {
					// Scroll adjusts debug camera speed
					debug_cam.speed = clamp(
						debug_cam.speed + event.wheel.y * 2.0,
						DEBUG_CAM_SPEED_MIN,
						DEBUG_CAM_SPEED_MAX,
					)
				} else {
					// Scroll zooms follow camera
					cam.distance -= event.wheel.y * CAMERA_ZOOM_SPEED
					cam.distance = clamp(cam.distance, CAMERA_DIST_MIN, CAMERA_DIST_MAX)
				}
			case .MOUSE_MOTION:
				if debug_mode {
					debug_cam.yaw += event.motion.xrel * MOUSE_SENSITIVITY
					debug_cam.pitch -= event.motion.yrel * MOUSE_SENSITIVITY
					debug_cam.pitch = clamp(debug_cam.pitch, -85.0 * math.RAD_PER_DEG, 85.0 * math.RAD_PER_DEG)
				}
			case .WINDOW_PIXEL_SIZE_CHANGED:
				log.info("WINDOW_PIXEL_SIZE_CHANGED event fired")
				new_w := u32(event.window.data1)
				new_h := u32(event.window.data2)
				if new_w > 0 && new_h > 0 {
					sdl.ReleaseGPUTexture(device, depth_texture)
					depth_texture = sdl.CreateGPUTexture(
						device,
						sdl.GPUTextureCreateInfo {
							type = .D2,
							format = .D32_FLOAT,
							width = new_w,
							height = new_h,
							layer_count_or_depth = 1,
							num_levels = 1,
							usage = {.DEPTH_STENCIL_TARGET},
						},
					)
					if depth_texture == nil {
						log_sdl_fatal("Failed to recreate depth texture on resize")
					}
					proj = linalg.matrix4_perspective_f32(
						math.to_radians(f32(45.0)),
						f32(new_w) / f32(new_h),
						0.1,
						100.0,
					)
				}
			}
		}

		// Gather input from keyboard state
		gather_input(&input)

		// Camera update
		view_proj: matrix[4, 4]f32
		cam_right: Vec3
		cam_up: Vec3
		if debug_mode {
			// Debug free camera — WASD movement along view vectors
			forward := Vec3 {
				math.sin(debug_cam.yaw) * math.cos(debug_cam.pitch),
				math.sin(debug_cam.pitch),
				-math.cos(debug_cam.yaw) * math.cos(debug_cam.pitch),
			}
			right := Vec3{math.cos(debug_cam.yaw), 0, math.sin(debug_cam.yaw)}
			move_speed := debug_cam.speed * input.dt

			if input.move_up.is_down do debug_cam.position += forward * move_speed
			if input.move_down.is_down do debug_cam.position -= forward * move_speed
			if input.move_right.is_down do debug_cam.position += right * move_speed
			if input.move_left.is_down do debug_cam.position -= right * move_speed

			// todo(hector) - move these to the input layer?
			keyboard := sdl.GetKeyboardState(nil)
			if keyboard[sdl.Scancode.E] do debug_cam.position.y += move_speed
			if keyboard[sdl.Scancode.Q] do debug_cam.position.y -= move_speed

			view := linalg.matrix4_look_at_f32(debug_cam.position, debug_cam.position + forward, {0, 1, 0})
			view_proj = proj * view
			cam_right = right
			cam_up = linalg.cross(right, forward)
		} else {
			// Follow camera — WASD pans target (temporary until player exists)
			if input.move_up.is_down do cam.target.z -= CAMERA_PAN_SPEED * input.dt
			if input.move_down.is_down do cam.target.z += CAMERA_PAN_SPEED * input.dt
			if input.move_left.is_down do cam.target.x -= CAMERA_PAN_SPEED * input.dt
			if input.move_right.is_down do cam.target.x += CAMERA_PAN_SPEED * input.dt

			offset_y := cam.distance * math.sin(cam.pitch)
			offset_z := cam.distance * math.cos(cam.pitch)
			eye := cam.target + {0, offset_y, offset_z}
			view := linalg.matrix4_look_at_f32(eye, cam.target, {0, 1, 0})
			view_proj = proj * view
			cam_right = {1, 0, 0}
			cam_forward := Vec3{0, -math.sin(cam.pitch), -math.cos(cam.pitch)}
			cam_up = linalg.cross(cam_right, cam_forward)
		}

		// Acquire command buffer
		cmd := sdl.AcquireGPUCommandBuffer(device)
		if cmd == nil {
			log_sdl_error("Failed to acquire GPU command buffer")
			continue
		}

		// Acquire swapchain texture
		swapchain_tex: ^sdl.GPUTexture
		if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd, window, &swapchain_tex, nil, nil) {
			log_sdl_error("Failed to acquire GPU swapchain texture")
			_ = sdl.SubmitGPUCommandBuffer(cmd)
			continue
		}
		if swapchain_tex == nil {
			// Window minimized or not visible — submit empty command buffer
			_ = sdl.SubmitGPUCommandBuffer(cmd)
			continue
		}

		// Begin render pass — clear to dark gray, clear depth to 1.0
		color_target := sdl.GPUColorTargetInfo {
			texture     = swapchain_tex,
			load_op     = .CLEAR,
			store_op    = .STORE,
			clear_color = {0.1, 0.1, 0.1, 1.0},
		}
		depth_target := sdl.GPUDepthStencilTargetInfo {
			texture     = depth_texture,
			load_op     = .CLEAR,
			store_op    = .STORE,
			clear_depth = 1.0,
		}
		render_pass := sdl.BeginGPURenderPass(cmd, &color_target, 1, &depth_target)

		// Draw ground plane
		sdl.BindGPUGraphicsPipeline(render_pass, pipeline)

		uniforms := Mesh_Uniforms {
			view_proj = view_proj,
			model     = 1, // identity
		}
		sdl.PushGPUVertexUniformData(cmd, 0, &uniforms, size_of(Mesh_Uniforms))

		tex_sampler_bindings := [?]sdl.GPUTextureSamplerBinding{{texture = ground_texture, sampler = sampler}}
		sdl.BindGPUFragmentSamplers(render_pass, 0, raw_data(&tex_sampler_bindings), len(tex_sampler_bindings))

		vbuf_bindings := [?]sdl.GPUBufferBinding{{buffer = vertex_buffer, offset = 0}}
		sdl.BindGPUVertexBuffers(render_pass, 0, raw_data(&vbuf_bindings), len(vbuf_bindings))
		sdl.DrawGPUPrimitives(render_pass, 6, 1, 0, 0)

		// Draw sprite
		sdl.BindGPUGraphicsPipeline(render_pass, sprite_pipeline)

		sprite_uniforms := Sprite_Uniforms {
			view_proj    = view_proj,
			camera_right = cam_right,
			camera_up    = cam_up,
			sprite_pos   = {0, 0, 0},
			sprite_size  = {1.5, 1.5},
			atlas_size   = {f32(sprite_width), f32(sprite_height)},
			sprite_rect  = {0, 33, 33, 33}, // idle down frame
		}
		sdl.PushGPUVertexUniformData(cmd, 0, &sprite_uniforms, size_of(Sprite_Uniforms))

		sprite_sampler_bindings := [?]sdl.GPUTextureSamplerBinding {
			{texture = sprite_texture, sampler = sprite_sampler},
		}
		sdl.BindGPUFragmentSamplers(render_pass, 0, raw_data(&sprite_sampler_bindings), len(sprite_sampler_bindings))

		sdl.DrawGPUPrimitives(render_pass, 4, 1, 0, 0)

		sdl.EndGPURenderPass(render_pass)

		// Submit
		if !sdl.SubmitGPUCommandBuffer(cmd) {
			log_sdl_error("Failed to submit GPU command buffer")
		}

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

load_shader :: proc(
	device: ^sdl.GPUDevice,
	path: string,
	stage: sdl.GPUShaderStage,
	num_uniform_buffers: u32,
	num_samplers: u32,
	allocator: mem.Allocator,
) -> ^sdl.GPUShader {
	code, read_err := os.read_entire_file(path, allocator)
	if read_err != nil {
		log.fatalf("Failed to load shader: %s", path)
		panic("shader load failed")
	}
	// No defer delete — caller owns the allocator lifetime (scratch gets wiped per frame)

	shader := sdl.CreateGPUShader(
		device,
		sdl.GPUShaderCreateInfo {
			code_size = len(code),
			code = raw_data(code),
			entrypoint = "main0",
			format = {.METALLIB},
			stage = stage,
			num_samplers = num_samplers,
			num_uniform_buffers = num_uniform_buffers,
		},
	)

	if shader == nil {
		log.fatalf("Failed to create shader: %s: %s", path, sdl.GetError())
		panic("shader creation failed")
	}
	return shader
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
