package gpu
// This is a very lightweight idiomatic Odin wrapper for the SDL_GPU and ShaderCross APIs.

import "base:runtime"
import "core:strings"
import "core:mem"
import "core:log"
import m "core:math/linalg/glsl"

import sdl "vendor:sdl3"
import "external:shadercross"

// Internal ^sdl.GPUDevice wrapper. Do not use directly.
_device :: struct {
    handle: ^sdl.GPUDevice,
    arena: mem.Arena,
    arena_allocator: mem.Allocator,
    backing_allocator: mem.Allocator,
    debug_mode, verbose_mode, low_power_mode: bool,
}

// i32 rectangle
irect :: struct {
    offset: m.ivec2,
    size: m.ivec2,
}

// An opaque handle representing the SDL_GPU context.
device :: ^_device

// An opaque handle representing a buffer.
//
// Used for vertices, indices, indirect draw commands, and general compute data.
buffer :: ^sdl.GPUBuffer
// An opaque handle representing a transfer buffer.
//
// Used for transferring data to and from the device.
transferbuffer :: ^sdl.GPUTransferBuffer
// An opaque handle representing a texture.
texture :: ^sdl.GPUTexture
// An opaque handle representing a sampler.
sampler :: ^sdl.GPUSampler
// An opaque handle representing a compiled shader object.
shader :: ^sdl.GPUShader
// An opaque handle representing a compute pipeline.
//
// Used during compute passes.
compute_pipeline :: ^sdl.GPUComputePipeline
// An opaque handle representing a graphics pipeline.
//
// Used during render passes.
pipeline :: ^sdl.GPUGraphicsPipeline
// An opaque handle representing a fence.
fence :: ^sdl.GPUFence

// Specifies the primitive topology of a graphics pipeline.
//
// If you are using `point_list` you must include a point size output in the vertex shader.
//
// - For HLSL compiling to SPIRV you must decorate a float output with [[vk::builtin("PointSize")]].
// - For GLSL you must set the gl_PointSize builtin.
// - For MSL you must include a float output with the [[point_size]] decorator.
//
// Note that sized point topology is totally unsupported on D3D12. Any size other than 1 will be ignored.
// In general, you should avoid using point topology for both compatibility and performance reasons.
// You WILL regret using it.
primitive_type :: enum i32 {
    // A series of separate triangles.
    triangle_list,
    // A series of connected triangles.
    triangle_strip,
    // A series of separate lines.
    line_list,
    // A series of connected lines.
    line_strip,
    // A series of separate points.
    point_list,
}

// Specifies how the contents of a texture attached to a render pass are treated at the beginning of the render pass.
load_op :: enum i32 {
    // The previous contents of the texture will be preserved.
    load,
    // The contents of the texture will be cleared to a color.
    clear,
    // The previous contents of the texture need not be preserved. The contents will be undefined.
    dont_care,
}

// Specifies how the contents of a texture attached to a render pass are treated at the end of the render pass.
store_op :: enum i32 {
    // The contents generated during the render pass will be written to memory.
    store,
    // The contents generated during the render pass are not needed and may be discarded. The contents will be undefined.
    dont_care,
    // The multisample contents generated during the render pass will be resolved to a non-multisample texture. The contents in the multisample texture may then be discarded and will be undefined.
    resolve,
    // The multisample contents generated during the render pass will be resolved to a non-multisample texture. The contents in the multisample texture will be written to memory.
    resolve_and_store,
}

// Specifies the size of elements in an index buffer.
index_element_size :: enum i32 {
    // The index elements are 16-bit.
    word,
    // The index elements are 32-bit.
    dword,
}

// Specifies the pixel format of a texture.
//
// Texture format support varies depending on driver, hardware, and usage flags. In general, you should use
// `texture_supports_format` to query if a format is supported before using it. However, there are a few guaranteed formats.
//
// For `{.sampler}` usage, the following formats are universally supported:
// - `rgba8_unorm`
// - `bgra8_unorm`
// - `r8_unorm`
// - `r8_snorm`
// - `rg8_unorm`
// - `rg8_snorm`
// - `rgba8_snorm`
// - `r16_float`
// - `rg16_float`
// - `rgba16_float`
// - `r32_float`
// - `rg32_float`
// - `rgba32_float`
// - `rg11b10_ufloat`
// - `rgba8_unorm_srgb`
// - `bgra8_unorm_srgb`
// - `d16_unorm`
//
// For `{.color_target}` usage, the following formats are universally supported:
// - `rgba8_unorm`
// - `bgra8_unorm`
// - `r8_unorm`
// - `r16_float`
// - `rg16_float`
// - `rgba16_float`
// - `r32_float`
// - `rg32_float`
// - `rgba32_float`
// - `r8_uint`
// - `rg8_uint`
// - `rgba8_uint`
// - `r16_uint`
// - `rg16_uint`
// - `rgba16_uint`
// - `r8_int`
// - `rg8_int`
// - `rgba8_int`
// - `r16_int`
// - `rg16_int`
// - `rgba16_int`
// - `rgba8_unorm_srgb`
// - `bgra8_unorm_srgb`
//
// For `{.storage}` usages, the following formats are universally supported:
// - `rgba8_unorm`
// - `rgba8_snorm`
// - `rgba16_float`
// - `r32_float`
// - `rg32_float`
// - `rgba32_float`
// - `rgba8_uint`
// - `rgba16_uint`
// - `rgba8_int`
// - `rgba16_int`
//
// For `{.depth_stencil_target}` usage, the following formats are universally supported:
// - `d16_unorm`
// - Either (but not necessarily both!) `d24_unorm` or `d32_float`
// - Either (but not necessarily both!) `d24_unorm_s8_uint` or `d32_float_s8_uint`
//
// Unless `d16_unorm` is sufficient for your purposes, always check which of D24/D32 is supported before creating
// a depth-stencil texture!
texture_format :: enum i32 {
    invalid,

    // Unsigned Normalized Float Color Formats
    a8_unorm,
    r8_unorm,
    rg8_unorm,
    rgba8_unorm,
    r16_unorm,
    rg16_unorm,
    rgba16_unorm,
    rgb10a2_unorm,
    b5g6r5_unorm,
    bgr5a1_unorm,
    bgra4_unorm,
    bgra8_unorm,

    // Compressed Unsigned Normalized Float Color Formats
    bc1_rgba_unorm,
    bc2_rgba_unorm,
    bc3_rgba_unorm,
    bc4_r_unorm,
    bc5_rg_unorm,
    bc7_rgba_unorm,

    // Compressed Signed Float Color Formats
    bc6h_rgb_float,

	// Compressed Unsigned Float Color Formats
    bc6h_rgb_ufloat,

    // Signed Normalized Float Color Formats
    r8_snorm,
    rg8_snorm,
    rgba8_snorm,
    r16_snorm,
    rg16_snorm,
    rgba16_snorm,

    // Signed Float Color Formats
    r16_float,
    rg16_float,
    rgba16_float,
    r32_float,
    rg32_float,
    rgba32_float,

    // Unsigned Float Color Formats
    rg11b10_float,

    // Unsigned Integer Color Formats
    r8_uint,
    rg8_uint,
    rgba8_uint,
    r16_uint,
    rg16_uint,
    rgba16_uint,
    r32_uint,
    rg32_uint,
    rgba32_uint,

    // Signed Integer Color Formats
    r8_int,
    rg8_int,
    rgba8_int,
    r16_int,
    rg16_int,
    rgba16_int,
    r32_int,
    rg32_int,
    rgba32_int,

    // SRGB Unsigned Normalized Color Formats
    rgba8_unorm_srgb,
    bgra8_unorm_srgb,

    // Compressed SRGB Unsigned Normalized Color Formats
    bc1_rgba_unorm_srgb,
    bc2_rgba_unorm_srgb,
    bc3_rgba_unorm_srgb,
    bc7_rgba_unorm_srgb,

    // Depth Formats
    d16_unorm,
    d24_unorm,
    d32_float,
    d24_unorm_s8_uint,
    d32_float_s8_uint,

    // Compressed ASTC Normalized Float Color Formats*/
	astc_4x4_unorm,
	astc_5x4_unorm,
	astc_5x5_unorm,
	astc_6x5_unorm,
	astc_6x6_unorm,
	astc_8x5_unorm,
	astc_8x6_unorm,
	astc_8x8_unorm,
	astc_10x5_unorm,
	astc_10x6_unorm,
	astc_10x8_unorm,
	astc_10x10_unorm,
	astc_12x10_unorm,
	astc_12x12_unorm,

	// Compressed SRGB ASTC Normalized Float Color Formats*/
	astc_4x4_unorm_srgb,
	astc_5x4_unorm_srgb,
	astc_5x5_unorm_srgb,
	astc_6x5_unorm_srgb,
	astc_6x6_unorm_srgb,
	astc_8x5_unorm_srgb,
	astc_8x6_unorm_srgb,
	astc_8x8_unorm_srgb,
	astc_10x5_unorm_srgb,
	astc_10x6_unorm_srgb,
	astc_10x8_unorm_srgb,
	astc_10x10_unorm_srgb,
	astc_12x10_unorm_srgb,
	astc_12x12_unorm_srgb,

	// Compressed ASTC Signed Float Color Formats*/
	astc_4x4_float,
	astc_5x4_float,
	astc_5x5_float,
	astc_6x5_float,
	astc_6x6_float,
	astc_8x5_float,
	astc_8x6_float,
	astc_8x8_float,
	astc_10x5_float,
	astc_10x6_float,
	astc_10x8_float,
	astc_10x10_float,
	astc_12x10_float,
	astc_12x12_float,
}

// Specifies how a texture is intended to be used by the client.
texture_usage_flag :: enum u32 {
    // Texture supports sampling.
    sampler,
    // Texture is a color render target.
    color_target,
    // Texture is a depth stencil target.
    depth_stencil_target,
    // Texture supports storage reads in graphics stages.
    graphics_storage_read,
    // Texture supports storage reads in the compute stage.
    compute_storage_read,
    // Texture supports storage writes in the compute stage.
    compute_storage_write,
    // Texture supports reads and writes in the same compute shader. This is NOT equivalent to `{.read, .write}`.
    compute_storage_simultaneous_readwrite,
}

// Specifies how a texture is intended to be used by the client.
//
// A texture must have at least one usage flag. Note that some usage flag combinations are invalid.
//
// With regards to compute storage usage, `{.read, .write}` means that you can have shader A that only writes into the texture
// and shader B that only reads from the texture and bind the same texture to either shader respectively.
// `simultaneous` means that you can do reads and writes within the same shader or compute pass. It also implies that atomic ops
// can be used, since those are read-modify-write operations. If you use `simultaneous`, you are responsible for avoiding data
// races, as there is no data synchronization within a compute pass. Note that `simultaneous` usage is only supported by a
// limited number of texture formats.
texture_usage_flags :: distinct bit_set[texture_usage_flag; u32]

// Specifies the type of a texture.
texture_type :: enum i32 {
    // The texture is a 2-dimensional image.
    d2,
    // The texture is a 2-dimensional array image.
    d2_array,
    // The texture is a 3-dimensional image.
    d3,
    // The texture is a cube image.
    cube,
    // The texture is a cube array image.
    cube_array,
}

// Specifies the sample count of a texture.
//
// Used in multisampling. Note that this value only applies when the texture is used as a render target.
sample_count :: enum i32 {
    // No multisampling.
    none,
    // MSAA 2x
    x2,
    // MSAA 4x
    x4,
    // MSAA 8x
    x8,
}

// Specifies the face of a cube map.
//
// Can be passed in as the layer field in texture-related structs.
cube_map_face :: enum i32 {
    positive_x,
    negative_x,
    positive_y,
    negative_y,
    positive_z,
    negative_z,
}

// Specifies how a buffer is intended to be used by the client.
buffer_usage_flag :: enum u32 {
    // Buffer is a vertex buffer.
    vertex,
    // Buffer is an index buffer.
    index,
    // Buffer is an indirect buffer.
    indirect,
    // Buffer supports storage reads in graphics stages.
    graphics_storage_read,
    // Buffer supports storage reads in the compute stage.
    compute_storage_read,
    // Buffer supports storage writes in the compute stage.
    compute_storage_write,
}

// Specifies how a buffer is intended to be used by the client.
//
// A buffer must have at least one usage flag. Note that some usage flag combinations are invalid.
//
// Unlike textures, `{.read, .write}` can be used for simultaneous read-write usage. The same data synchronization
// concerns as textures apply.
//
// If you use a `storage` flag, the data in the buffer must respect `std140` layout conventions. In practical terms this
// means you must ensure that `vec3` and `vec4` fields are 16-byte aligned.
buffer_usage_flags :: distinct bit_set[buffer_usage_flag; u32]

// Specifies how a transfer buffer is intended to be used by the client.
//
// Note that mapping and copying FROM an upload transfer buffer or TO a download transfer buffer is undefined behavior.
transferbuffer_usage :: enum i32 {
    upload,
    download,
}

// Specifies the format of shader code.
shader_format_flag :: enum u32 {
    // Shaders for NDA'd platforms.
    private,
    // SPIR-V shaders for Vulkan.
    spirv,
    // DXBC SM5_1 shaders for D3D12.
    dxbc,
    // DXIL SM6_0 shaders for D3D12.
    dxil,
    // MSL shaders for Metal.
    msl,
    // Precompiled metallib shaders for Metal.
    metallib,
}

// Specifies the format of shader code.
//
// Each format corresponds to a specific backend that accepts it.
shader_formats :: distinct bit_set[shader_format_flag; u32]

