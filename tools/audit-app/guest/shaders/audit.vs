// audit.vs - vertex shader of the audit guest. One shader draws everything: screen-space quads with a
// colour and a texture coordinate, through an identity matrix (audit.c passes clip-space positions).
//
// Compiled to a GX2/GFD binary at build time by CafeGLSL's glslcompiler (see .github/workflows/build-audit-ipa.yml) and
// embedded in audit.rpx as audit_shader_gsh.h. Same shader model as homebrew/bench/gpubench/source/shaders/scene.vs,
// which the bench already builds and runs on this toolchain: every binding and location is explicit.

#version 420

layout(binding = 0) uniform uf_scene
{
   mat4 mvp;
};

layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec4 in_color;
layout(location = 2) in vec2 in_uv;

layout(location = 0) out vec4 out_color;
layout(location = 1) out vec2 out_uv;

void main()
{
   gl_Position = mvp * vec4(in_pos, 1.0);
   out_color = in_color;
   out_uv = in_uv;
}
