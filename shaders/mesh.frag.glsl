#version 460

// set 0 = vertex samplers          (BindGPUVertexSamplers)
// set 1 = vertex uniform buffers   (PushGPUVertexUniformData)
// set 2 = fragment samplers        (BindGPUFragmentSamplers)
// set 3 = fragment uniform buffers (PushGPUFragmentUniformData)

layout (location = 0) in vec2 v_uv;

layout (location = 0) out vec4 frag_color;

layout (set = 3, binding = 0) uniform Uniforms {
    mat4 u_view_proj;
    mat4 u_model;
    vec4 u_color_tint;
};

layout (set = 2, binding = 0) uniform sampler2D u_texture;

void main() {
    frag_color = texture(u_texture, v_uv) * u_color_tint;
}