// Specifies the format of a vertex attribute.
vertex_element_format :: enum i32 {
    invalid,

    // 32-bit Signed Integers
    int,
    int2,
    int3,
    int4,

    // 32-bit Unsigned Integers
    uint,
    uint2,
    uint3,
    uint4,

    // 32-bit Floats
    float,
    float2,
    float3,
    float4,

    // 8-bit Signed Integers
    byte2,
    byte4,

    // 8-bit Unsigned Integers
    ubyte2,
    ubyte4,

    // 8-bit Signed Normalized
    byte2_norm,
    byte4_norm,

    // 8-bit Unsigned Normalized
    ubyte2_norm,
    ubyte4_norm,

    // 16-bit Signed Integers
    short2,
    short4,

    // 16-bit Unsigned Integers
    ushort2,
    ushort4,

    // 16-bit Signed Normalized
    short2_norm,
    short4_norm,

    // 16-bit Unsigned Normalized
    ushort2_norm,
    ushort4_norm,

    // 16-bit Floats
    half2,
    half4,
}

// Specifies the rate at which vertex attributes are pulled from buffers.
vertex_input_rate :: enum i32 {
    // Attribute addressing is a function of the vertex index.
    vertex,
    // Attribute addressing is a function of the instance index.
    instance,
}

// Specifies the facing direction in which triangle faces will be culled.
fill_mode :: enum i32 {
    // Polygons will be rendered via rasterization.
    fill,
    // Polygon edges will be drawn as line segments.
    line,
}

// Specifies the facing direction in which triangle faces will be culled.
cull_mode :: enum i32 {
    // No triangles are culled.
    none,
    // Front-facing triangles are culled.
    front,
    // Back-facing triangles are culled.
    back,
}

// Specifies the vertex winding that will cause a triangle to be determined to be front-facing.
front_face :: enum i32 {
    // A triangle with counter-clockwise vertex winding will be considered front-facing.
    counter_clockwise,
    // A triangle with clockwise vertex winding will be considered front-facing.
    clockwise,
}

// Specifies a comparison operator for depth, stencil and sampler operations.
compare_op :: enum i32 {
    invalid,
    // The comparison always evaluates false.
    never,
    // The comparison evaluates reference <  test.
    less,
    // The comparison evaluates reference == test.
    equal,
    // The comparison evaluates reference <= test.
    less_or_equal,
    // The comparison evaluates reference >  test.
    greater,
    // The comparison evaluates reference != test.
    not_equal,
    // The comparison evaluates reference >= test.
    greater_or_equal,
    // The comparison always evaluates true.
    always,
}

// Specifies what happens to a stored stencil value if stencil tests fail or pass.
stencil_op :: enum i32 {
    invalid,
    // Keeps the current value.
    keep,
    // Sets the value to 0.
    zero,
    // Sets the value to reference.
    replace,
    // Increments the current value and clamps to the maximum value.
    increment_and_clamp,
    // Decrements the current value and clamps to 0.
    decrement_and_clamp,
    // Bitwise-inverts the current value.
    invert,
    // Increments the current value and wraps back to 0.
    increment_and_wrap,
     // Decrements the current value and wraps to the maximum value.
    decrement_and_wrap,
}

// Specifies the operator to be used when pixels in a render target are blended with existing pixels in the texture.
//
// The source color is the value written by the fragment shader. The destination color is the value currently existing
// in the texture.
blend_op :: enum i32 {
    invalid,
    // (source * source_factor) + (destination * destination_factor)
    add,
    // (source * source_factor) - (destination * destination_factor)
    subtract,
    // (destination * destination_factor) - (source * source_factor)
    reverse_subtract,
    // min(source, destination)
    min,
    // max(source, destination)
    max,
}

// Specifies a blending factor to be used when pixels in a render target are blended with existing pixels in the texture.
//
// The source color is the value written by the fragment shader. The destination color is the value currently existing
// in the texture.
blend_factor :: enum i32 {
    invalid,
    // 0
    zero,
    // 1
    one,
    // source color
    src_color,
    // 1 - source color
    one_minus_src_color,
    // destination color
    dst_color,
    // 1 - destination color
    one_minus_dst_color,
    // source alpha
    src_alpha,
    // 1 - source alpha
    one_minus_src_alpha,
    // destination alpha
    dst_alpha,
    // 1 - destination alpha
    one_minus_dst_alpha,
    // blend constant
    constant_color,
    // 1 - blend constant
    one_minus_constant_color,
    // min(source alpha, 1 - destination alpha)
    src_alpha_saturate,
}

// Specifies which color components are written in a graphics pipeline.
color_component_flag :: enum u8 {
    r, g, b, a,
}

// Specifies which color components are written in a graphics pipeline.
color_component_flags :: distinct bit_set[color_component_flag; u8]

// Specifies a filter operation used by a sampler.
filter :: enum i32 {
    // Point filtering.
    nearest,
    // Linear filtering.
    linear,
}

// Specifies a mipmap mode used by a sampler.
mipmap_mode :: enum i32 {
    // Point filtering.
    nearest,
    // Linear filtering.
    linear,
}

// Specifies behavior of texture sampling when the coordinates exceed the 0-1 range.
address_mode :: enum i32 {
    // Specifies that the coordinates will wrap around.
    repeat,
    // Specifies that the coordinates will wrap around mirrored.
    mirrored_repeat,
    // Specifies that the coordinates will clamp to the 0-1 range.
    clamp_to_edge,
}

// Specifies the timing that will be used to present swapchain textures to the OS.
//
// `.vsync` mode will always be supported. `.immediate` and `.mailbox` modes may not be supported on certain systems.
//
// It is recommended to query `window_supports_present_mode` after claiming the window if you wish to change the present
// mode to `.immediate` or `.mailbox`.
present_mode :: enum i32 {
    // Waits for vblank before presenting. No tearing is possible. If there is a pending image to present, the new image
    // is enqueued for presentation. Disallows tearing at the cost of visual latency.
    vsync,
    // Immediately presents. Lowest latency option, but tearing may occur.
    immediate,
    // Waits for vblank before presenting. No tearing is possible. If there is a pending image to present, the pending image
    // is replaced by the new image. Similar to VSYNC, but with reduced visual latency.
    mailbox,
}

// Specifies the texture format and colorspace of the swapchain textures.
//
// `.sdr` will always be supported. Other compositions may not be supported on certain systems.
//
// It is recommended to query `window_supports_swapchain_composition` after claiming the window if you wish to change the
// swapchain composition from `.sdr`.
swapchain_composition :: enum i32 {
    // `bgra8` or `rgba8` swapchain. Pixel values are in sRGB encoding.
    sdr,
    // `bgra8_srgb` or `rgba8_srgb` swapchain. Pixel values are stored in memory in sRGB encoding but accessed in shaders in
    //  "linear sRGB" encoding which is sRGB but with a linear transfer function.
    sdr_linear,
    //  `rgba16_float` swapchain. Pixel values are in extended linear sRGB encoding and permits values outside of the
    // `[0, 1]` range.
    hdr_extended_linear,
    // `a2rgb10` or `a2bgr10` swapchain. Pixel values are in BT.2020 ST2084 (PQ) encoding.
    hdr10_st2084,
}

// The flip mode.
flip_mode :: enum i32 {
    // Do not flip
    none,
    // flip horizontally
    horizontal,
    // flip vertically
    vertical,
    // flip horizontally and vertically (not a diagonal flip)
    horizontal_and_vertical = 1 | 2,
}

// A structure specifying a viewport.
viewport :: struct {
    // The offset of the viewport.
    offset: m.vec2,
    // The width and height of the viewport.
    size: m.vec2,
    // The minimum depth of the viewport.
	min_depth: f32,
    // The maximum depth of the viewport.
	max_depth: f32,
}


// A structure specifying parameters related to transferring data to or from a texture.
//
// If either of `pixels_per_row` or `rows_per_layer` is zero, then width and height of passed `texture_region` to `upload_to_texture`
// or `download_from_texture` are used as default values respectively and data is considered to be tightly packed.
//
// WARNING: On some older/integrated hardware, Direct3D 12 requires texture data row pitch to be 256 byte aligned, and offsets to be
// aligned to 512 bytes. If they are not, SDL will make a temporary copy of the data that is properly aligned, but this adds overhead
// to the transfer process. Apps can avoid this by aligning their data appropriately, or using a different GPU backend than Direct3D 12.
texture_transfer_info :: struct {
    // The transfer buffer used in the transfer operation.
	transfer_buffer: transferbuffer,
    // The starting byte of the image data in the transfer buffer.
	offset:          u32,
    // The number of pixels from one row to the next.
	pixels_per_row:  u32,
    // The number of rows from one layer/depth-slice to the next.
	rows_per_layer:  u32,
}

// A structure specifying a location in a transfer buffer.
//
// Used when transferring buffer data to or from a transfer buffer.
transferbuffer_location :: struct {
    // The transfer buffer used in the transfer operation.
	transfer_buffer: transferbuffer,
    // The starting byte of the buffer data in the transfer buffer.
	offset:          u32,
}

// A structure specifying a location in a texture.
texture_location :: struct {
    // The texture used in the copy operation.
	texture:   texture,
    // The mip level index of the location.
	mip_level: u32,
    // The layer index of the location.
	layer:     u32,
    // The offset of the location.
    offset: m.uvec3,
}

// A structure specifying a region of a texture.
//
// Used when transferring data to or from a texture.
texture_region :: struct {
    // The texture used in the copy operation.
	texture:   texture,
    // The mip level index to transfer.
	mip_level: u32,
    // The layer index to transfer.
	layer:     u32,
    // The left, top and front offset of the region.
    offset: m.uvec3,
    // The width and height of the region.
    size: m.uvec2,
    // The depth of the region.
    depth: u32,
}

// A structure specifying a location in a buffer.
//
// Used when copying data between buffers.
buffer_location :: struct {
    // The buffer.
	buffer: buffer,
    // The starting byte within the buffer.
	offset: u32,
}

// A structure specifying a region of a buffer.
//
// Used when transferring data to or from buffers.
buffer_region :: struct {
    // The buffer.
	buffer: buffer,
    // The starting byte within the buffer.
	offset: u32,
    // The size in bytes of the region.
	size:   u32,
}

// A structure specifying the parameters of an indirect draw command.
//
// - **NOTE:** In the vertex and fragment shaders, `SV_VertexID` and `SV_InstanceID` will be offset by `first_vertex` and `first_instance`
// respectively. This wouldn't be true for the `"d3d12"` driver, but this wrapper doesn't use that.
indirect_draw_command :: struct {
    // The number of vertices to draw.
	num_vertices:   u32,
    // The number of instances to draw.
	num_instances:  u32,
    // The index of the first vertex to draw.
	first_vertex:   u32,
    // The ID of the first instance to draw.
	first_instance: u32,
}
// A structure specifying the parameters of an indexed indirect draw command.
//
// - **NOTE:** In the vertex and fragment shaders, `SV_VertexID` and `SV_InstanceID` will be offset by `first_vertex` and `first_instance`
// respectively. This wouldn't be true for the `"d3d12"` driver, but this wrapper doesn't use that.
indexed_indirect_draw_command :: struct {
    // The number of indices to draw per instance.
	num_indices:    u32,
    // The number of instances to draw.
	num_instances:  u32,
    // The base index within the index buffer.
	first_index:    u32,
    // The value added to the vertex index before indexing into the vertex buffer.
	vertex_offset:  i32,
    // The ID of the first instance to draw.
	first_instance: u32,
}

// A structure specifying the parameters of an indexed dispatch command.
indirect_dispatch_command :: struct {
    // The number of local workgroups to dispatch in the X dimension.
	groupcount_x: u32,
    // The number of local workgroups to dispatch in the Y dimension.
	groupcount_y: u32,
    // The number of local workgroups to dispatch in the Z dimension.
	groupcount_z: u32,
}

// A structure specifying the parameters of a sampler.
//
// Note that `mip_lod_bias` is a no-op for the Metal driver. For Metal, LOD bias must be applied via shader instead.
sampler_desc :: struct {
    // A name that can be displayed in debugging tools.
    name: string,
    // The minification filter to apply to lookups.
	min_filter:        filter,
    // The magnification filter to apply to lookups.
	mag_filter:        filter,
    // The mipmap filter to apply to lookups.
	mipmap_mode:       mipmap_mode,
    // The addressing mode for U coordinates outside [0, 1).
	address_mode_u:    address_mode,
    // The addressing mode for V coordinates outside [0, 1).
	address_mode_v:    address_mode,
    // The addressing mode for W coordinates outside [0, 1).
	address_mode_w:    address_mode,
    // The bias to be added to mipmap LOD calculation.
	mip_lod_bias:      f32,
    // The anisotropy value clamp used by the sampler. If enable_anisotropy is false, this is ignored.
	max_anisotropy:    f32,
    // The comparison operator to apply to fetched data before filtering.
	compare_op:        compare_op,
    // Clamps the minimum of the computed LOD value.
	min_lod:           f32,
    // Clamps the maximum of the computed LOD value.
	max_lod:           f32,
    // true to enable anisotropic filtering.
	enable_anisotropy: bool,
    // true to enable comparison against a reference value during lookups.
	enable_compare:    bool,
}

// A structure specifying the parameters of vertex buffers used in a graphics pipeline.
//
// When you call `bind_vertex_buffers`, you specify the binding slots of the vertex buffers. For example if you called `bind_vertex_buffers` with a
// `first_slot` of 2 and `num_bindings` of 3, the binding slots 2, 3, 4 would be used by the vertex buffers you pass in.
//
// Vertex attributes are linked to buffers via the `buffer_slot` field of `vertex_attribute`. For example, if an attribute has a `buffer_slot` of 0,
// then that attribute belongs to the vertex buffer bound at slot 0.
vertex_buffer_info :: struct {
    // The binding slot of the vertex buffer.
	slot:               u32,
    // The byte pitch between consecutive elements of the vertex buffer.
	pitch:              u32,
    // Whether attribute addressing is a function of the vertex index or instance index.
	input_rate:         vertex_input_rate,
    // Reserved for future use. Must be set to 0.
	instance_step_rate: u32,
}

