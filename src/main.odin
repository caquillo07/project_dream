package main

import intrinsics "base:intrinsics"
import "core:fmt"
import "core:log"
import "core:mem"
import vmem "core:mem/virtual"
import "core:os"
import sdl "vendor:sdl3"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

Vertex :: struct {
	position: [3]f32,
	color:    [3]f32,
}

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

	// Game memory — growable virtual memory arenas
	// Initial block sizes are our best guess. If they grow, we log it so we can tune.
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
	context.temp_allocator = scratch_allocator

	// Track arena sizes so we can warn on growth and tune initial sizes
	permanent_reserved := permanent_arena.total_reserved
	scratch_reserved := scratch_arena.total_reserved
	log.infof("Permanent arena: %s reserved", format_bytes(permanent_reserved))
	log.infof("Scratch arena: %s reserved", format_bytes(scratch_reserved))

	// Load shaders (into scratch — bytes only needed until CreateGPUShader copies them)
	swapchain_format := sdl.GetGPUSwapchainTextureFormat(device, window)

	vert_shader := load_shader(device, "build/shaders/triangle.vert.metallib", .VERTEX, 0, 0, scratch_allocator)
	frag_shader := load_shader(device, "build/shaders/triangle.frag.metallib", .FRAGMENT, 0, 0, scratch_allocator)

	// Create graphics pipeline
	vbuf_descs := [1]sdl.GPUVertexBufferDescription{{slot = 0, pitch = size_of(Vertex), input_rate = .VERTEX}}
	vert_attrs := [2]sdl.GPUVertexAttribute {
		{location = 0, buffer_slot = 0, format = .FLOAT3, offset = u32(offset_of(Vertex, position))},
		{location = 1, buffer_slot = 0, format = .FLOAT3, offset = u32(offset_of(Vertex, color))},
	}
	color_target_descs := [1]sdl.GPUColorTargetDescription{{format = swapchain_format}}

	pipeline := sdl.CreateGPUGraphicsPipeline(
		device,
		sdl.GPUGraphicsPipelineCreateInfo {
			vertex_shader = vert_shader,
			fragment_shader = frag_shader,
			vertex_input_state = {
				vertex_buffer_descriptions = raw_data(&vbuf_descs),
				num_vertex_buffers = 1,
				vertex_attributes = raw_data(&vert_attrs),
				num_vertex_attributes = 2,
			},
			primitive_type = .TRIANGLELIST,
			rasterizer_state = {fill_mode = .FILL, cull_mode = .NONE},
			target_info = {color_target_descriptions = raw_data(&color_target_descs), num_color_targets = 1},
		},
	)
	if pipeline == nil {
		log_sdl_fatal("Failed to create graphics pipeline")
	}
	defer sdl.ReleaseGPUGraphicsPipeline(device, pipeline)

	sdl.ReleaseGPUShader(device, vert_shader)
	sdl.ReleaseGPUShader(device, frag_shader)

	// Create vertex buffer and upload triangle data
	vertices := [3]Vertex {
		{{0.0, 0.5, 0.0}, {1.0, 0.0, 0.0}}, // top — red
		{{-0.5, -0.5, 0.0}, {0.0, 1.0, 0.0}}, // bottom-left — green
		{{0.5, -0.5, 0.0}, {0.0, 0.0, 1.0}}, // bottom-right — blue
	}

	vertex_buffer := sdl.CreateGPUBuffer(device, sdl.GPUBufferCreateInfo{usage = {.VERTEX}, size = size_of(vertices)})
	if vertex_buffer == nil {
		log_sdl_fatal("Failed to create vertex buffer")
	}
	defer sdl.ReleaseGPUBuffer(device, vertex_buffer)

	// Upload via transfer buffer
	transfer_buf := sdl.CreateGPUTransferBuffer(
		device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = size_of(vertices)},
	)
	data_ptr := sdl.MapGPUTransferBuffer(device, transfer_buf, false)
	mem.copy(data_ptr, &vertices, size_of(vertices))
	sdl.UnmapGPUTransferBuffer(device, transfer_buf)

	upload_cmd := sdl.AcquireGPUCommandBuffer(device)
	copy_pass := sdl.BeginGPUCopyPass(upload_cmd)
	sdl.UploadToGPUBuffer(
		copy_pass,
		sdl.GPUTransferBufferLocation{transfer_buffer = transfer_buf, offset = 0},
		sdl.GPUBufferRegion{buffer = vertex_buffer, offset = 0, size = size_of(vertices)},
		false,
	)
	sdl.EndGPUCopyPass(copy_pass)
	_ = sdl.SubmitGPUCommandBuffer(upload_cmd)
	sdl.ReleaseGPUTransferBuffer(device, transfer_buf)

	// Main loop
	running := true
	for running {
		event: sdl.Event
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				running = false
			case .KEY_DOWN:
				#partial switch event.key.scancode {
				case .ESCAPE:
					running = false
				}
			}
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

		// Begin render pass — clear to dark gray
		color_target := sdl.GPUColorTargetInfo {
			texture     = swapchain_tex,
			load_op     = .CLEAR,
			store_op    = .STORE,
			clear_color = {0.1, 0.1, 0.1, 1.0},
		}
		render_pass := sdl.BeginGPURenderPass(cmd, &color_target, 1, nil)

		// Draw triangle
		sdl.BindGPUGraphicsPipeline(render_pass, pipeline)
		bindings := [1]sdl.GPUBufferBinding{{buffer = vertex_buffer, offset = 0}}
		sdl.BindGPUVertexBuffers(render_pass, 0, raw_data(&bindings), 1)
		sdl.DrawGPUPrimitives(render_pass, 3, 1, 0, 0)

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
