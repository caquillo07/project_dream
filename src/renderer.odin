package main

import "core:c"
import fmt "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

Pipeline_Kind :: enum {
	Mesh,
	Sprite,
}

Render_State :: struct {
	pixel_width:            int,
	pixel_height:           int,
	proj:                   linalg.Matrix4f32,
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
	width:       u32,
	height:      u32,
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

	// projection matrix
	renderer.proj = linalg.matrix4_perspective_f32(
		math.to_radians(f32(45.0)),
		f32(renderer.pixel_width) / f32(renderer.pixel_height),
		0.1,
		100.0,
	)

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
	renderer.proj = linalg.matrix4_perspective_f32(math.to_radians(f32(45.0)), f32(width) / f32(height), 0.1, 100.0)
}

renderer_enable_vsync :: proc(enable: bool) {
	if !sdl.SetGPUSwapchainParameters(renderer.device, renderer.window, .SDR, enable ? .VSYNC : .IMMEDIATE) {
		state := enable ? "enable" : "disable"
		log_sdl_warn(fmt.tprintf("failed to %s vsync", state))
	}
}

renderer_begin_frame :: proc() -> (^sdl.GPUCommandBuffer, ^sdl.GPURenderPass, bool) {
	// Acquire command buffer
	cmd := sdl.AcquireGPUCommandBuffer(renderer.device)
	if cmd == nil {
		log_sdl_error("Failed to acquire GPU command buffer")
		return nil, nil, false
	}

	// Acquire swapchain texture
	swapchain_tex: ^sdl.GPUTexture
	if !sdl.WaitAndAcquireGPUSwapchainTexture(cmd, renderer.window, &swapchain_tex, nil, nil) {
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
		texture     = renderer.depth_texture,
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

load_texture :: proc(path: string) -> Texture {
	// Load sprite sheet
	image_width, image_height, image_channels: c.int
	// todo handle allocations here
	image_pixels := stbi.load(strings.unsafe_string_to_cstring(path), &image_width, &image_height, &image_channels, 4)
	if image_pixels == nil {
		log.fatalf("Failed to load texture iamge: %s", stbi.failure_reason())
		panic("texture load failed")
	}

	defer stbi.image_free(image_pixels)
	image_data_size := u32(image_width * image_height * 4)
	return load_texture_from_pixels(u32(image_width), u32(image_height), image_pixels, image_data_size)
}

load_texture_from_pixels :: proc(tex_width, tex_height: u32, pixels_buf: [^]byte, pixels_buf_size: u32) -> Texture {
	sdl_texture := sdl.CreateGPUTexture(
		renderer.device,
		sdl.GPUTextureCreateInfo {
			type = .D2,
			format = .R8G8B8A8_UNORM,
			width = u32(tex_width),
			height = u32(tex_height),
			layer_count_or_depth = 1,
			num_levels = 1,
			usage = {.SAMPLER},
		},
	)
	if sdl_texture == nil {
		log_sdl_fatal("Failed to create texture")
	}

	// Upload sprite sheet to GPU
	tex_transfer := sdl.CreateGPUTransferBuffer(
		renderer.device,
		sdl.GPUTransferBufferCreateInfo{usage = .UPLOAD, size = pixels_buf_size},
	)
	transfer_buf_ptr := sdl.MapGPUTransferBuffer(renderer.device, tex_transfer, false)
	mem.copy(transfer_buf_ptr, pixels_buf, int(pixels_buf_size))
	sdl.UnmapGPUTransferBuffer(renderer.device, tex_transfer)

	tex_upload_cmd := sdl.AcquireGPUCommandBuffer(renderer.device)
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
	sdl.ReleaseGPUTransferBuffer(renderer.device, tex_transfer)

	log.infof("Loaded texture: %dx%d", tex_width, tex_height)
	return {sdl_texture = sdl_texture, height = u32(tex_height), width = u32(tex_width)}
}

unload_texture :: proc(t: Texture) {
	sdl.ReleaseGPUTexture(renderer.device, t.sdl_texture)
}