// A structure specifying a vertex attribute.
//
// All vertex attribute locations provided to an `vertex_input_state` must be unique.
vertex_attribute :: struct {
    // The shader input location index.
	location:    u32,
    // The binding slot of the associated vertex buffer.
	buffer_slot: u32,
    // The size and type of the attribute data.
	format:      vertex_element_format,
    // The byte offset of this attribute relative to the start of the vertex element.
	offset:      u32,
}

// A structure specifying the parameters of a graphics pipeline vertex input state.
vertex_input_state :: struct {
    // A pointer to an array of vertex buffer descriptions.
	vertex_buffer_descriptions: []vertex_buffer_info,
    // A pointer to an array of vertex attribute descriptions.
	vertex_attributes:          []vertex_attribute,
}

// A structure specifying the stencil operation state of a graphics pipeline.
stencil_op_state :: struct {
    // The action performed on samples that fail the stencil test.
	fail_op:       stencil_op,
    // The action performed on samples that pass the depth and stencil tests.
	pass_op:       stencil_op,
    // The action performed on samples that pass the stencil test and fail the depth test.
	depth_fail_op: stencil_op,
    // The comparison operator used in the stencil test.
	compare_op:    compare_op,
}

// A structure specifying the blend state of a color target.
color_target_blend_state :: struct {
    // The value to be multiplied by the source RGB value.
	src_color_blendfactor:   blend_factor,
    // The value to be multiplied by the destination RGB value.
	dst_color_blendfactor:   blend_factor,
    // The blend operation for the RGB components.
	color_blend_op:          blend_op,
    // The value to be multiplied by the source alpha.
	src_alpha_blendfactor:   blend_factor,
    // The value to be multiplied by the destination alpha.
	dst_alpha_blendfactor:   blend_factor,
    // The blend operation for the alpha component.
	alpha_blend_op:          blend_op,
    // A bitmask specifying which of the RGBA components are enabled for writing. Writes to all channels if enable_color_write_mask is false.
	color_write_mask:        color_component_flags,
    // Whether blending is enabled for the color target.
	enable_blend:            bool,
    // Whether the color write mask is enabled.
	enable_color_write_mask: bool,
}

// A structure specifying the parameters of a texture.
texture_desc :: struct {
    // A name that can be displayed in debugging tools.
    name: string,
    // The base dimensionality of the texture.
	type:                 texture_type,
    // The pixel format of the texture.
	format:               texture_format,
    // How the texture is intended to be used by the client.
	usage:                texture_usage_flags,
    // The width of the texture.
	width:                u32,
    // The height of the texture.
	height:               u32,
    // The layer count or depth of the texture. This value is treated as a layer count on 2D array textures, and as a depth value on 3D textures.
	layer_count_or_depth: u32,
    // The number of mip levels in the texture.
	num_levels:           u32,
    // The number of samples per texel. Only applies if the texture is used as a render target.
	sample_count:         sample_count,
}

// A structure specifying the parameters of a buffer.
buffer_desc :: struct {
    // A name that can be displayed in debugging tools.
    name: string,
    // How the buffer is intended to be used by the client.
	usage: buffer_usage_flags,
    // The size in bytes of the buffer.
	size:  u32,
}

// A structure specifying the parameters of a transfer buffer.
transferbuffer_desc :: struct {
    // A name that can be displayed in debugging tools.
    name: string,
    // How the transfer buffer is intended to be used by the client.
	usage: transferbuffer_usage,
    // The size in bytes of the transfer buffer.
	size:  u32,
}

// A structure specifying the parameters of the graphics pipeline rasterizer state.
//
// Note that `fill_mode.line` is not supported on many Android devices. For those devices, the fill mode will
// automatically fall back to `.fill`.
//
// Also note that the D3D12 driver will enable depth clamping even if `enable_depth_clip` is true. If you need this clamp+clip behavior,
// consider enabling depth clip and then manually clamping depth in your fragment shaders on Metal and Vulkan.
rasterizer_state :: struct {
    // Whether polygons will be filled in or drawn as lines.
	fill_mode:                  fill_mode,
    // The facing direction in which triangles will be culled.
	cull_mode:                  cull_mode,
    // The vertex winding that will cause a triangle to be determined as front-facing.
	front_face:                 front_face,
    // A scalar factor controlling the depth value added to each fragment.
	depth_bias_constant_factor: f32,
    // The maximum depth bias of a fragment.
	depth_bias_clamp:           f32,
    // A scalar factor applied to a fragment's slope in depth calculations.
	depth_bias_slope_factor:    f32,
    // true to bias fragment depth values.
	enable_depth_bias:          bool,
    // true to enable depth clip, false to enable depth clamp.
	enable_depth_clip:          bool,
    // Padding
    _, _: u8,
}

// A structure specifying the parameters of the graphics pipeline multisample state.
multisample_state :: struct {
    // The number of samples to be used in rasterization.
	sample_count:             sample_count,
    // Reserved for future use. Must be set to 0.
	sample_mask:              u32,
    // Reserved for future use. Must be set to false.
	enable_mask:              bool,
    // true enables the alpha-to-coverage feature.
	enable_alpha_to_coverage: bool,
    // Padding
    _, _: u8,
}

// A structure specifying the parameters of the graphics pipeline depth stencil state.
depth_stencil_state :: struct {
    // The comparison operator used for depth testing.
	compare_op:          compare_op,
    // The stencil op state for back-facing triangles.
	back_stencil_state:  stencil_op_state,
    // The stencil op state for front-facing triangles.
	front_stencil_state: stencil_op_state,
    // Selects the bits of the stencil values participating in the stencil test.
	compare_mask:        u8,
    // Selects the bits of the stencil values updated by the stencil test.
	write_mask:          u8,
    // true enables the depth test.
	enable_depth_test:   bool,
    // true enables depth writes. Depth writes are always disabled when enable_depth_test is false.
	enable_depth_write:  bool,
    // true enables the stencil test.
	enable_stencil_test: bool,
    // padding
    _, _, _: u8,
}

// A structure specifying the parameters of color targets used in a graphics pipeline.
pipeline_color_target :: struct {
    // The pixel format of the texture to be used as a color target.
	format:      texture_format,
    // The blend state to be used for the color target.
	blend_state: color_target_blend_state,
}

// A structure specifying the descriptions of render targets used in a graphics pipeline.
pipeline_target :: struct {
    // A pointer to an array of color target descriptions.
	color_targets: []pipeline_color_target,
    // The pixel format of the depth-stencil target or `nil` if there is no depth-stencil target.
	depth_stencil_format:      Maybe(texture_format),
}

// A structure specifying the parameters of a graphics pipeline state.
pipeline_desc :: struct {
    // A name that can be displayed in debugging tools.
    name: string,
    // The vertex shader used by the graphics pipeline.
	vertex_shader:       shader,
    // The fragment shader used by the graphics pipeline.
	fragment_shader:     shader,
    // The vertex layout of the graphics pipeline.
	vertex_input_state:  vertex_input_state,
    // The primitive topology of the graphics pipeline.
	primitive_type:      primitive_type,
    // The rasterizer state of the graphics pipeline.
	rasterizer_state:    rasterizer_state,
    // The multisample state of the graphics pipeline.
	multisample_state:   multisample_state,
    // The depth-stencil state of the graphics pipeline.
	depth_stencil_state: depth_stencil_state,
    // Formats and blend modes for the render targets of the graphics pipeline.
	target_info:         pipeline_target,
}

// A structure specifying the parameters of a color target used by a render pass.
//
// The `load_op` field determines what is done with the texture at the beginning of the render pass.
// - `load`: Loads the data currently in the texture. Not recommended for multisample textures as it requires significant memory bandwidth.
// - `clear`: Clears the texture to a single color.
// - `dont_care`: The driver will do whatever it wants with the texture memory. This is a good option if you know that every single pixel will be touched in the render pass.
//
// The store_op field determines what is done with the color results of the render pass.
// - `store`: Stores the results of the render pass in the texture. Not recommended for multisample textures as it requires significant memory bandwidth.
// - `dont_care`: The driver will do whatever it wants with the texture memory. This is often a good option for depth/stencil textures.
// - `resolve`: Resolves a multisample texture into resolve_texture, which must have a sample count of 1. Then the driver may discard the multisample texture memory. This is the most performant method of resolving a multisample target.
// - `resolve_and_store`: Resolves a multisample texture into the resolve_texture, which must have a sample count of 1. Then the driver stores the multisample texture's contents. Not recommended as it requires significant memory bandwidth.
color_target :: struct {
    // The texture that will be used as a color target by a render pass.
	texture_handle:               texture,
     // The mip level to use as a color target.
	mip_level:             u32,
    // The layer index or depth plane to use as a color target. This value is treated as a layer index on 2D array and cube textures, and as a depth plane on 3D textures.
	layer_or_depth_plane:  u32,
    // The color to clear the color target to at the start of the render pass. Ignored if GPU_LOADOP_CLEAR is not used.
	clear_color:           m.vec4,
    // What is done with the contents of the color target at the beginning of the render pass.
	load_op:               load_op,
    // What is done with the results of the render pass.
	store_op:              store_op,
    // The texture that will receive the results of a multisample resolve operation. Ignored if a RESOLVE* store_op is not used.
	resolve_texture:       texture,
    // The mip level of the resolve texture to use for the resolve operation. Ignored if a RESOLVE* store_op is not used.
	resolve_mip_level:     u32,
    // The layer index of the resolve texture to use for the resolve operation. Ignored if a RESOLVE* store_op is not used.
	resolve_layer:         u32,
    // true cycles the texture if the texture is bound and load_op is not LOAD
	cycle:                 bool,
    // true cycles the resolve texture if the resolve texture is bound. Ignored if a RESOLVE* store_op is not used.
	cycle_resolve_texture: bool,

	_: u8, _: u8,
}

// A structure specifying the parameters of a depth-stencil target used by a render pass.
//
// The `load_op` field determines what is done with the depth contents of the texture at the beginning of the render pass.
// - `load`: Loads the depth values currently in the texture.
// - `clear`: Clears the texture to a single depth.
// - `dont_care`: The driver will do whatever it wants with the memory. This is a good option if you know that every single pixel will be touched in the render pass.
//
// The `store_op` field determines what is done with the depth results of the render pass.
// - `store`: Stores the depth results in the texture.
// - `dont_care`: The driver will do whatever it wants with the depth results. This is often a good option for depth/stencil textures that don't need to be reused again.
//
// The `stencil_load_op` field determines what is done with the stencil contents of the texture at the beginning of the render pass.
// - `load`: Loads the stencil values currently in the texture.
// - `clear`: Clears the stencil values to a single value.
// - `dont_care`: The driver will do whatever it wants with the memory. This is a good option if you know that every single pixel will be touched in the render pass.
//
// The `stencil_store_op` field determines what is done with the stencil results of the render pass.
// - `store`: Stores the stencil results in the texture.
// - `dont_care`: The driver will do whatever it wants with the stencil results. This is often a good option for depth/stencil textures that don't need to be reused again.
//
// Note that depth/stencil targets do not support multisample resolves.
//
// Due to ABI limitations, depth textures with more than 255 layers are not supported.
depth_stencil_target :: struct {
    // The texture that will be used as the depth stencil target by the render pass.
	texture:          texture,
    // The value to clear the depth component to at the beginning of the render pass. Ignored if `load_op.clear` is not used.
	clear_depth:      f32,
    // What is done with the depth contents at the beginning of the render pass.
	depth_load_op:          load_op,
    // What is done with the depth results of the render pass.
	depth_store_op:         store_op,
    // What is done with the stencil contents at the beginning of the render pass.
	stencil_load_op:  load_op,
    // What is done with the stencil results of the render pass.
	stencil_store_op: store_op,
    // true cycles the texture if the texture is bound and any load ops are not LOAD
	cycle:            bool,
    // The value to clear the stencil component to at the beginning of the render pass. Ignored if `load_op.clear` is not used.
	clear_stencil:    u8,
    // The mip level to use as the depth stencil target.
	mip_level:        u8,
    // The layer index to use as the depth stencil target.
	layer:            u8,
}

// A structure containing parameters for a blit command.
blit_info :: struct {
    // The source region for the blit.
	source:      blit_region,
    // The destination region for the blit.
	destination: blit_region,
    // What is done with the contents of the destination before the blit.
	load_op:     load_op,
    // The color to clear the destination region to before the blit. Ignored if load_op is not `load_op.clear`.
	clear_color: m.vec4,
    // The flip mode for the source region.
	flip_mode:   flip_mode,
    // The filter mode used when blitting.
	filter:      filter,
    // If true cycles the destination texture if it is already bound.
	cycle:       bool,
}

// A structure specifying a region of a texture used in the blit operation.
blit_region :: struct {
    // The texture.
	texture:              texture,
    // The mip level index of the region.
	mip_level:            u32,
    // The layer index or depth plane of the region. This value is treated as a layer index on 2D array and cube textures, and
    // as a depth plane on 3D textures.
	layer_or_depth_plane: u32,
    // The offset of the region.
	offset: m.uvec2,
    // The width and height of the region.
    size: m.uvec2,
}

// A structure specifying parameters in a buffer binding call.
buffer_binding :: struct {
    // The buffer to bind. Must have been created with `{.vertex}` usage flag for `renderpass->bind_vertex_buffers`, or `{.index}` usage flag for `renderpass->bind_index_buffer`.
	buffer: buffer,
    // The starting byte of the data to bind in the buffer.
	offset: u32,
}

// A structure specifying parameters in a sampler binding call.
texture_sampler_binding :: struct {
    // The texture to bind. Must have been created with GPU_TEXTUREUSAGE_SAMPLER.
	texture: texture,
    // The sampler to bind.
	sampler: sampler,
}

