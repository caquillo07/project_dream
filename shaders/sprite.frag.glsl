#version 460

layout(location = 0) in vec2 v_uv;

layout(location = 0) out vec4 frag_color;

layout(set = 2, binding = 0) uniform sampler2D u_texture;

void main() {
    vec4 tex_color = texture(u_texture, v_uv);

    // Alpha test — hard cutoff for pixel art
    if (tex_color.a < 0.5) {
        discard;
    }

    frag_color = tex_color;
}
