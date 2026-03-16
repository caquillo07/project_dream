package main

import "core:c"
import sdl "vendor:sdl3"

SHADERCROSS_LIB_PATH :: "../ext-libs/SDL_gpu_shadercross/build/"

foreign import shadercross_lib {SHADERCROSS_LIB_PATH + "libSDL3_shadercross.a"}

ShaderCross_ShaderStage :: enum c.int {
	VERTEX,
	FRAGMENT,
	COMPUTE,
}

ShaderCross_GraphicsShaderResourceInfo :: struct {
	num_samplers:         u32,
	num_storage_textures: u32,
	num_storage_buffers:  u32,
	num_uniform_buffers:  u32,
}

ShaderCross_SPIRV_Info :: struct {
	bytecode:      [^]u8,
	bytecode_size: c.size_t,
	entrypoint:    cstring,
	shader_stage:  ShaderCross_ShaderStage,
	props:         sdl.PropertiesID,
}

@(default_calling_convention = "c", link_prefix = "SDL_")
foreign shadercross_lib {
	ShaderCross_Init :: proc() -> bool ---
	ShaderCross_Quit :: proc() ---
	ShaderCross_GetSPIRVShaderFormats :: proc() -> sdl.GPUShaderFormat ---
	ShaderCross_CompileGraphicsShaderFromSPIRV :: proc(device: ^sdl.GPUDevice, info: ^ShaderCross_SPIRV_Info, resource_info: ^ShaderCross_GraphicsShaderResourceInfo, props: sdl.PropertiesID) -> ^sdl.GPUShader ---
}