// A structure specifying parameters related to binding buffers in a compute pass.
storage_buffer_rw_binding :: struct {
    // The buffer to bind. Must have been created with `buffer_usage.compute_storage_write`.
	buffer: buffer,
    // true cycles the buffer if it is already bound.
	cycle:  bool,
}

// A structure specifying parameters related to binding textures in a compute pass.
storage_texture_rw_binding :: struct {
    // The texture to bind. Must have been created with `texture_usage.compute_storage_write` or `texture_usage.compute_storage_simultaneous_read_write`.
	texture:   texture,
    // The mip level index to bind.
	mip_level: u32,
    // The layer index to bind.
	layer:     u32,
    // true cycles the texture if it is already bound.
	cycle:     bool,
}

// Error handling method for `error_callback`
handle_error :: enum {
    // The error will be silently ignored.
    ignore,
    // The game will crash with an error message, or assert in debug mode
    crash,
}

error_callback: proc(error: cstring, src_loc: runtime.Source_Code_Location) -> handle_error = default_error_callback

default_error_callback :: proc(error: cstring, src_loc: runtime.Source_Code_Location) -> handle_error {
    log.error("GPU error: %q", location = src_loc)
    when ODIN_DEBUG {
        return .crash
    } else {
        return .ignore
    }
}

// Allowed frames in flight. See `change_frames_in_flight` for more information.
frames_in_flight :: enum u32 {
    default = 0,
    one = 1,
    two = 2,
    three = 3,
}

// Parameters to create a device
device_desc :: struct {
    // Debug mode GPU-based validation (Enables Vulkan validation layers)
    debug_mode: bool,
    // Enables verbose logging
    verbose_mode: bool,
    // Will prefer GPUs that consume less power, i.e integrated GPUs
    prefer_low_power: bool,
    // Will try to create an HDR swapchain, may fail
    prefer_hdr: bool,
    // Will try to create a VSynced swapchain
    vsync: bool,
    // Frames in flight preference. Defaults to `.two`
    frames_in_flight: frames_in_flight,
}

// Creates a GPU device.
//
// Allocates heap memory for the handle and a memory arena of 4KiB. The allocator provided will be used to destroy the device and other things.
create_device :: proc(window: ^sdl.Window, desc: device_desc, allocator := context.allocator, src_loc := #caller_location) -> device {
    dev_props := sdl.CreateProperties()
    defer sdl.DestroyProperties(dev_props)
    if desc.debug_mode {
        sdl.SetBooleanProperty(dev_props, sdl.PROP_GPU_DEVICE_CREATE_DEBUGMODE_BOOLEAN, value = true)

        // In debug mode, our shaders are generated with "non semantic debug info" which allows support for debug printf among other cool things.
        //
        // These are only supported with either the VK_KHR_shader_non_semantic_info device extension or Vulkan 1.3. I tried to keep Vulkan 1.0 with
        // just the extension but it didn't seem to really work. It is the only Vulkan 1.3 feature we'll ever use regardless, so keeping it on for
        // debug mode doesn't feel that bad.
        vk_options := sdl.GPUVulkanOptions {
            vulkan_api_version = (1<<22) | (3<<12) | (0), // VK_API_VERSION_1_3
        }
        sdl.SetPointerProperty(dev_props, sdl.PROP_GPU_DEVICE_CREATE_VULKAN_OPTIONS_POINTER, value = &vk_options)
    } else {
        sdl.SetBooleanProperty(dev_props, sdl.PROP_GPU_DEVICE_CREATE_DEBUGMODE_BOOLEAN, value = false)
    }

    sdl.SetBooleanProperty(dev_props, sdl.PROP_GPU_DEVICE_CREATE_PREFERLOWPOWER_BOOLEAN, value = desc.prefer_low_power)

    // We only have access to SPIR-V shaders, and we only want access to the Vulkan backend.
    sdl.SetBooleanProperty(dev_props, sdl.PROP_GPU_DEVICE_CREATE_SHADERS_SPIRV_BOOLEAN, value = true)
    sdl.SetStringProperty(dev_props, sdl.PROP_GPU_DEVICE_NAME_STRING, value = "vulkan")

    handle := sdl.CreateGPUDeviceWithProperties(dev_props)
    check_error_ptr(handle, src_loc)

    dev := new(_device, allocator)
    dev.handle = handle
    mem.arena_init(&dev.arena, make([]u8, 4 * mem.Kilobyte, allocator))
    dev.arena_allocator = mem.arena_allocator(&dev.arena)
    dev.backing_allocator = allocator
    dev.debug_mode = desc.debug_mode
    dev.verbose_mode = desc.verbose_mode
    dev.low_power_mode = desc.prefer_low_power

    // Claim window
    claim_result := sdl.ClaimWindowForGPUDevice(dev.handle, window)
    check_error_bool(claim_result, src_loc)

    // Configure swapchain
    composition: sdl.GPUSwapchainComposition = .SDR
    // Set HDR if preferred and supported
    if desc.prefer_hdr && !sdl.WindowSupportsGPUSwapchainComposition(dev.handle, window, .HDR10_ST2084) {
        log.warn("Requested HDR window but not supported, falling back to SDR")
        composition = .SDR
    } else {
        composition = .HDR10_ST2084
    }

    // If VSync is on: Present with MAILBOX, or VSYNC if that is not supported
    // If VSync is off: Present with IMMEDIATE, or crash if that is not supported
    present_mode: sdl.GPUPresentMode = .MAILBOX
    switch desc.vsync {
    case true:
        if !sdl.SetGPUSwapchainParameters(dev.handle, window, composition, .MAILBOX) {
            log.warn("VSync requested, but ideal present mode MAILBOX is not supported. Using VSYNC instead")
            // .SDR and .VSYNC is guaranteed to always exist
            _ = sdl.SetGPUSwapchainParameters(dev.handle, window, composition, .VSYNC)
            present_mode = .VSYNC
        }
    case false:
        if !sdl.SetGPUSwapchainParameters(dev.handle, window, composition, .IMMEDIATE) {
            // If the user requested VSync to be off and yet it's not supported, it's better to just crash than to lie to them
            log.fatal("Your GPU does not support disabling VSync. Enable it or try updating your graphics drivers")
        }
        present_mode = .IMMEDIATE
    }

    return cast(device) dev
}

// Destroys the GPU device created by `create_device`.
destroy_device :: #force_inline proc(dev: device) {
    sdl.DestroyGPUDevice(dev.handle)

    delete(dev.arena.data, dev.backing_allocator)
    free(dev, dev.backing_allocator)
}


// Attempts to block the thread until the GPU is completely idle.
//
// Prints an error in case that fails.
wait_idle :: #force_inline proc(dev: device, src_loc := #caller_location) {
    if !sdl.WaitForGPUIdle(dev.handle) {
        log.error("Could not wait until GPU is idle: %q. Sync errors may ensue", sdl.GetError(), location = src_loc)
    }
}

// Attempts to block the thread until the given fences are signaled.
//
// Prints an error in case that fails.
wait_fences :: #force_inline proc(dev: device, fences: []fence, wait_all := true, src_loc := #caller_location) {
    if !sdl.WaitForGPUFences(dev.handle, wait_all, raw_data(fences), cast(u32) len(fences)) {
        log.error("Could not wait for fences: %q. Sync errors may ensue", sdl.GetError(), location = src_loc)
    }
}

// Attempts to block the thread until a swapchain texture is available to be acquired.
//
// Prints an error in case that fails.
//
// This function should only be called from the thread that created the window.
wait_swapchain :: #force_inline proc(dev: device, window: ^sdl.Window, src_loc := #caller_location) {
    if !sdl.WaitForGPUSwapchain(dev.handle, window) {
        log.error("Could not wait for SwapChain: %q. Sync errors may ensue", sdl.GetError(), location = src_loc)
    }
}

// Checks the status of a fence. Returns true if the fence is signaled, false if it is not.
query_fence :: #force_inline proc(dev: device, fence: fence) -> bool {
    return sdl.QueryGPUFence(dev.handle, fence)
}

// Releases a fence obtained from `commandbuffer->submit_and_acquire_fence()`. You must not reference the fence after calling this function.
release_fence :: #force_inline proc(dev: device, fence: fence) {
    sdl.ReleaseGPUFence(dev.handle, fence)
}

// Determines if a sample count for a texture format is supported.
supports_texture_sample_count :: #force_inline proc(dev: device, format: texture_format, sample_count: sample_count) -> bool {
    return sdl.GPUTextureSupportsSampleCount(dev.handle, sdl.GPUTextureFormat(format), sdl.GPUSampleCount(sample_count))
}

// Determines whether a texture format is supported for a given type and usage.
supports_texture_format :: #force_inline proc(dev: device, format: texture_format, type: texture_type, usage: texture_usage_flags) -> bool {
    return sdl.GPUTextureSupportsFormat(dev.handle, sdl.GPUTextureFormat(format), sdl.GPUTextureType(type), transmute(sdl.GPUTextureUsageFlags) usage)
}

// Calculate the size in bytes of a texture format with dimensions.
texture_format_size :: #force_inline  proc(format: texture_format, width, height: u32, depth_or_layer_count: u32) -> u32 {
    return sdl.CalculateGPUTextureFormatSize(sdl.GPUTextureFormat(format), width, height, depth_or_layer_count)
}

// Obtains the texel block size for a texture format.
texture_format_texel_block_size :: #force_inline proc(format: texture_format) -> u32 {
    return sdl.GPUTextureFormatTexelBlockSize(sdl.GPUTextureFormat(format))
}

// Obtains the texture format of the swapchain for the given window.
//
// Note that this format can change if the swapchain parameters change.
swapchain_texture_format :: #force_inline proc(dev: device, window: ^sdl.Window) -> texture_format {
    return cast(texture_format) sdl.GetGPUSwapchainTextureFormat(dev.handle, window)
}

// Contains various information about the GPU device used to render.
device_info :: struct {
    // Contains the name of the underlying device as reported by the system driver. This string has no standardized format,
    // is highly inconsistent between hardware devices and drivers, and is able to change at any time. Do not attempt to parse
    // this string as it is bound to fail at some point in the future when system drivers are updated, new hardware devices are
    // introduced, or when SDL adds new GPU backends or modifies existing ones.
    //
    // The same device can have different formats, the vendor name may or may not appear in the string, the included vendor name
    // may not be the vendor of the chipset on the device, some manufacturers include pseudo-legal marks while others don't, some
    // devices may not use a marketing name in the string, the device string may be wrapped by the name of a translation interface,
    // the device may be emulated in software, or the string may contain generic text that does not identify the device at all.
    device_name: string,
    // Contains the self-reported name of the underlying system driver.
    driver_name: string,
    // Contains the self-reported version of the underlying system driver. This is a relatively short version string in an unspecified
    // format. If `driver_info` is not empty, then that field should be preferred over this one as it may  contain additional information
    // that is useful for identifying the exact driver version used.
    driver_version: string,
    // Contains the detailed version information of the underlying system driver as reported by the driver. This is an arbitrary string
    // with no standardized format and it may contain newlines. This property should be preferred over `driver_version` if it is not empty
    // as it usually contains the same information but in a format that is easier to read.
    driver_info: string,
}

// Queries information about the device and the driver. The strings are short lived (allocated with the device's arena allocator)
query_device_info :: proc(dev: device) -> (info: device_info) {

    props := sdl.GetGPUDeviceProperties(dev.handle)
    defer sdl.DestroyProperties(props)

    device_name :=  sdl.GetStringProperty(props, sdl.PROP_GPU_DEVICE_NAME_STRING, "")
    driver_name := sdl.GetStringProperty(props, sdl.PROP_GPU_DEVICE_DRIVER_NAME_STRING, "")
    driver_version := sdl.GetStringProperty(props, sdl.PROP_GPU_DEVICE_DRIVER_VERSION_STRING, "")
    driver_info := sdl.GetStringProperty(props, sdl.PROP_GPU_DEVICE_DRIVER_INFO_STRING, "")

    // Copy the values with the arena allocator
    info.device_name = strings.clone_from_cstring(device_name, dev.arena_allocator)
    info.driver_name = strings.clone_from_cstring(driver_name, dev.arena_allocator)
    info.driver_version = strings.clone_from_cstring(driver_version, dev.arena_allocator)
    info.driver_info = strings.clone_from_cstring(driver_info, dev.arena_allocator)

    return info
}

// Configures the maximum allowed number of frames in flight.
//
// The default value when the device is created is `.two`. This means that after you have submitted two frames for presentation,
// if the GPU has not finished working on the first frame, `acquire_swapchain_texture()` will fill the swapchain texture
// pointer with NULL, and `wait_and_acquire_swapchain_texture()`` will block.
//
// Higher values increase throughput at the expense of visual latency. Lower values decrease visual latency at the expense of throughput.
//
// Note that calling this function will stall and flush the command queue to prevent synchronization issues.
//
// The minimum value of allowed frames in flight is `.one`, and the maximum is `.three`.
change_frames_in_flight :: proc(dev: device, frames_in_flight: frames_in_flight, src_loc := #caller_location) {
    frames := frames_in_flight
    if frames == .default do frames = .two

    result := sdl.SetGPUAllowedFramesInFlight(dev.handle, cast(u32) frames)
    check_error_bool(result, src_loc)
}

