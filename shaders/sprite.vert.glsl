#version 460

layout(location = 0) out vec2 v_uv;

layout(set = 1, binding = 0) uniform SpriteUniforms {
    mat4 u_view_proj;
    vec3 u_camera_right;
    float _pad0;
    vec3 u_camera_up;
    float _pad1;
    vec3 u_sprite_pos;
    float _pad2;
    vec2 u_sprite_size;
    vec2 u_atlas_size;
    vec4 u_sprite_rect;
};

void main() {
    // Generate quad corner from vertex index (triangle strip: 0=BL, 1=BR, 2=TL, 3=TR)
    vec2 corner = vec2(gl_VertexIndex & 1, gl_VertexIndex >> 1);

    // Billboard: offset from sprite position using camera vectors
    // X: centered (-0.5 to 0.5), Y: bottom-anchored (0 to 1)
    vec3 offset = u_camera_right * u_sprite_size.x * (corner.x - 0.5)
                + u_camera_up * u_sprite_size.y * corner.y;

    vec3 world_pos = u_sprite_pos + offset;
    gl_Position = u_view_proj * vec4(world_pos, 1.0);

    // UV from sprite rect (pixel coords -> normalized) with half-pixel inset
    vec2 uv_min = (u_sprite_rect.xy + vec2(0.5)) / u_atlas_size;
    vec2 uv_max = (u_sprite_rect.xy + u_sprite_rect.zw - vec2(0.5)) / u_atlas_size;
    v_uv = mix(uv_min, uv_max, vec2(corner.x, 1.0 - corner.y));
}
