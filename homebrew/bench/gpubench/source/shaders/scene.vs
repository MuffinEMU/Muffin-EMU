// scene.vs - vertex shader for gpubench.rpx's quad-grid scene.
//
// Compiled to a GX2/GFD binary at CI build time by CafeGLSL's glslcompiler
// (see ../../../README.md for why that tool and how it's invoked), then
// baked into scene_gsh.h as a byte array gpubench.c loads with
// WHBGfxLoadGFDShaderGroup(). Not compiled by devkitPPC - this file never
// touches the PPC C compiler, only the PC-hosted GLSL-to-Latte compiler.
//
// CafeGLSL's separable-shader model requires every binding explicit - see
// its README's "Current Limitations". layout(binding/location=N) here is
// not optional decoration, it is load-bearing: gpubench.c looks these
// numbers up by name (attribute names) or relies on them matching exactly
// (uniform block/sampler binding 0, varying locations 0/1 matched against
// scene.ps).

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