// Creates a buffer object to be used in graphics or compute workflows.
//
// The contents of this buffer are undefined until data is written to the buffer.
//
// Note that certain combinations of usage flags are invalid. For example, a buffer cannot have both the `{.vertex}` and `{.index}` flags.
//
// If you use a `{.storage}` flag, the data in the buffer must respect `std140`` layout conventions. In practical terms this means you must
// ensure that `vec3` and `vec4` fields are 16-byte aligned.
//
// For better understanding of underlying concepts and memory management with SDL GPU API, you may refer to
// [this blog post](https://moonside.games/posts/sdl-gpu-concepts-cycling/).
create_buffer :: proc(dev: device, desc: buffer_desc, src_loc := #caller_location) -> buffer {
    tmpmem := mem.begin_arena_temp_memory(&dev.arena)
    defer mem.end_arena_temp_memory(tmpmem)

    ci := sdl.GPUBufferCreateInfo {
        size = desc.size,
        usage = transmute(sdl.GPUBufferUsageFlags) desc.usage,
    }
    // Name the buffer
    if desc.name != "" {
        ci.props = sdl.CreateProperties()
        name_c := to_cstr(dev, desc.name)
        sdl.SetStringProperty(ci.props, sdl.PROP_GPU_BUFFER_CREATE_NAME_STRING, name_c)
    }
    defer if desc.name != "" do sdl.DestroyProperties(ci.props)

    buf := sdl.CreateGPUBuffer(dev.handle, ci)
    check_error_ptr(buf, src_loc)

    return cast(buffer) buf
}

// Frees the given buffer as soon as it is safe to do so. You must not reference the buffer after calling this function.
release_buffer :: #force_inline proc(dev: device, buf: buffer) {
    sdl.ReleaseGPUBuffer(dev.handle, buf)
}

// Creates a transfer buffer to be used when uploading to or downloading from graphics resources.
//
// Download buffers can be particularly expensive to create, so it is good practice to reuse them if data will be downloaded regularly.
create_transferbuffer :: proc(dev: device, desc: transferbuffer_desc, src_loc := #caller_location) -> transferbuffer {
    tmpmem := mem.begin_arena_temp_memory(&dev.arena)
    defer mem.end_arena_temp_memory(tmpmem)

    ci := sdl.GPUTransferBufferCreateInfo {
        usage = cast(sdl.GPUTransferBufferUsage) desc.usage,
        size = desc.size,
    }
    if desc.name != "" {
        ci.props = sdl.CreateProperties()
        name_c := to_cstr(dev, desc.name)
        sdl.SetStringProperty(ci.props, sdl.PROP_GPU_TRANSFERBUFFER_CREATE_NAME_STRING, name_c)
    }
    defer if desc.name != "" do sdl.DestroyProperties(ci.props)

    buf := sdl.CreateGPUTransferBuffer(dev.handle, ci)
    check_error_ptr(buf, src_loc)

    return cast(transferbuffer) buf
}

// Frees the given transfer buffer as soon as it is safe to do so. You must not reference the transfer buffer after calling this function.
release_transferbuffer :: #force_inline proc(dev: device, tbuf: transferbuffer) {
    sdl.ReleaseGPUTransferBuffer(dev.handle, tbuf)
}

// Maps a transfer buffer into application address space. Type is casted into a multi-ptr of `T`.
//
// You must unmap the transfer buffer before encoding upload commands. The memory is owned by the graphics driver. Do NOT free the given slice.
@(require_results)
map_transferbuffer :: #force_inline proc(dev: device, tbuf: transferbuffer, cycle: bool, $T: typeid, src_loc := #caller_location) -> [^]T {
    ptr := sdl.MapGPUTransferBuffer(dev, tbuf, cycle)
    check_error_ptr(ptr, src_loc)

    return cast([^]T) ptr
}

// Unmaps a previously mapped transfer buffer.
unmap_transferbuffer :: #force_inline proc(dev: device, tbuf: transferbuffer) {
    sdl.UnmapGPUTransferBuffer(dev.handle, tbuf)
}

// Creates a texture object to be used in graphics or compute workflows.
//
// The contents of this texture are undefined until data is written to the texture, either via `upload_to_texture` or by performing a render or
// compute pass with this texture as a target.
//
// Note that certain combinations of usage flags are invalid. For example, a texture cannot have both the `{.sampler}` and `{.graphics_storage_read}` flags.
//
// If you request a sample count higher than the hardware supports, the implementation will automatically fall back to the highest available sample count.
create_texture :: proc(dev: device, desc: texture_desc, src_loc := #caller_location) -> texture {
    tmpmem := mem.begin_arena_temp_memory(&dev.arena)
    defer mem.end_arena_temp_memory(tmpmem)

    ci := sdl.GPUTextureCreateInfo {
        type = cast(sdl.GPUTextureType) desc.type,
        format = cast(sdl.GPUTextureFormat) desc.format,
        usage = transmute(sdl.GPUTextureUsageFlags) desc.usage,
        width = desc.width,
        height = desc.height,
        layer_count_or_depth = desc.layer_count_or_depth,
        num_levels = desc.num_levels,
        sample_count = cast(sdl.GPUSampleCount) desc.sample_count,
    }
    if desc.name != "" {
        ci.props = sdl.CreateProperties()
        name_c := to_cstr(dev, desc.name)
        sdl.SetStringProperty(ci.props, sdl.PROP_GPU_TEXTURE_CREATE_NAME_STRING, name_c)
    }
    defer if desc.name != "" do sdl.DestroyProperties(ci.props)

    txt := sdl.CreateGPUTexture(dev.handle, ci)
    check_error_ptr(txt, src_loc)

    return cast(texture) txt
}

// Frees the given texture as soon as it is safe to do so. You must not reference the texture after calling this function.
release_texture :: #force_inline proc(dev: device, txt: texture) {
    sdl.ReleaseGPUTexture(dev.handle, txt)
}

// Creates a sampler object to be used when binding textures in a graphics workflow.
create_sampler :: proc(dev: device, desc: sampler_desc, src_loc := #caller_location) -> sampler {
    tmpmem := mem.begin_arena_temp_memory(&dev.arena)
    defer mem.end_arena_temp_memory(tmpmem)

    ci := sdl.GPUSamplerCreateInfo {
        min_filter = cast(sdl.GPUFilter) desc.min_filter,
    }
    if desc.name != "" {
        ci.props = sdl.CreateProperties()
        name_c := to_cstr(dev, desc.name)
        sdl.SetStringProperty(ci.props, sdl.PROP_GPU_SAMPLER_CREATE_NAME_STRING, name_c)
    }
    defer if desc.name != "" do sdl.DestroyProperties(ci.props)

    smpl := sdl.CreateGPUSampler(dev.handle, ci)
    check_error_ptr(smpl, src_loc)

    return cast(sampler) smpl
}

// Frees the given sampler as soon as it is safe to do so. You must not reference the sampler after calling this function.
release_sampler :: proc(dev: device, smpl: sampler) {
    sdl.ReleaseGPUSampler(dev.handle, smpl)
}

// Specifies which stage a shader program corresponds to.
shader_stage :: enum {
    vertex,
    fragment,
    compute,
}

// Shader macro definition.
shader_define :: struct {
    name, value: string,
}

// A structure specifying the parameters of a shader.
shader_desc :: struct {
    // A name that can be displayed in debugging tools.
    name: string,
    // The stage the shader corresponds to
    stage: shader_stage,
    // Entry point function
    entry_point: string,
    // The include directory for shader code. Optional, can be `""`.
    include_dir: string,
    // An array of macro definitions. Optional, can be empty.
    defines: []shader_define,
}

// Creates a shader to be used when creating a graphics pipeline.
//
// Shader resource bindings must be authored to follow a particular order depending on the shader format. For HLSL shaders,
// use the following register order:
//
// For vertex shaders:
// - `(t[n], space0)`: Sampled textures, followed by storage textures, followed by storage buffers
// - `(s[n], space0)`: Samplers with indices corresponding to the sampled textures
// - `(b[n], space1)`: Uniform buffers
//
// For pixel shaders:
// - `(t[n], space2)`: Sampled textures, followed by storage textures, followed by storage buffers
// - `(s[n], space2)`: Samplers with indices corresponding to the sampled textures
// - `(b[n], space3)`: Uniform buffers
//
// This function compiles a shader from HLSL source code at runtime using `SDL_shadercross`. As this wrapper only uses the Vulkan backend,
// it is only compiled to SPIR-V.
create_graphics_shader_from_hlsl :: proc(dev: device, desc: shader_desc, source_code: string) -> shader {
    tmpmem := mem.begin_arena_temp_memory(&dev.arena)
    defer mem.end_arena_temp_memory(tmpmem)

    assert(desc.stage != .compute, "Cannot create compute shader with `create_graphics_shader`")

    spirv_ptr, spirv_size := compile_shader_to_spirv(dev, desc, source_code)
    defer sdl.free(spirv_ptr)

    return create_graphics_shader_from_spirv(cast(device) dev, desc, mem.byte_slice(spirv_ptr, spirv_size))
}

// Creates a shader to be used when creating a graphics pipeline.
//
// Shader resource bindings must be authored to follow a particular order depending on the shader format. For HLSL shaders,
// use the following register order:
//
// For vertex shaders:
// - `(t[n], space0)`: Sampled textures, followed by storage textures, followed by storage buffers
// - `(s[n], space0)`: Samplers with indices corresponding to the sampled textures
// - `(b[n], space1)`: Uniform buffers
//
// For pixel shaders:
// - `(t[n], space2)`: Sampled textures, followed by storage textures, followed by storage buffers
// - `(s[n], space2)`: Samplers with indices corresponding to the sampled textures
// - `(b[n], space3)`: Uniform buffers
//
// This function creates the shader from pre-compiled SPIR-V code. It still uses `SDL_shadercross` for reflection.
create_graphics_shader_from_spirv :: proc(dev: device, desc: shader_desc, spirv_code: []u8, src_loc := #caller_location) -> shader {
    tmpmem := mem.begin_arena_temp_memory(&dev.arena)
    defer mem.end_arena_temp_memory(tmpmem)
    assert(desc.stage != .compute, "Cannot create compute shader with `create_graphics_shader`")

    spirv_size := cast(uint) len(spirv_code)

    // TODO: gather the rest of the metadata
    meta := shadercross.ReflectGraphicsSPIRV(raw_data(spirv_code), spirv_size)
    check_error_ptr(meta, src_loc)
    defer sdl.free(meta)

    ci := sdl.GPUShaderCreateInfo {
        code_size = spirv_size,
        code = raw_data(spirv_code),
        entrypoint = to_cstr(dev, desc.entry_point),
        format = {.SPIRV},
        stage = cast(sdl.GPUShaderStage) desc.stage,
        num_samplers = meta.resource_info.num_samplers,
        num_storage_textures = meta.resource_info.num_storage_textures,
        num_storage_buffers = meta.resource_info.num_storage_buffers,
        num_uniform_buffers = meta.resource_info.num_uniform_buffers,
    }
    if desc.name != "" {
        ci.props = sdl.CreateProperties()
        name_c := to_cstr(dev, desc.name)
        sdl.SetStringProperty(ci.props, sdl.PROP_GPU_SHADER_CREATE_NAME_STRING, name_c)
    }
    defer if desc.name != "" do sdl.DestroyProperties(ci.props)

    shader := sdl.CreateGPUShader(dev.handle, ci)
    check_error_ptr(shader, src_loc)

    return shader
}

// Frees the given shader as soon as it is safe to do so. You must not reference the shader after calling this function.
release_graphics_shader :: #force_inline proc(dev: device, shader: shader) {
    sdl.ReleaseGPUShader(dev.handle, shader)
}

// Creates a pipeline object to be used in a compute workflow.
//
// Shader resource bindings must be authored to follow a particular order depending on the shader format. For HLSL shaders,
// use the following register order:
// - `(t[n], space0)`: Sampled textures, followed by read-only storage textures, followed by read-only storage buffers
// - `(u[n], space1)`: Read-write storage textures, followed by read-write storage buffers
// - `(b[n], space2)`: Uniform buffers
//
// This function compiles a shader from HLSL source code at runtime using `SDL_shadercross`. As this wrapper only uses the Vulkan backend,
// it is only compiled to SPIR-V.
create_compute_pipeline_from_hlsl :: proc(dev: device, desc: shader_desc, source_code: string) -> compute_pipeline {
    tmpmem := mem.begin_arena_temp_memory(&dev.arena)
    defer mem.end_arena_temp_memory(tmpmem)
    assert(desc.stage != .vertex && desc.stage != .fragment, "Cannot create vertex/fragment shader with `create_compute_pipeline`")

    spirv_ptr, spirv_size := compile_shader_to_spirv(dev, desc, source_code)
    defer sdl.free(spirv_ptr)

    return create_compute_pipeline_from_spirv(cast(device) dev, desc, mem.byte_slice(spirv_ptr, spirv_size))
}

// Creates a pipeline object to be used in a compute workflow.
//
// Shader resource bindings must be authored to follow a particular order depending on the shader format. For HLSL shaders,
// use the following register order:
// - `(t[n], space0)`: Sampled textures, followed by read-only storage textures, followed by read-only storage buffers
// - `(u[n], space1)`: Read-write storage textures, followed by read-write storage buffers
// - `(b[n], space2)`: Uniform buffers
//
// This function creates the shader from pre-compiled SPIR-V code. It still uses `SDL_shadercross` for reflection.
create_compute_pipeline_from_spirv :: proc(dev: device, desc: shader_desc, spirv_code: []u8, src_loc := #caller_location) -> compute_pipeline {
    tmpmem := mem.begin_arena_temp_memory(&dev.arena)
    defer mem.end_arena_temp_memory(tmpmem)
    assert(desc.stage != .vertex && desc.stage != .fragment, "Cannot create vertex/fragment shader with `create_compute_pipeline`")

    spirv_size := cast(uint) len(spirv_code)

    // TODO: gather the rest of the metadata
    meta := shadercross.ReflectComputeSPIRV(raw_data(spirv_code), spirv_size)
    check_error_ptr(meta, src_loc)
    defer sdl.free(meta)

    ci := sdl.GPUComputePipelineCreateInfo {
        code_size = spirv_size,
        code = raw_data(spirv_code),
        entrypoint = to_cstr(dev, desc.entry_point),
        format = {.SPIRV},
        num_samplers = meta.num_samplers,
        num_uniform_buffers = meta.num_uniform_buffers,
        num_readonly_storage_buffers = meta.num_read_only_storage_buffers,
        num_readonly_storage_textures = meta.num_read_only_storage_textures,
        num_readwrite_storage_buffers = meta.num_read_only_storage_buffers,
        num_readwrite_storage_textures = meta.num_read_write_storage_textures,
        threadcount_x = meta.thread_count_x,
        threadcount_y = meta.thread_count_y,
        threadcount_z = meta.thread_count_z,
    }
    if desc.name != "" {
        ci.props = sdl.CreateProperties()
        name_c := to_cstr(dev, desc.name)
        sdl.SetStringProperty(ci.props, sdl.PROP_GPU_COMPUTEPIPELINE_CREATE_NAME_STRING, name_c)
    }
    defer if desc.name != "" do sdl.DestroyProperties(ci.props)

    cpip := sdl.CreateGPUComputePipeline(dev.handle, ci)
    check_error_ptr(cpip, src_loc)

    return cpip
}

