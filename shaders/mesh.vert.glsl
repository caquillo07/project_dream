#version 460

// set 0 = vertex samplers          (BindGPUVertexSamplers)
// set 1 = vertex uniform buffers   (PushGPUVertexUniformData)
// set 2 = fragment samplers        (BindGPUFragmentSamplers)
// set 3 = fragment uniform buffers (PushGPUFragmentUniformData)

layout (location = 0) in vec3 a_position;
layout (location = 1) in vec2 a_uv;
layout (location = 2) in vec3 a_normal;

layout (location = 0) out vec2 v_uv;

layout (set = 1, binding = 0) uniform Uniforms {
    mat4 u_view_proj;
    mat4 u_model;
    vec4 u_tint_color;
};

void main() {
    gl_Position = u_view_proj * u_model * vec4(a_position, 1.0);
    v_uv = a_uv;
}
