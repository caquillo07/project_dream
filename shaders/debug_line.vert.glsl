#version 460

layout(set=1, binding=0) uniform Uniforms {
    mat4 view_proj;
};

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec4 in_color;

layout(location = 0) out vec4 frag_color;

void main() {
    gl_Position = view_proj * vec4(in_position, 1.0);
    frag_color = in_color;
}