// Frees the given compute pipeline as soon as it is safe to do so. You must not reference the compute pipeline after calling this function.
release_compute_pipeline :: #force_inline proc(dev: device, cpip: compute_pipeline) {
    sdl.ReleaseGPUComputePipeline(dev.handle, cpip)
}

// Creates a pipeline object to be used in a graphics workflow.
create_pipeline :: proc(dev: device, desc: pipeline_desc, src_loc := #caller_location) -> pipeline {

    vertex_input_state := sdl.GPUVertexInputState {
        vertex_buffer_descriptions = cast([^]sdl.GPUVertexBufferDescription) raw_data(desc.vertex_input_state.vertex_buffer_descriptions),
        num_vertex_buffers = cast(u32) len(desc.vertex_input_state.vertex_buffer_descriptions),
        vertex_attributes = cast([^]sdl.GPUVertexAttribute) raw_data(desc.vertex_input_state.vertex_attributes),
        num_vertex_attributes = cast(u32) len(desc.vertex_input_state.vertex_attributes),
    }

    depth_stencil_format := desc.target_info.depth_stencil_format.(texture_format) if desc.target_info.depth_stencil_format != nil else .invalid
    target_info := sdl.GPUGraphicsPipelineTargetInfo {
        color_target_descriptions = cast([^]sdl.GPUColorTargetDescription) raw_data(desc.target_info.color_targets),
        num_color_targets = cast(u32) len(desc.target_info.color_targets),
        has_depth_stencil_target = desc.target_info.depth_stencil_format != nil,
        depth_stencil_format = sdl.GPUTextureFormat(depth_stencil_format),
    }

    ci := sdl.GPUGraphicsPipelineCreateInfo {
        vertex_shader = desc.vertex_shader,
        fragment_shader = desc.fragment_shader,
        vertex_input_state = vertex_input_state,
        primitive_type = sdl.GPUPrimitiveType(desc.primitive_type),
        rasterizer_state = transmute(sdl.GPURasterizerState) desc.rasterizer_state,
        multisample_state = transmute(sdl.GPUMultisampleState) desc.multisample_state,
        depth_stencil_state = transmute(sdl.GPUDepthStencilState) desc.depth_stencil_state,
        target_info = target_info,
    }
    if desc.name != "" {
        ci.props = sdl.CreateProperties()
        name_c := to_cstr(dev, desc.name)
        sdl.SetStringProperty(ci.props, sdl.PROP_GPU_GRAPHICSPIPELINE_CREATE_NAME_STRING, name_c)
    }
    defer if desc.name != "" do sdl.DestroyProperties(ci.props)

    pip := sdl.CreateGPUGraphicsPipeline(dev.handle, ci)
    check_error_ptr(pip, src_loc)

    return cast(pipeline) pip
}

// Frees the given graphics pipeline as soon as it is safe to do so. You must not reference the graphics pipeline after calling this function.
release_pipeline :: #force_inline proc(dev: device, pip: pipeline) {
    sdl.ReleaseGPUGraphicsPipeline(dev.handle, pip)
}

acquire_commandbuffer :: proc(dev: device, src_loc := #caller_location) -> commandbuffer {
    handle := sdl.AcquireGPUCommandBuffer(dev.handle)
    check_error_ptr(handle, src_loc)

    cmdbuf := new(_commandbuffer, dev.backing_allocator)
    cmdbuf.handle = handle
    cmdbuf.device_ref = dev
    cmdbuf.vtable = &static_commandbuffer_vtable

    return cmdbuf
}

@(private)
to_cstr :: proc(dev: device, s: string) -> cstring {
    return strings.clone_to_cstring(s, dev.arena_allocator)
}

@(private)
compile_shader_to_spirv :: proc(dev: device, desc: shader_desc, source_code: string) -> (rawptr, uint) {
    tmpmem := mem.begin_arena_temp_memory(&dev.arena)
    defer mem.end_arena_temp_memory(tmpmem)

    // Properties
    props := sdl.CreateProperties()
    defer sdl.DestroyProperties(props)
    sdl.SetBooleanProperty(props, shadercross.SHADER_CULL_UNUSED_BINDINGS_BOOLEAN, true)
    if dev.debug_mode {
        sdl.SetBooleanProperty(props, shadercross.SHADER_DEBUG_ENABLE_BOOLEAN, true)
    }
    if desc.name != "" {
        name_c := to_cstr(dev, desc.name)
        sdl.SetStringProperty(props, shadercross.SHADER_DEBUG_NAME_STRING, name_c)
    }

    source_c := to_cstr(dev, source_code)
    entry_point_c := to_cstr(dev, desc.entry_point)

    info := shadercross.HlslInfo {
        source = source_c,
        shader_stage = cast(shadercross.ShaderStage) desc.stage,
        entry_point = entry_point_c,
        props = props,
    }

    // Compile to SPIR-V
    spirv_size: uint
    spirv_ptr := shadercross.CompileSPIRVFromHLSL(&info, &spirv_size)
    if spirv_ptr == nil {
        log.error("%v", sdl.GetError())
        log.fatal("Could not compile %v shader %q to SPIR-V", desc.stage, desc.name if desc.name != "" else "<unnamed>")
    }
    return spirv_ptr, spirv_size
}

// Determines which shader the bindings are bound to.
bindpoint :: enum u32 {
    vertex,
    fragment,
    compute,
}

// Determines which shader the bindings are bound to. Used in render passes.
graphics_bindpoint :: enum u32 {
    vertex,
    fragment,
}

// Implementation of a command buffer handle. Do not use directly
_commandbuffer :: struct {
    handle: ^sdl.GPUCommandBuffer,
    device_ref: device,
    using vtable: ^commandbuffer_vtable,
}

// An opaque handle representing a command buffer.
//
// Most state is managed via command buffers. When setting state using a command buffer, that state is local to
// the command buffer.
//
// Commands only begin execution on the GPU once `submit()` is called. Once the command buffer is submitted, it
// is no longer valid to use it.
//
// Command buffers are executed in submission order. If you submit command buffer `A` and then command buffer `B`
// all commands in `A` will begin executing before any command in `B` begins executing.
//
// In multi-threading scenarios, you should only access a command buffer on the thread you acquired it from.
commandbuffer :: ^_commandbuffer

