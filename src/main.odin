package main

import "base:intrinsics"
import "core:fmt"
import "core:log"
import "core:math"
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

Platform :: struct {
	game:         Game_State,
	renderer:     Render_State,
	game_input:   Game_Input,
	debug_timing: Debug_Timing,
}

platform: Platform

main :: proc() {
	// Game memory — growable virtual memory arenas
	// Initial block sizes are our best guess. If they grow, we log it so we can tune.
	// todo - we need a permanet for the game memory and one for the platform,
	//  do this when we get to hot reloading
	main_started_at := time_now()
	permanent_arena: vmem.Arena
	if vmem.arena_init_growing(&permanent_arena, 64 * mem.Megabyte) != nil {
		panic("Failed to init permanent arena")
	}
	permanent_allocator := vmem.arena_allocator(&permanent_arena)

	scratch_arena: vmem.Arena
	if vmem.arena_init_growing(&scratch_arena, 16 * mem.Megabyte) != nil {
		panic("Failed to init scratch arena")
	}
	scratch_allocator := vmem.arena_allocator(&scratch_arena)

	// Own all temp memory — tprintf and friends go through our scratch arena
	context.allocator = permanent_allocator
	context.temp_allocator = scratch_allocator

	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	// Track arena sizes so we can warn on growth and tune initial sizes
	permanent_reserved := permanent_arena.total_reserved
	scratch_reserved := scratch_arena.total_reserved
	log.infof("Permanent arena: %s reserved", format_bytes(permanent_reserved))
	log.infof("Scratch arena: %s reserved", format_bytes(scratch_reserved))

	// Init SDL
	if !sdl.Init({.VIDEO}) {
		log_sdl_fatal("Failed to init SDL")
	}
	defer sdl.Quit()

	// init renderer, then clear the temp allocator to let the game start fresh
	init_renderer()
	defer deinit_renderer()
	free_all(context.temp_allocator)

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

	ground_texture := load_texture_from_pixels(CHECKER_SIZE, CHECKER_SIZE, checker_pixels[:])
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

	ground_mesh_vertex_buffer := renderer_upload_vertex_buffer(ground_verts[:])
	defer renderer_release_vertex_buffer(ground_mesh_vertex_buffer)

	sprite_texture := load_texture("assets/sprites/nate.png")
	defer unload_texture(sprite_texture)

	// Title bar timing display — sampled every 0.5s
	TITLE_UPDATE_INTERVAL :: 0.5
	title_accumulator: f32
	title_frame_count: i32
	title_ms_sum: f32
	title_ms_min: f32 = 999.0
	title_ms_max: f32

	log.infof("platform init took %.2fms", elapsed_ms(main_started_at))

	// Main loop and Frame timing
	game_init(&platform.game)
	last_frame_counter := time_now()
	running, global_pause := true, false
	dt: f32
	for running {
		// Measure frame time
		now := time_now()
		dt = elapsed(last_frame_counter)
		last_frame_counter = now

		platform.debug_timing.frame_ms = dt * 1000.0
		platform.debug_timing.fps = dt > 0 ? 1.0 / dt : 0

		// Accumulate timing samples, update title periodically
		title_accumulator += dt
		title_frame_count += 1
		title_ms_sum += platform.debug_timing.frame_ms
		title_ms_min = min(title_ms_min, platform.debug_timing.frame_ms)
		title_ms_max = max(title_ms_max, platform.debug_timing.frame_ms)

		if title_accumulator >= TITLE_UPDATE_INTERVAL {
			avg_ms := title_ms_sum / f32(title_frame_count)
			sdl.SetWindowTitle(
				platform.renderer.window,
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

		reset_game_input(&platform.game_input)
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
					if !platform.game.debug_mode {
						// Enter debug mode — save follow camera, init debug camera at current eye position
						platform.game.saved_cam = platform.game.camera
						offset_y := platform.game.camera.distance * math.sin(platform.game.camera.pitch)
						offset_z := platform.game.camera.distance * math.cos(platform.game.camera.pitch)
						platform.game.debug_cam = Debug_Camera {
							position = platform.game.camera.target + {0, offset_y, offset_z},
							yaw      = 0,
							pitch    = -platform.game.camera.pitch, // looking down at target
							speed    = DebugCamSpeedDefault,
						}
						platform.game.debug_mode = true
						assert(
							sdl.SetWindowRelativeMouseMode(platform.renderer.window, true),
							"failed to set relative mouse mode",
						)
						log.infof("Debug camera ON")
					} else {
						// Exit debug mode — restore follow camera
						platform.game.camera = platform.game.saved_cam
						platform.game.debug_mode = false
						assert(
							sdl.SetWindowRelativeMouseMode(platform.renderer.window, false),
							"failed to set relative mouse mode",
						)
						log.infof("Debug camera OFF")
					}
				case .V:
					if platform.game.debug_mode {
						platform.renderer.vsync = !platform.renderer.vsync // todo - should live on platform?
						renderer_enable_vsync(platform.renderer.vsync)
						log.infof("VSync: %s", platform.renderer.vsync ? "ON" : "OFF")
					}
				}
			case .MOUSE_WHEEL:
				scroll := event.wheel.y
				// if using natural scrolling, convert back to regular
				//  todo - not sure if i want this, maybe it can be a setting if
				//   someone else wants/needs it
				// if event.wheel.direction == .FLIPPED do scroll = -scroll
				platform.game_input.scroll_delta += scroll

				// todo move to game layer
				if platform.game.debug_mode {
					// Scroll adjusts debug camera game.speed
					platform.game.debug_cam.speed = clamp(
						platform.game.debug_cam.speed + platform.game_input.scroll_delta * 2.0,
						DebugCamSpeedMin,
						DebugCamSpeedMax,
					)
				} else {
					// Scroll zooms follow camera
					platform.game.camera.distance -= platform.game_input.scroll_delta * CameraZoomSpeed
					platform.game.camera.distance = clamp(platform.game.camera.distance, CameraDistMin, CameraDistMax)
				}
			case .MOUSE_MOTION:
				platform.game_input.mouse_delta.x += event.motion.xrel
				platform.game_input.mouse_delta.y += event.motion.yrel
				platform.game_input.mouse_position = {event.motion.x, event.motion.y}

				// todo move to game layer
				if platform.game.debug_mode {
					platform.game.debug_cam.yaw += platform.game_input.mouse_delta.x * MouseSensitivity
					platform.game.debug_cam.pitch -= platform.game_input.mouse_delta.y * MouseSensitivity
					platform.game.debug_cam.pitch = clamp(
						platform.game.debug_cam.pitch,
						-85.0 * math.RAD_PER_DEG,
						85.0 * math.RAD_PER_DEG,
					)
				}
			case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
				is_down := event.type == .MOUSE_BUTTON_DOWN
				if event.button.button == sdl.BUTTON_LEFT do update_button(&platform.game_input.mouse_left, is_down)
				if event.button.button == sdl.BUTTON_RIGHT do update_button(&platform.game_input.mouse_right, is_down)

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
		gather_input(&platform.game_input)

		// Game update
		if !global_pause {
			game_update_and_render(&platform.game, &platform.game_input, dt, platform.renderer.proj)
		}


		cmd, render_pass, ok := renderer_begin_frame()
		if !ok {
			log_sdl_warn("failed to begin frame")
			continue
		}

		// Draw ground plane
		sdl.BindGPUGraphicsPipeline(render_pass, renderer_pipeline(.Mesh))

		uniforms := Mesh_Uniforms {
			view_proj = platform.game.view_proj,
			model     = 1, // identity
		}
		sdl.PushGPUVertexUniformData(cmd, 0, &uniforms, size_of(Mesh_Uniforms))

		// todo - bind_fragment_texture
		tex_sampler_bindings := [?]sdl.GPUTextureSamplerBinding {
			{texture = ground_texture.sdl_texture, sampler = platform.renderer.nearest_repeat_sampler},
		}
		sdl.BindGPUFragmentSamplers(render_pass, 0, raw_data(&tex_sampler_bindings), len(tex_sampler_bindings))
		// todo - end of bind_fragment_texture

		vbuf_bindings := [?]sdl.GPUBufferBinding{{buffer = ground_mesh_vertex_buffer, offset = 0}}
		sdl.BindGPUVertexBuffers(render_pass, 0, raw_data(&vbuf_bindings), len(vbuf_bindings))
		sdl.DrawGPUPrimitives(render_pass, 6, 1, 0, 0)

		// Draw sprite
		player := get_player(&platform.game)
		sdl.BindGPUGraphicsPipeline(render_pass, renderer_pipeline(.Sprite))

		sprite_uniforms := Sprite_Uniforms {
			view_proj    = platform.game.view_proj,
			camera_right = platform.game.camera_right,
			camera_up    = platform.game.camera_up,
			sprite_pos   = player.position,
			sprite_size  = {1.5, 1.5},
			atlas_size   = {f32(sprite_texture.width), f32(sprite_texture.height)},
			sprite_rect  = {0, 33, 33, 33}, // idle down frame
		}
		sdl.PushGPUVertexUniformData(cmd, 0, &sprite_uniforms, size_of(Sprite_Uniforms))

		// todo - bind_fragment_texture
		sprite_sampler_bindings := [?]sdl.GPUTextureSamplerBinding {
			{texture = sprite_texture.sdl_texture, sampler = platform.renderer.nearest_clamp_sampler},
		}
		sdl.BindGPUFragmentSamplers(render_pass, 0, raw_data(&sprite_sampler_bindings), len(sprite_sampler_bindings))
		// todo - end of bind_fragment_texture

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
		free_all(context.temp_allocator)
	}
}

update_button :: proc(button: ^Button_State, is_down: bool) {
	was_down := button.is_down
	button.is_down = is_down
	button.pressed = is_down && !was_down
	button.released = !is_down && was_down
}

reset_game_input :: proc(input: ^Game_Input) {
	input.scroll_delta = 0
	input.mouse_delta = {}
}

gather_input :: proc(input: ^Game_Input) {
	keyboard := sdl.GetKeyboardState(nil)

	update_button(&input.move_up, keyboard[sdl.Scancode.W])
	update_button(&input.move_down, keyboard[sdl.Scancode.S])
	update_button(&input.move_left, keyboard[sdl.Scancode.A])
	update_button(&input.move_right, keyboard[sdl.Scancode.D])
	update_button(&input.action_a, keyboard[sdl.Scancode.SPACE])
	update_button(&input.action_b, keyboard[sdl.Scancode.E])
	// TODO: conflicts with game action B (E/Q) — resolve when game
	//  actions are wired
	update_button(&input.cam_fly_down, keyboard[sdl.Scancode.Q])
	update_button(&input.cam_fly_up, keyboard[sdl.Scancode.E])
}

time_now :: proc() -> u64 {
	return u64(sdl.GetPerformanceCounter())
}

elapsed_ms :: proc(start: u64) -> f32 {
	return elapsed(start) * 1000.0
}

elapsed :: proc(start: u64) -> f32 {
	return f32(sdl.GetPerformanceCounter() - start) / f32(sdl.GetPerformanceFrequency())
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

