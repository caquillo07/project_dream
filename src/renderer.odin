package main

import "core:c"
import fmt "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import sdl "vendor:sdl3"

Pipeline_Kind :: enum {
	Mesh,
	Sprite,
}

Render_State :: struct {
	pixel_width:            int,
	pixel_height:           int,
	vsync:                  bool,
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
}

init_renderer :: proc() {
	// Create window
	renderer.window = sdl.CreateWindow("Project Dream", WINDOW_WIDTH, WINDOW_HEIGHT, {.RESIZABLE})
	if renderer.window == nil {
		log_sdl_fatal("Failed to create window")
	}

	// Init ShaderCross — runtime SPIR-V transpilation to native GPU format
	if !ShaderCross_Init() {
		log.fatalf("Failed to init ShaderCross: %s", sdl.GetError())
		panic("ShaderCross init failed")
	}

	shader_formats := ShaderCross_GetSPIRVShaderFormats()
	log.infof("ShaderCross supported formats: %v", shader_formats)

	renderer.device = sdl.CreateGPUDevice(shader_formats, ODIN_DEBUG, nil)
	if renderer.device == nil {
		log_sdl_fatal("Failed to create GPU device")
	}

	// Claim window for GPU rendering
	if !sdl.ClaimWindowForGPUDevice(renderer.device, renderer.window) {
		log_sdl_fatal("Failed to claim window")
	}
	// Get actual pixel dimensions (may differ from logical on HiDPI/Retina)
	pixel_w, pixel_h: c.int
	assert(sdl.GetWindowSizeInPixels(renderer.window, &pixel_w, &pixel_h))
	log.infof("Window: %dx%d logical, %dx%d pixels", WINDOW_WIDTH, WINDOW_HEIGHT, pixel_w, pixel_h)

	renderer.pixel_height = int(pixel_h)
	renderer.pixel_width = int(pixel_w)

	// VSync on by default
	renderer.vsync = true
	assert(sdl.SetGPUSwapchainParameters(renderer.device, renderer.window, .SDR, .VSYNC))

	renderer.swapchain_format = sdl.GetGPUSwapchainTextureFormat(renderer.device, renderer.window)
	log.infof("using swapchain format: %v", renderer.swapchain_format)

	// Depth buffer
	renderer.depth_texture = sdl.CreateGPUTexture(
		renderer.device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .D32_FLOAT,
			width = u32(renderer.pixel_width),
			height = u32(renderer.pixel_height),
			layer_count_or_depth = 1,
			num_levels = 1,
			usage = {.DEPTH_STENCIL_TARGET},
		},
	)
	if renderer.depth_texture == nil {
		log_sdl_fatal("Failed to create depth texture")
	}

	renderer.nearest_repeat_sampler = sdl.CreateGPUSampler(
		renderer.device,
		sdl.GPUSamplerCreateInfo {
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			address_mode_u = .REPEAT,
			address_mode_v = .REPEAT,
		},
	)
	if renderer.nearest_repeat_sampler == nil {
		log_sdl_fatal("Failed to create sampler")
	}

	renderer.nearest_clamp_sampler = sdl.CreateGPUSampler(
		renderer.device,
		sdl.GPUSamplerCreateInfo {
			min_filter = .NEAREST,
			mag_filter = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
		},
	)
	if renderer.nearest_clamp_sampler == nil {
		log_sdl_fatal("Failed to create sprite sampler")
	}

}

deinit_renderer :: proc() {
	sdl.ReleaseGPUSampler(renderer.device, renderer.nearest_clamp_sampler)
	sdl.ReleaseGPUSampler(renderer.device, renderer.nearest_repeat_sampler)
	sdl.ReleaseGPUTexture(renderer.device, renderer.depth_texture)
	sdl.DestroyGPUDevice(renderer.device)
	sdl.DestroyWindow(renderer.window)
	ShaderCross_Quit()
}

renderer_resize_viewport :: proc(width, height: u32) {
	sdl.ReleaseGPUTexture(renderer.device, renderer.depth_texture)
	renderer.depth_texture = sdl.CreateGPUTexture(
		renderer.device,
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
	if renderer.depth_texture == nil {
		log_sdl_fatal("Failed to recreate depth texture on resize")
	}
}

renderer_enable_vsync :: proc(enable: bool) {
	if !sdl.SetGPUSwapchainParameters(renderer.device, renderer.window, .SDR, renderer.vsync ? .VSYNC : .IMMEDIATE) {
		state := enable ? "enable" : "disable"
		log_sdl_warn(fmt.tprintf("failed to %s vsync", state))
	}
}

load_shader :: proc(
	renderer: Render_State,
	spv_path: string,
	stage: sdl.GPUShaderStage,
	num_uniform_buffers: u32,
	num_samplers: u32,
	allocator: mem.Allocator,
) -> ^sdl.GPUShader {
	code, read_err := os.read_entire_file(spv_path, allocator)
	if read_err != nil {
		log.fatalf("Failed to load shader: %s", spv_path)
		panic("shader load failed")
	}

	sc_stage: ShaderCross_ShaderStage = stage == .VERTEX ? .VERTEX : .FRAGMENT

	shader := ShaderCross_CompileGraphicsShaderFromSPIRV(
		renderer.device,
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

load_texture :: proc() -> Texture {
	t: Texture
	return t
}

