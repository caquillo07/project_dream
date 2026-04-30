package main

import "base:intrinsics"
import runtime "base:runtime"
import "core:fmt"
import "core:log"
import math "core:math"
import "core:math/linalg"
import "core:mem"
import vmem "core:mem/virtual"
import sdl "vendor:sdl3"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

Debug_Timing :: struct {
	fps:                   f32,
	frame_ms:              f32,
	platform_init_elapsed: f32,
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
	_ctx := context
	sdl.SetLogPriorities(.VERBOSE when ODIN_DEBUG else .INFO)
	sdl.SetLogOutputFunction(
		proc "c" (userdata: rawptr, category: sdl.LogCategory, priority: sdl.LogPriority, message: cstring) {
			context = (cast(^runtime.Context)userdata)^
			log.debugf("SDL {} [{}]: {}", category, priority, message)
		},
		&_ctx,
	)
	if !sdl.Init({.VIDEO}) {
		log_sdl_fatal("Failed to init SDL")
	}
	defer sdl.Quit()

	// init renderer and all assets needed, then clear the temp allocator to
	// let the game start fresh.
	temp_scratch_arena := vmem.arena_temp_begin(&scratch_arena)

	init_renderer()
	defer deinit_renderer()

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

	log.info("loading ground plane")
	ground_texture := load_texture_from_pixels(CHECKER_SIZE, CHECKER_SIZE, checker_pixels[:])
	defer unload_texture(ground_texture)

	// Ground quad — 6 vertices on XZ plane at Y=0
	GROUND_HALF :: f32(10.0)
	UV_TILES :: f32(5.0) // how many times the checkerboard repeats
	ground_verts := [6]Model_Vertex {
		// Triangle 1 (CCW when viewed from above: +Y)
		{{-GROUND_HALF, 0, -GROUND_HALF}, {0, 0}, {0, 1, 0}, {}, {}},
		{{-GROUND_HALF, 0, GROUND_HALF}, {0, UV_TILES}, {0, 1, 0}, {}, {}},
		{{GROUND_HALF, 0, GROUND_HALF}, {UV_TILES, UV_TILES}, {0, 1, 0}, {}, {}},
		// Triangle 2
		{{-GROUND_HALF, 0, -GROUND_HALF}, {0, 0}, {0, 1, 0}, {}, {}},
		{{GROUND_HALF, 0, GROUND_HALF}, {UV_TILES, UV_TILES}, {0, 1, 0}, {}, {}},
		{{GROUND_HALF, 0, -GROUND_HALF}, {UV_TILES, 0}, {0, 1, 0}, {}, {}},
	}

	ground_mesh_vertex_buffer := renderer_upload_buffer(ground_verts[:], .VERTEX)
	defer renderer_release_vertex_buffer(ground_mesh_vertex_buffer)

	sprite_texture := load_texture("assets/sprites/nate.png")
	defer unload_texture(sprite_texture)

	// loading a model
	bat_model, bat_model_ok := load_model("assets/models/animated_halloween_bat.glb")
	assert(bat_model_ok, "failed to load bat model")
	defer unload_model(&bat_model)

	// Title bar timing display — sampled every 0.5s
	TITLE_UPDATE_INTERVAL :: 0.5
	title_accumulator: f32
	title_frame_count: i32
	title_ms_sum: f32
	title_ms_min: f32 = 999.0
	title_ms_max: f32

	platform.debug_timing.platform_init_elapsed = elapsed_ms(main_started_at)
	log.infof("platform init took %.2fms", platform.debug_timing.platform_init_elapsed)

	// clear the temp arena so we can start the game loop fresh
	vmem.arena_temp_end(temp_scratch_arena)
	vmem.arena_check_temp(&scratch_arena)

	// Main loop and Frame timing
	game_init(&platform.game)
	last_frame_counter := time_now()
	game_running, global_pause := true, false
	dt: f32
	for game_running {
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

		// Process input events
		reset_game_input(&platform.game_input)
		event: sdl.Event
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				game_running = false
			case .WINDOW_FOCUS_LOST:
				// todo
				log.infof("window has lost focus")
			case .WINDOW_MINIMIZED:
				// todo
				log.infof("window has been minimized")
			case .WINDOW_OCCLUDED:
				// todo
				log.infof("window has been occluded")
			case .KEY_DOWN, .KEY_UP:
				// todo: contexts + raw key array (see input_system_spec.md)
				is_down := event.type == .KEY_DOWN
				if !is_down || (is_down && !event.key.repeat) { 	// kind of usesless... but just in case
					for btn in InputAction {
						if event.key.scancode == key_bindings[btn] {
							update_button(&platform.game_input.buttons[btn], is_down)
						}
					}
				}
			case .MOUSE_WHEEL:
				// if using natural scrolling, convert back to regular
				//  todo - not sure if i want this, maybe it can be a setting if
				//   someone else wants/needs it
				scroll := event.wheel.y
				if event.wheel.direction == .FLIPPED do scroll = -scroll
				platform.game_input.mouse_scroll_delta += scroll

			case .MOUSE_MOTION:
				platform.game_input.mouse_position_delta.x += event.motion.xrel
				platform.game_input.mouse_position_delta.y += event.motion.yrel
				platform.game_input.mouse_position = {event.motion.x, event.motion.y}

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

		if button_is_pressed(platform.game_input.buttons[.GlobalGamePause]) {
			global_pause = !global_pause
		}

		// Game update
		previous_debug_mode := platform.game.debug_mode
		previous_vsync_mode := platform.game.vsync
		if !global_pause {
			game_update_and_render(
				&platform.game,
				&platform.game_input,
				dt,
				platform.renderer.pixel_width,
				platform.renderer.pixel_height,
			)
		} else {
			if is_key_pressed(&platform.game_input, .Cancel) {
				game_running = false
			}
		}

		if platform.game.debug_mode != previous_debug_mode {
			assert(
				sdl.SetWindowRelativeMouseMode(platform.renderer.window, platform.game.debug_mode),
				"failed to set relative mouse mode",
			)
			log.infof("Debug camera %s", platform.game.debug_mode ? "ON" : "OFF")
		}

		if platform.game.vsync != previous_vsync_mode {
			renderer_enable_vsync(platform.game.vsync)
			log.infof("VSync: %s", platform.game.vsync ? "ON" : "OFF")
		}
		if platform.game.quit_game {
			game_running = false
		}

		cmd, render_pass, ok := renderer_begin_frame()
		if !ok {
			log_sdl_warn("failed to begin frame")
			continue
		}

		/////// Draw Calls //////
		// todo split game + platform

		// Draw ground plane
		sdl.BindGPUGraphicsPipeline(render_pass, renderer_pipeline(.Mesh))

		uniforms := Mesh_Uniforms {
			view_proj  = platform.game.view_proj,
			model      = linalg.MATRIX4F32_IDENTITY,
			color_tint = Vec4{1, 1, 1, 1}, // white = no tint
		}
		sdl.PushGPUVertexUniformData(cmd, 0, &uniforms, size_of(Mesh_Uniforms))
		sdl.PushGPUFragmentUniformData(cmd, 0, &uniforms, size_of(Mesh_Uniforms))

		// todo - bind_fragment_texture
		tex_sampler_bindings := [?]sdl.GPUTextureSamplerBinding {
			{texture = ground_texture.sdl_texture, sampler = platform.renderer.nearest_repeat_sampler},
		}
		sdl.BindGPUFragmentSamplers(render_pass, 0, raw_data(&tex_sampler_bindings), len(tex_sampler_bindings))
		// todo - end of bind_fragment_texture

		vbuf_bindings := [?]sdl.GPUBufferBinding{{buffer = ground_mesh_vertex_buffer, offset = 0}}
		sdl.BindGPUVertexBuffers(render_pass, 0, raw_data(&vbuf_bindings), len(vbuf_bindings))
		sdl.DrawGPUPrimitives(render_pass, 6, 1, 0, 0)

		// Draw sprite // todo move this to the game rendering layer later...
		player := get_player(&platform.game)
		sdl.BindGPUGraphicsPipeline(render_pass, renderer_pipeline(.Sprite))

		sprite_anim_frame := player.sprite_animation.anim_frame

		sprite_rect :=
			nate_walk_frames[player.direction][sprite_anim_frame] if player.sprite_animation.is_playing else nate_idle_frames[player.direction]
		sprite_uniforms := Sprite_Uniforms {
			view_proj    = platform.game.view_proj,
			camera_right = platform.game.camera_right,
			camera_up    = platform.game.camera_up,
			sprite_pos   = player.position,
			sprite_size  = {1.0, 1.0},
			atlas_size   = {f32(sprite_texture.width), f32(sprite_texture.height)},
			sprite_rect  = sprite_rect, // idle down frame
		}
		sdl.PushGPUVertexUniformData(cmd, 0, &sprite_uniforms, size_of(Sprite_Uniforms))

		// todo - bind_fragment_texture
		sprite_sampler_bindings := [?]sdl.GPUTextureSamplerBinding {
			{texture = sprite_texture.sdl_texture, sampler = platform.renderer.nearest_clamp_sampler},
		}
		sdl.BindGPUFragmentSamplers(render_pass, 0, raw_data(&sprite_sampler_bindings), len(sprite_sampler_bindings))
		// todo - end of bind_fragment_texture

		sdl.DrawGPUPrimitives(render_pass, 4, 1, 0, 0)

		// draw bat model
		// world position, always in order translation * rotation * scale
		model_matrix :=
			linalg.matrix4_translate(Vec3{0, 2, 0}) *
			linalg.matrix4_rotate(math.to_radians(f32(-90)), Vec3{1, 0, 0}) *
			linalg.matrix4_scale(Vec3{0.3, 0.3, 0.3})

		sdl.BindGPUGraphicsPipeline(render_pass, renderer_pipeline(.Mesh))

		for mesh, i in bat_model.meshes {
			material := bat_model.materials[bat_model.mesh_material[i]]
			mesh_uniforms := Mesh_Uniforms {
				view_proj  = platform.game.view_proj,
				model      = model_matrix,
				color_tint = material.color_tint,
			}
			sdl.PushGPUVertexUniformData(cmd, 0, &mesh_uniforms, size_of(Mesh_Uniforms))
			sdl.PushGPUFragmentUniformData(cmd, 0, &mesh_uniforms, size_of(Mesh_Uniforms))

			texture := material.base_color_texture.sdl_texture
			if texture == nil {
				texture = platform.renderer.fallback_texture.sdl_texture
			}
			material_sampler_bindings := [?]sdl.GPUTextureSamplerBinding {
				{texture = texture, sampler = platform.renderer.nearest_repeat_sampler},
			}

			sdl.BindGPUFragmentSamplers(
				render_pass,
				0,
				raw_data(&material_sampler_bindings),
				len(material_sampler_bindings),
			)
			sdl.BindGPUVertexBuffers(render_pass, 0, &sdl.GPUBufferBinding{buffer = mesh.vertex_buffer}, 1)
			sdl.BindGPUIndexBuffer(render_pass, sdl.GPUBufferBinding{buffer = mesh.index_buffer}, ._32BIT)
			sdl.DrawGPUIndexedPrimitives(render_pass, u32(len(mesh.indices)), 1, 0, 0, 0)
		}

		// debug stuff
		if platform.game.debug_mode {
			game_camera_frustum_uniforms := Debug_Line_Uniforms {
				view_proj = platform.game.view_proj,
			}

			debug_frustum_corners := platform.game.debug_frustum_corners

			// Filled frustum faces (draw first so wireframe renders on top)
			fill := ColorYellow
			fill.a = 0.15
			frustum_tris := [36]Debug_Line_Vertex {
				// Near face
				{position = debug_frustum_corners[0], color = fill},
				{position = debug_frustum_corners[1], color = fill},
				{position = debug_frustum_corners[2], color = fill},
				{position = debug_frustum_corners[0], color = fill},
				{position = debug_frustum_corners[2], color = fill},
				{position = debug_frustum_corners[3], color = fill},
				// Far face
				{position = debug_frustum_corners[4], color = fill},
				{position = debug_frustum_corners[6], color = fill},
				{position = debug_frustum_corners[5], color = fill},
				{position = debug_frustum_corners[4], color = fill},
				{position = debug_frustum_corners[7], color = fill},
				{position = debug_frustum_corners[6], color = fill},
				// Left face
				{position = debug_frustum_corners[0], color = fill},
				{position = debug_frustum_corners[3], color = fill},
				{position = debug_frustum_corners[7], color = fill},
				{position = debug_frustum_corners[0], color = fill},
				{position = debug_frustum_corners[7], color = fill},
				{position = debug_frustum_corners[4], color = fill},
				// Right face
				{position = debug_frustum_corners[1], color = fill},
				{position = debug_frustum_corners[5], color = fill},
				{position = debug_frustum_corners[6], color = fill},
				{position = debug_frustum_corners[1], color = fill},
				{position = debug_frustum_corners[6], color = fill},
				{position = debug_frustum_corners[2], color = fill},
				// Top face
				{position = debug_frustum_corners[3], color = fill},
				{position = debug_frustum_corners[2], color = fill},
				{position = debug_frustum_corners[6], color = fill},
				{position = debug_frustum_corners[3], color = fill},
				{position = debug_frustum_corners[6], color = fill},
				{position = debug_frustum_corners[7], color = fill},
				// Bottom face
				{position = debug_frustum_corners[0], color = fill},
				{position = debug_frustum_corners[4], color = fill},
				{position = debug_frustum_corners[5], color = fill},
				{position = debug_frustum_corners[0], color = fill},
				{position = debug_frustum_corners[5], color = fill},
				{position = debug_frustum_corners[1], color = fill},
			}

			sdl.BindGPUGraphicsPipeline(render_pass, renderer_pipeline(.DebugTriangles))
			sdl.PushGPUVertexUniformData(cmd, 0, &game_camera_frustum_uniforms, size_of(Debug_Line_Uniforms))
			frustum_tris_buf := renderer_upload_buffer(frustum_tris[:], .VERTEX)
			defer renderer_release_vertex_buffer(frustum_tris_buf)

			frustum_tris_vert_buf := [?]sdl.GPUBufferBinding{{buffer = frustum_tris_buf, offset = 0}}
			sdl.BindGPUVertexBuffers(render_pass, 0, raw_data(&frustum_tris_vert_buf), len(frustum_tris_vert_buf))
			sdl.DrawGPUPrimitives(render_pass, len(frustum_tris), 1, 0, 0)

			// Frustum wireframe
			sdl.BindGPUGraphicsPipeline(render_pass, renderer_pipeline(.DebugLines))
			sdl.PushGPUVertexUniformData(cmd, 0, &game_camera_frustum_uniforms, size_of(Debug_Line_Uniforms))

			frustum_lines := [?]Debug_Line_Vertex {
				// Near quad`
				{position = debug_frustum_corners[0], color = ColorYellow},
				{position = debug_frustum_corners[1], color = ColorYellow},
				{position = debug_frustum_corners[1], color = ColorYellow},
				{position = debug_frustum_corners[2], color = ColorYellow},
				{position = debug_frustum_corners[2], color = ColorYellow},
				{position = debug_frustum_corners[3], color = ColorYellow},
				{position = debug_frustum_corners[3], color = ColorYellow},
				{position = debug_frustum_corners[0], color = ColorYellow},
				// Far quad
				{position = debug_frustum_corners[4], color = ColorYellow},
				{position = debug_frustum_corners[5], color = ColorYellow},
				{position = debug_frustum_corners[5], color = ColorYellow},
				{position = debug_frustum_corners[6], color = ColorYellow},
				{position = debug_frustum_corners[6], color = ColorYellow},
				{position = debug_frustum_corners[7], color = ColorYellow},
				{position = debug_frustum_corners[7], color = ColorYellow},
				{position = debug_frustum_corners[4], color = ColorYellow},
				// Connecting edges
				{position = debug_frustum_corners[0], color = ColorYellow},
				{position = debug_frustum_corners[4], color = ColorYellow},
				{position = debug_frustum_corners[1], color = ColorYellow},
				{position = debug_frustum_corners[5], color = ColorYellow},
				{position = debug_frustum_corners[2], color = ColorYellow},
				{position = debug_frustum_corners[6], color = ColorYellow},
				{position = debug_frustum_corners[3], color = ColorYellow},
				{position = debug_frustum_corners[7], color = ColorYellow},
			}

			frustum_buf := renderer_upload_buffer(frustum_lines[:], .VERTEX)
			defer renderer_release_vertex_buffer(frustum_buf)
			frustum_buf_vert_bindings := [?]sdl.GPUBufferBinding{{buffer = frustum_buf, offset = 0}}
			sdl.BindGPUVertexBuffers(
				render_pass,
				0,
				raw_data(&frustum_buf_vert_bindings),
				len(frustum_buf_vert_bindings),
			)
			sdl.DrawGPUPrimitives(render_pass, len(frustum_lines), 1, 0, 0)

			// camera eye cross - upload and draw
			eye := platform.game.debug_game_cam_eye
			eye_lines := [?]Debug_Line_Vertex {
				{position = eye + {-DebugGameCameraEyeCrossSize, 0, 0}, color = ColorCyan},
				{position = eye + {DebugGameCameraEyeCrossSize, 0, 0}, color = ColorCyan},
				{position = eye + {0, -DebugGameCameraEyeCrossSize, 0}, color = ColorCyan},
				{position = eye + {0, DebugGameCameraEyeCrossSize, 0}, color = ColorCyan},
				{position = eye + {0, 0, -DebugGameCameraEyeCrossSize}, color = ColorCyan},
				{position = eye + {0, 0, DebugGameCameraEyeCrossSize}, color = ColorCyan},
			}

			eye_buf := renderer_upload_buffer(eye_lines[:], .VERTEX)
			eye_buf_vert_bidnings := [?]sdl.GPUBufferBinding{{buffer = eye_buf, offset = 0}}
			sdl.BindGPUVertexBuffers(render_pass, 0, raw_data(&eye_buf_vert_bidnings), len(eye_buf_vert_bidnings))
			sdl.DrawGPUPrimitives(render_pass, len(eye_lines), 1, 0, 0)
		}

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