// Methods for the `commandbuffer` handle.
commandbuffer_vtable :: struct #all_or_none {
    // Inserts an arbitrary string label into the command buffer callstream. Useful for debugging.
    insert_debug_label: proc(self: commandbuffer, text: string),
    // Begins a debug group with an arbitrary name. Used for denoting groups of calls when viewing the command buffer callstream in a graphics
    // debugging tool.
    //
    // Each call to `push_debug_group` must have a corresponding call to `pop_debug_group`. For best results, if you push a debug group during
    // a pass, always pop it in the same pass.
    push_debug_group: proc(self: commandbuffer, name: string),
    // Ends the most-recently pushed debug group.
    pop_debug_group: proc(self: commandbuffer),

    // Pushes data to a vertex, fragment or compute uniform slot on the command buffer.
    //
    // Subsequent draw calls in this command buffer will use this uniform data.
    //
    // The data being pushed must respect std140 layout conventions. In practical terms this means you must ensure that vec3 and vec4 fields are
    // 16-byte aligned.
    //
    // For detailed information about accessing uniform data from a shader, please refer to `create_graphics_shader`.
    push_uniform_data: proc(self: commandbuffer, bindpoint: bindpoint, slot_idx: u32, data: []u8),
    // Generates mipmaps for the given texture.
    //
    // This function must not be called inside of any pass.
    generate_mipmaps: proc(self: commandbuffer, txt: texture),
    // Blits from a source texture region to a destination texture region.
    //
    // This function must not be called inside of any pass.
    blit_texture: proc(self: commandbuffer, info: blit_info),

    // Submits a command buffer so its commands can be processed on the GPU.
    //
    // It is invalid to use the command buffer after this is called.
    //
    // This must be called from the thread the command buffer was acquired on.
    //
    // All commands in the submission are guaranteed to begin executing before any command in a subsequent submission begins executing.
    submit: proc(self: commandbuffer, src_loc := #caller_location),
    // Submits a command buffer so its commands can be processed on the GPU, and acquires a fence associated with the command buffer.
    //
    // You must release this fence when it is no longer needed or it will cause a leak. It is invalid to use the command buffer after this
    // is called.
    //
    // This must be called from the thread the command buffer was acquired on.
    //
    // All commands in the submission are guaranteed to begin executing before any command in a subsequent submission begins executing.
    submit_and_acquire_fence: proc(self: commandbuffer, src_loc := #caller_location) -> fence,
    // Cancels a command buffer. None of the enqueued commands are executed.
    //
    // It is an error to call this function after a swapchain texture has been acquired.
    //
    // This must be called from the thread the command buffer was acquired on.
    //
    // You must not reference the command buffer after calling this function.
    cancel: proc(self: commandbuffer, src_loc := #caller_location),
    // Acquire a texture to use in presentation.
    //
    // When a swapchain texture is acquired on a command buffer, it will automatically be submitted for presentation when the command buffer is
    // submitted. The swapchain texture should only be referenced by the command buffer used to acquire it.
    //
    // This function will return `nil` as the swapchain texture if too many frames are in flight. This is not an error. This `nil` pointer
    // should not be passed back into SDL. Instead, it should be considered as an indication to wait until the swapchain is available.
    //
    // If you use this function, it is possible to create a situation where many command buffers are allocated while the rendering context waits
    // for the GPU to catch up, which will cause memory usage to grow. You should use `wait_and_acquire_swapchain_texture()` unless you know what
    // you are doing with timing.
    //
    // The swapchain texture is managed by the implementation and must not be freed by the user. You **MUST NOT** call this function from any thread
    // other than the one that created the window.
    //
    // The swapchain texture is write-only and cannot be used as a sampler or for another reading operation.
    acquire_swapchain_texture: proc(self: commandbuffer, window: ^sdl.Window, src_loc := #caller_location) -> (Maybe(texture), m.uvec2),
    // Blocks the thread until a swapchain texture is available to be acquired, and then acquires it.
    //
    // When a swapchain texture is acquired on a command buffer, it will automatically be submitted for presentation when the command buffer is
    // submitted. The swapchain texture should only be referenced by the command buffer used to acquire it. It is an error to call
    // `cancel()` after a swapchain texture is acquired.
    //
    // This function can return `nil` as the swapchain texture handle in certain cases, for example if the window is minimized. This is not an error.
    // You should always make sure to check whether the pointer is `nil` before actually using it.
    //
    // The swapchain texture is managed by the implementation and must not be freed by the user. You **MUST NOT** call this function from any thread other
    // than the one that created the window.
    //
    // The swapchain texture is write-only and cannot be used as a sampler or for another reading operation.
    wait_and_acquire_swapchain_texture: proc(self: commandbuffer, window: ^sdl.Window, src_loc := #caller_location) -> (Maybe(texture), m.uvec2),

    // Begins a render pass on a command buffer.
    //
    // A render pass consists of a set of texture subresources (or depth slices in the 3D texture case) which will be rendered to during the render
    // pass, along with corresponding clear values and load/store operations. All operations related to graphics pipelines must take place inside of
    // a render pass. A default viewport and scissor state are automatically set when this is called. You cannot begin another render pass, or begin
    // a compute pass or copy pass until you have ended the render pass.
    //
    // Using `load_op.load` before any contents have been written to the texture subresource will result in undefined behavior. `load_op.clear` will
    // set the contents of the texture subresource to a single value before any rendering is performed. It's fine to do an empty render pass using
    // `store_op.store` to clear a texture, but in general it's better to think of clearing not as an independent operation but as something that's
    // done as the beginning of a render pass.
    begin_renderpass: proc(self: commandbuffer, color_targets: []color_target, depth_stencil: Maybe(depth_stencil_target) = nil) -> renderpass,
    // Begins a compute pass on a command buffer.
    //
    // A compute pass is defined by a set of texture subresources and buffers that may be written to by compute pipelines. These textures and buffers
    // must have been created with the `{.compute_storage_write}` bit or the `{.compute_storage_simultaneous_readwrite}` bit. If you do not create a
    // texture with {.compute_storage_simultaneous_readwrite}`, you must not read from the texture in the compute pass. All operations related to
    // compute pipelines must take place inside of a compute pass. You must not begin another compute pass, or a render pass or copy pass before
    // ending the compute pass.
    //
    // - **A VERY IMPORTANT NOTE:** Reads and writes in compute passes are NOT implicitly synchronized. This means you may cause data races by both
    // reading and writing a resource region in a compute pass, or by writing multiple times to a resource region. If your compute work depends on
    // reading the completed output from a previous dispatch, you MUST end the current compute pass and begin a new one before you can safely access
    // the data. Otherwise you will receive unexpected results. Reading and writing a texture in the same compute pass is only supported by specific
    // texture formats. Make sure you check the format support!
    begin_computepass: proc(self: commandbuffer, texture_bindings: []storage_texture_rw_binding, buffer_bindings: []storage_buffer_rw_binding) -> computepass,
    // Begins a copy pass on a command buffer.
    //
    // All operations related to copying to or from buffers or textures take place inside a copy pass. You must not begin another copy pass, or a render
    // pass or compute pass before ending the copy pass.
    begin_copypass: proc(self: commandbuffer) -> copypass,
}

// Implementation of a render pass handle. Do not use directly.
_renderpass :: struct {
    handle: ^sdl.GPURenderPass,
    device_ref: device,
    using vtable: ^renderpass_vtable,
}

// A wide pointer opaque handle representing a render pass.
//
// This handle is transient and should not be held or referenced after `end()` is called.
renderpass :: ^_renderpass

// Methods for the `renderpass` handle.
renderpass_vtable :: struct #all_or_none {
    // Sets the current viewport state on a command buffer.
    set_viewport: proc(self: renderpass, viewport: viewport),
    // Sets the current scissor state on a command buffer.
    set_scissor: proc(self: renderpass, scissor: irect),
    // Sets the current blend constants on a command buffer.
    set_blend_constants: proc(self: renderpass, blend_constants: m.vec4),
    // Sets the current stencil reference value on a command buffer.
    set_stencilref: proc(self: renderpass, reference: u8),

    // Binds a graphics pipeline on a render pass to be used in rendering.
    //
    // A graphics pipeline must be bound before making any draw calls.
    bind_pipeline: proc(self: renderpass, pip: pipeline),
    // Binds vertex buffers on a command buffer for use with subsequent draw calls.
    bind_vertex_buffers: proc(self: renderpass, bindings: []buffer_binding, first_slot: u32 = 0),
    // Binds an index buffer on a command buffer for use with subsequent draw calls.
    bind_index_buffer: proc(self: renderpass, binding: buffer_binding, element_size: index_element_size),
    // Binds texture-sampler pairs for use on the vertex or fragment shader.
    //
    // The textures must have been created with the `{.sampler}` usage flag.
    //
    // Be sure your shader is set up according to the requirements documented in `create_graphics_shader()`
    bind_samplers: proc(self: renderpass, bindpoint: graphics_bindpoint, bindings: []texture_sampler_binding, first_slot: u32 = 0),
    // Binds storage textures for use on the vertex or fragment shader.
    //
    // The textures must have been created with the `{.graphics_storage_read}` usage flag.
    //
    // Be sure your shader is set up according to the requirements documented in `create_graphics_shader()`
    bind_storage_textures: proc(self: renderpass, bindpoint: graphics_bindpoint, bindings: []texture, first_slot: u32 = 0),
    // Binds storage buffers for use on the vertex or fragment shader.
    //
    // The buffers must have been created with the `{.graphics_storage_read}` usage flag.
    //
    // Be sure your shader is set up according to the requirements documented in `create_graphics_shader()`
    bind_storage_buffers: proc(self: renderpass, bindpoint: graphics_bindpoint, bindings: []buffer, first_slot: u32 = 0),

    // Draws data using bound graphics state with instancing enabled. You must not call this function before binding a graphics pipeline.
    //
    // - **NOTE:** In the vertex and fragment shaders, `SV_VertexID` and `SV_InstanceID` will be offset by `first_vertex` and `first_instance`
    // respectively. This wouldn't be true for the `"d3d12"` driver, but this wrapper doesn't use that.
    draw: proc(self: renderpass, num_vertices, num_instances: u32, first_vertex, first_instance: u32),
    // Draws data using bound graphics state with an index buffer and instancing enabled. You must not call this function before binding a graphics
    // pipeline.
    //
    // - **NOTE:** In the vertex and fragment shaders, `SV_VertexID` and `SV_InstanceID` will be offset by `first_vertex` and `first_instance`
    // respectively. This wouldn't be true for the `"d3d12"` driver, but this wrapper doesn't use that.
    draw_indexed: proc(self: renderpass, num_indices, num_instances: u32, first_index: u32, vertex_offset: i32, first_instance: u32),
    // Draws data using bound graphics state and with draw parameters set from a buffer. You must not call this function before binding a graphics
    // pipeline.
    //
    // The buffer must consist of tightly-packed draw parameter sets that each match the layout of `indirect_draw_command`.
    draw_indirect: proc(self: renderpass, buf: buffer, offset, draw_count: u32),
    // Draws data using bound graphics state with an index buffer enabled and with draw parameters set from a buffer. You must not call this function
    // before binding a graphics pipeline.
    //
    // The buffer must consist of tightly-packed draw parameter sets that each match the layout of `indexed_indirect_draw_command`.
    draw_indexed_indirect: proc(self: renderpass, buf: buffer, offset, draw_count: u32),

    // Ends the given render pass. All bound graphics state on the render pass command buffer is unset. The render pass handle is now invalid.
    end: proc(self: renderpass),
}

// Implementation of a compute pass handle. Do not use directly.
_computepass :: struct {
    handle: ^sdl.GPUComputePass,
    device_ref: device,
    using vtable: ^computepass_vtable,
}

// A wide pointer opaque handle representing a compute pass.
//
// This handle is transient and should not be held or referenced after `end_computepass` is called.
computepass :: ^_computepass

// Methods for the `computepass` handle.
computepass_vtable :: struct #all_or_none {
    // Binds a compute pipeline on a command buffer for use in compute dispatch.
    bind_pipeline: proc(self: computepass, pip: compute_pipeline),
    // Binds texture-sampler pairs for use on the compute shader.
    //
    // The textures must have been created with the `{.sampler}` usage flag.
    //
    // Be sure your shader is set up according to the requirements documented in `create_compute_pipeline()`
    bind_samplers: proc(self: computepass, bindings: []texture_sampler_binding, first_slot: u32 = 0),
    // Binds storage textures as readonly for use on the compute pipeline.
    //
    // The textures must have been created with the `{.compute_storage_read}` usage flag.
    //
    // Be sure your shader is set up according to the requirements documented in `create_compute_pipeline()`
    bind_storage_textures: proc(self: computepass, bindings: []texture, first_slot: u32 = 0),
    // Binds storage buffers as readonly for use on the compute pipeline.
    //
    // The buffers must have been created with the `{.compute_storage_read}` usage flag.
    //
    // Be sure your shader is set up according to the requirements documented in `create_compute_pipeline()`
    bind_storage_buffers: proc(self: computepass, bindings: []buffer, first_slot: u32 = 0),

    // Dispatches compute work.
    //
    // You must not call this function before binding a compute pipeline.
    //
    // - **A VERY IMPORTANT NOTE:** If you dispatch multiple times in a compute pass, and the dispatches write to the same resource region as each
    // other, there is no guarantee of which order the writes will occur. If the write order matters, you MUST end the compute pass and begin another
    // one.
    dispatch: proc(self: computepass, groupcount_x, groupcount_y, groupcount_z: u32),
    // Dispatches compute work with parameters set from a buffer. You must not call this function before binding a compute pipeline.
    //
    // The buffer layout should match the layout of `indirect_dispatch_command`.
    //
    // - **A VERY IMPORTANT NOTE:** If you dispatch multiple times in a compute pass, and the dispatches write to the same resource region as each
    // other, there is no guarantee of which order the writes will occur. If the write order matters, you MUST end the compute pass and begin another
    // one.
    dispatch_indirect: proc(self: computepass, buf: buffer, offset: u32),

    // Ends the current compute pass. All bound compute state on the command buffer is unset. The compute pass handle is now invalid.
    end: proc(self: computepass),
}

// Implementation of a copy pass handle. Do not use directly
_copypass :: struct {
    handle: ^sdl.GPUCopyPass,
    device_ref: device,
    using vtable: ^copypass_vtable,
}

// A wide pointer opaque handle representing a copy pass.
//
// This handle is transient and should not be held or referenced after SDL_EndGPUCopyPass is called.
copypass :: ^_copypass

// Methods for the `copypass` handle.
copypass_vtable :: struct #all_or_none {
    // Uploads data from a transfer buffer to a texture.
    //
    // The upload occurs on the GPU timeline. You may assume that the upload has finished in subsequent commands.
    //
    // You must align the data in the transfer buffer to a multiple of the texel size of the texture format.
    upload_to_texture: proc(self: copypass, src: texture_transfer_info, dest: texture_region, cycle: bool),
    // Uploads data from a transfer buffer to a buffer.
    //
    // The upload occurs on the GPU timeline. You may assume that the upload has finished in subsequent commands.
    upload_to_buffer: proc(self: copypass, src: transferbuffer_location, dest: buffer_region, cycle: bool),
    // Performs a texture-to-texture copy.
    //
    // This copy occurs on the GPU timeline. You may assume the copy has finished in subsequent commands.
    //
    // This function does not support copying between depth and color textures. For those, copy the texture to a buffer and then to
    // the destination texture.
    copy_texture: proc(self: copypass, src, dest: texture_location, size: m.uvec2, depth: u32, cycle: bool),
    // Performs a buffer-to-buffer copy.
    //
    // This copy occurs on the GPU timeline. You may assume the copy has finished in subsequent commands.
    copy_buffer: proc(self: copypass, src, dest: buffer_location, size: u32, cycle: bool),
    // Copies data from a texture to a transfer buffer on the GPU timeline.
    //
    // This data is not guaranteed to be copied until the command buffer fence is signaled.
    download_from_texture: proc(self: copypass, src: texture_region, dest: texture_transfer_info),
    // Copies data from a buffer to a transfer buffer on the GPU timeline.
    //
    // This data is not guaranteed to be copied until the command buffer fence is signaled.
    download_from_buffer: proc(self: copypass, src: buffer_region, dest: transferbuffer_location),
    // Ends the current copy pass.
    end: proc(self: copypass),
}

// Vtable implementations


@(private)
cmdbuf_insert_debug_label :: proc(self: commandbuffer, text: string) {
    tmpmem := mem.begin_arena_temp_memory(&self.device_ref.arena)
    defer mem.end_arena_temp_memory(tmpmem)
    sdl.InsertGPUDebugLabel(self.handle, to_cstr(self.device_ref, text))
}
@(private)
cmdbuf_push_debug_group :: proc(self: commandbuffer, text: string) {
    tmpmem := mem.begin_arena_temp_memory(&self.device_ref.arena)
    defer mem.end_arena_temp_memory(tmpmem)
    sdl.PushGPUDebugGroup(self.handle, to_cstr(self.device_ref, text))
}
@(private)
cmdbuf_pop_debug_group :: proc(self: commandbuffer) {
    sdl.PopGPUDebugGroup(self.handle)
}
@(private)
cmdbuf_push_uniform_data :: proc(self: commandbuffer, bindpoint: bindpoint, slot_idx: u32, data: []u8) {
    switch bindpoint {
    case .vertex: sdl.PushGPUVertexUniformData(self.handle, slot_idx, raw_data(data), cast(u32) len(data))
    case .fragment: sdl.PushGPUFragmentUniformData(self.handle, slot_idx, raw_data(data), cast(u32) len(data))
    case .compute: sdl.PushGPUComputeUniformData(self.handle, slot_idx, raw_data(data), cast(u32) len(data))
    }
}
@(private)
cmdbuf_generate_mipmaps :: proc(self: commandbuffer, txt: texture) {
    sdl.GenerateMipmapsForGPUTexture(self.handle, txt)
}
@(private)
cmdbuf_blit_texture :: proc(self: commandbuffer, info: blit_info) {
    info := transmute(sdl.GPUBlitInfo) info
    sdl.BlitGPUTexture(self.handle, info)
}
@(private)
cmdbuf_submit :: proc(self: commandbuffer, src_loc := #caller_location) {
    result := sdl.SubmitGPUCommandBuffer(self.handle)
    check_error_bool(result, src_loc)
    free(self, self.device_ref.backing_allocator)
}
@(private)
cmdbuf_submit_and_acquire_fence :: proc(self: commandbuffer, src_loc := #caller_location) -> fence {
    fe := sdl.SubmitGPUCommandBufferAndAcquireFence(self.handle)
    check_error_ptr(fe, src_loc)
    free(self, self.device_ref.backing_allocator)

    return cast(fence) fe
}
@(private)
cmdbuf_cancel :: proc(self: commandbuffer, src_loc := #caller_location) {
    result := sdl.CancelGPUCommandBuffer(self.handle)
    check_error_bool(result, src_loc)
    free(self, self.device_ref.backing_allocator)
}
@(private)
cmdbuf_acquire_swapchain_texture :: proc(self: commandbuffer, window: ^sdl.Window, src_loc := #caller_location) -> (Maybe(texture), m.uvec2) {
    txt: ^sdl.GPUTexture
    w, h: u32
    result := sdl.AcquireGPUSwapchainTexture(self.handle, window, &txt, &w, &h)
    check_error_bool(result, src_loc)

    return cast(texture) txt, m.uvec2 {w, h}
}
@(private)
cmdbuf_wait_and_acquire_swapchain_texture :: proc(self: commandbuffer, window: ^sdl.Window, src_loc := #caller_location) -> (Maybe(texture), m.uvec2) {
    txt: ^sdl.GPUTexture
    w, h: u32
    result := sdl.WaitAndAcquireGPUSwapchainTexture(self.handle, window, &txt, &w, &h)
    check_error_bool(result, src_loc)

    return cast(texture) txt, m.uvec2 {w, h}
}
@(private)
cmdbuf_begin_renderpass :: proc(self: commandbuffer, color_targets: []color_target, depth_stencil: Maybe(depth_stencil_target) = nil) -> renderpass {
    color_target_data := cast([^]sdl.GPUColorTargetInfo) raw_data(color_targets)
    depth_stencil := depth_stencil

    sdl_depth_stencil := transmute(Maybe(^sdl.GPUDepthStencilTargetInfo)) &depth_stencil
    if depth_stencil == nil {
        sdl_depth_stencil = nil
    }

    handle := sdl.BeginGPURenderPass(
        self.handle, color_target_data, cast(u32) len(color_targets),
        sdl_depth_stencil,
    )
    rpass := new(_renderpass, self.device_ref.backing_allocator)
    rpass.handle = handle
    rpass.device_ref = self.device_ref
    rpass.vtable = &static_renderpass_vtable

    return rpass
}
@(private)
cmdbuf_begin_computepass :: proc(self: commandbuffer, texture_bindings: []storage_texture_rw_binding, buffer_bindings: []storage_buffer_rw_binding) -> computepass {
    handle := sdl.BeginGPUComputePass(
        self.handle,
        cast([^]sdl.GPUStorageTextureReadWriteBinding) raw_data(texture_bindings),
        cast(u32) len(texture_bindings),
        cast([^]sdl.GPUStorageBufferReadWriteBinding) raw_data(buffer_bindings),
        cast(u32) len(buffer_bindings),
    )
    cmpass := new(_computepass, self.device_ref.backing_allocator)
    cmpass.handle = handle
    cmpass.device_ref = self.device_ref
    cmpass.vtable = &static_computepass_vtable

    return cmpass
}
@(private)
cmdbuf_begin_copypass :: proc(self: commandbuffer) -> copypass {
    handle := sdl.BeginGPUCopyPass(self.handle)
    cpass := new(_copypass, self.device_ref.backing_allocator)
    cpass.handle = handle
    cpass.device_ref = self.device_ref
    cpass.vtable = &static_copypass_vtable

    return cpass
}

@(rodata)
static_commandbuffer_vtable := commandbuffer_vtable {
    insert_debug_label = cmdbuf_insert_debug_label,
    push_debug_group = cmdbuf_push_debug_group,
    pop_debug_group = cmdbuf_pop_debug_group,

    push_uniform_data = cmdbuf_push_uniform_data,
    generate_mipmaps = cmdbuf_generate_mipmaps,
    blit_texture = cmdbuf_blit_texture,

    submit = cmdbuf_submit,
    submit_and_acquire_fence = cmdbuf_submit_and_acquire_fence,
    cancel = cmdbuf_cancel,
    acquire_swapchain_texture = cmdbuf_acquire_swapchain_texture,
    wait_and_acquire_swapchain_texture = cmdbuf_wait_and_acquire_swapchain_texture,

    begin_renderpass = cmdbuf_begin_renderpass,
    begin_computepass = cmdbuf_begin_computepass,
    begin_copypass = cmdbuf_begin_copypass,
}

@(private)
rpass_set_viewport :: proc(self: renderpass, viewport: viewport) {
    viewport := transmute(sdl.GPUViewport) viewport
    sdl.SetGPUViewport(self.handle, viewport)
}
@(private)
rpass_set_scissor :: proc(self: renderpass, scissor: irect) {
    scissor := transmute(sdl.Rect) scissor
    sdl.SetGPUScissor(self.handle, scissor)
}
@(private)
rpass_set_blend_constants :: proc(self: renderpass, blend_constants: m.vec4) {
    blend_constants := cast(sdl.FColor) blend_constants
    sdl.SetGPUBlendConstants(self.handle, blend_constants)
}
@(private)
rpass_set_stencilref :: proc(self: renderpass, reference: u8) {
    sdl.SetGPUStencilReference(self.handle, reference)
}
@(private)
rpass_bind_pipeline :: proc(self: renderpass, pip: pipeline) {
    sdl.BindGPUGraphicsPipeline(self.handle, pip)
}
@(private)
rpass_bind_vertex_buffers :: proc(self: renderpass, bindings: []buffer_binding, first_slot: u32 = 0) {
    sdl.BindGPUVertexBuffers(
        self.handle, first_slot,
        cast([^]sdl.GPUBufferBinding) raw_data(bindings),
        cast(u32) len(bindings),
    )
}
@(private)
rpass_bind_index_buffer :: proc(self: renderpass, binding: buffer_binding, element_size: index_element_size) {
    sdl.BindGPUIndexBuffer(
        self.handle,
        transmute(sdl.GPUBufferBinding) binding,
        cast(sdl.GPUIndexElementSize) element_size,
    )
}
@(private)
rpass_bind_samplers :: proc(self: renderpass, bindpoint: graphics_bindpoint, bindings: []texture_sampler_binding, first_slot: u32 = 0) {
    switch bindpoint {
    case .vertex:
        sdl.BindGPUVertexSamplers(
            self.handle, first_slot,
            cast([^]sdl.GPUTextureSamplerBinding) raw_data(bindings),
            cast(u32) len(bindings),
        )
    case .fragment:
        sdl.BindGPUFragmentSamplers(
            self.handle, first_slot,
            cast([^]sdl.GPUTextureSamplerBinding) raw_data(bindings),
            cast(u32) len(bindings),
        )
    }
}
@(private)
rpass_bind_storage_textures :: proc(self: renderpass, bindpoint: graphics_bindpoint, bindings: []texture, first_slot: u32 = 0) {
    switch bindpoint {
    case .vertex:
        sdl.BindGPUVertexStorageTextures(
            self.handle, first_slot,
            cast([^]^sdl.GPUTexture) raw_data(bindings),
            cast(u32) len(bindings),
        )
    case .fragment:
        sdl.BindGPUFragmentStorageTextures(
            self.handle, first_slot,
            cast([^]^sdl.GPUTexture) raw_data(bindings),
            cast(u32) len(bindings),
        )
    }
}
@(private)
rpass_bind_storage_buffers :: proc(self: renderpass, bindpoint: graphics_bindpoint, bindings: []buffer, first_slot: u32 = 0) {
    switch bindpoint {
    case .vertex:
        sdl.BindGPUVertexStorageBuffers(
            self.handle, first_slot,
            cast([^]^sdl.GPUBuffer) raw_data(bindings),
            cast(u32) len(bindings),
        )
    case .fragment:
        sdl.BindGPUFragmentStorageBuffers(
            self.handle, first_slot,
            cast([^]^sdl.GPUBuffer) raw_data(bindings),
            cast(u32) len(bindings),
        )
    }
}
@(private)
rpass_draw :: proc(self: renderpass, num_vertices, num_instances: u32, first_vertex, first_instance: u32) {
    sdl.DrawGPUPrimitives(self.handle, num_vertices, num_instances, first_vertex, first_instance)
}
@(private)
rpass_draw_indexed :: proc(self: renderpass, num_indices, num_instances: u32, first_index: u32, vertex_offset: i32, first_instance: u32) {
    sdl.DrawGPUIndexedPrimitives(self.handle, num_indices, num_instances, first_index, vertex_offset, first_instance)
}
@(private)
rpass_draw_indirect :: proc(self: renderpass, buf: buffer, offset, draw_count: u32) {
    sdl.DrawGPUPrimitivesIndirect(self.handle, buf, offset, draw_count)
}
@(private)
rpass_draw_indexed_indirect :: proc(self: renderpass, buf: buffer, offset, draw_count: u32) {
    sdl.DrawGPUIndexedPrimitivesIndirect(self.handle, buf, offset, draw_count)
}
@(private)
rpass_end :: proc(self: renderpass) {
    sdl.EndGPURenderPass(self.handle)
    free(self, self.device_ref.backing_allocator)
}

@(rodata)
static_renderpass_vtable := renderpass_vtable {
    set_viewport = rpass_set_viewport,
    set_scissor = rpass_set_scissor,
    set_blend_constants = rpass_set_blend_constants,
    set_stencilref = rpass_set_stencilref,

    bind_pipeline = rpass_bind_pipeline,
    bind_vertex_buffers = rpass_bind_vertex_buffers,
    bind_index_buffer = rpass_bind_index_buffer,
    bind_samplers = rpass_bind_samplers,
    bind_storage_buffers = rpass_bind_storage_buffers,
    bind_storage_textures = rpass_bind_storage_textures,

    draw = rpass_draw,
    draw_indexed = rpass_draw_indexed,
    draw_indirect = rpass_draw_indirect,
    draw_indexed_indirect = rpass_draw_indexed_indirect,

    end = rpass_end,
}

@(private)
cmpass_bind_pipeline :: proc(self: computepass, pip: compute_pipeline) {
    sdl.BindGPUComputePipeline(self.handle, pip)
}
@(private)
cmpass_bind_samplers :: proc(self: computepass, bindings: []texture_sampler_binding, first_slot: u32 = 0) {
    sdl.BindGPUComputeSamplers(
        self.handle, first_slot,
        cast([^]sdl.GPUTextureSamplerBinding) raw_data(bindings),
        cast(u32) len(bindings),
    )
}
@(private)
cmpass_bind_storage_textures :: proc(self: computepass, bindings: []texture, first_slot: u32 = 0) {
    sdl.BindGPUComputeStorageTextures(
        self.handle, first_slot,
        cast([^]^sdl.GPUTexture) raw_data(bindings),
        cast(u32) len(bindings),
    )
}
@(private)
cmpass_bind_storage_buffers :: proc(self: computepass, bindings: []buffer, first_slot: u32 = 0) {
    sdl.BindGPUComputeStorageBuffers(
        self.handle, first_slot,
        cast([^]^sdl.GPUBuffer) raw_data(bindings),
        cast(u32) len(bindings),
    )
}
@(private)
cmpass_dispatch :: proc(self: computepass, groupcount_x, groupcount_y, groupcount_z: u32) {
    sdl.DispatchGPUCompute(self.handle, groupcount_x, groupcount_y, groupcount_z)
}
@(private)
cmpass_dispatch_indirect :: proc(self: computepass, buf: buffer, offset: u32) {
    sdl.DispatchGPUComputeIndirect(self.handle, buf, offset)
}
@(private)
cmpass_end :: proc(self: computepass) {
    sdl.EndGPUComputePass(self.handle)
    free(self, self.device_ref.backing_allocator)
}

@(rodata)
static_computepass_vtable := computepass_vtable {
    bind_pipeline = cmpass_bind_pipeline,
    bind_samplers = cmpass_bind_samplers,
    bind_storage_textures = cmpass_bind_storage_textures,
    bind_storage_buffers = cmpass_bind_storage_buffers,

    dispatch = cmpass_dispatch,
    dispatch_indirect = cmpass_dispatch_indirect,

    end = cmpass_end,
}

@(private)
cpass_upload_to_texture :: proc(self: copypass, src: texture_transfer_info, dest: texture_region, cycle: bool) {
    sdl.UploadToGPUTexture(self.handle, transmute(sdl.GPUTextureTransferInfo) src, transmute(sdl.GPUTextureRegion) dest, cycle)
}
@(private)
cpass_upload_to_buffer :: proc(self: copypass, src: transferbuffer_location, dest: buffer_region, cycle: bool) {
    sdl.UploadToGPUBuffer(self.handle, transmute(sdl.GPUTransferBufferLocation) src, transmute(sdl.GPUBufferRegion) dest, cycle)
}
@(private)
cpass_copy_texture :: proc(self: copypass, src, dest: texture_location, size: m.uvec2, depth: u32, cycle: bool) {
    sdl.CopyGPUTextureToTexture(
        self.handle,
        transmute(sdl.GPUTextureLocation) src,
        transmute(sdl.GPUTextureLocation) dest,
        size.x, size.y, depth, cycle,
    )
}
@(private)
cpass_copy_buffer :: proc(self: copypass, src, dest: buffer_location, size: u32, cycle: bool) {
    sdl.CopyGPUBufferToBuffer(
        self.handle,
        transmute(sdl.GPUBufferLocation) src,
        transmute(sdl.GPUBufferLocation) dest,
        size, cycle,
    )
}
@(private)
cpass_download_from_texture :: proc(self: copypass, src: texture_region, dest: texture_transfer_info) {
    sdl.DownloadFromGPUTexture(self.handle, transmute(sdl.GPUTextureRegion) src, transmute(sdl.GPUTextureTransferInfo) dest)
}
@(private)
cpass_download_from_buffer :: proc(self: copypass, src: buffer_region, dest: transferbuffer_location) {
    sdl.DownloadFromGPUBuffer(self.handle, transmute(sdl.GPUBufferRegion) src, transmute(sdl.GPUTransferBufferLocation) dest)
}
@(private)
cpass_end :: proc(self: copypass) {
    sdl.EndGPUCopyPass(self.handle)
    free(self, self.device_ref.backing_allocator)
}

@(rodata)
static_copypass_vtable := copypass_vtable {
    upload_to_texture = cpass_upload_to_texture,
    upload_to_buffer = cpass_upload_to_buffer,
    copy_texture = cpass_copy_texture,
    copy_buffer = cpass_copy_buffer,
    download_from_texture = cpass_download_from_texture,
    download_from_buffer = cpass_download_from_buffer,
    end = cpass_end,
}

// Checks an error with a returned pointer value
@(private)
check_error_ptr :: proc(ptr: ^$T, src_loc: runtime.Source_Code_Location) {
    if ptr == nil {
        if default_error_callback(sdl.GetError(), src_loc) == .crash {
            log.fatal("Fatal GPU error. Read logs for more information.")
        }
    }
}

// Checks an error with a returned boolean value
@(private)
check_error_bool :: proc(result: bool, src_loc: runtime.Source_Code_Location) {
    if !result {
        if default_error_callback(sdl.GetError(), src_loc) == .crash {
            log.fatal("Fatal GPU error. Read logs for more information.")
        }
    }
}
