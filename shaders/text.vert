#version 450

layout(location = 0) in vec2 in_pos;
layout(location = 1) in vec2 in_glyph_pos;
layout(location = 2) in vec2 in_glyph_size;
layout(location = 3) in vec4 in_atlas_rect;
layout(location = 4) in vec4 in_color;

layout(set = 0, binding = 0) uniform UBO {
    mat4 projection;
} ubo;

layout(location = 0) out vec2 frag_uv;
layout(location = 1) out vec4 frag_color;

void main() {
    vec2 pos = in_glyph_pos + (in_pos * in_glyph_size);
    gl_Position = ubo.projection * vec4(pos, 0.0, 1.0);
    frag_uv = in_atlas_rect.xy + (in_pos * in_atlas_rect.zw);
    frag_color = in_color;
}
