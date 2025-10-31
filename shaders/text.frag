#version 450

layout(set = 0, binding = 1) uniform sampler2D atlas;

layout(location = 0) in vec2 frag_uv;
layout(location = 1) in vec4 frag_color;

layout(location = 0) out vec4 out_color;

void main() {
    float alpha = texture(atlas, frag_uv).r;
    out_color = vec4(frag_color.rgb, frag_color.a * alpha);
}
