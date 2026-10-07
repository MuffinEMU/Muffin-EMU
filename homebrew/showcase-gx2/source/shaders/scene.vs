// scene.vs - the one vertex shader every flat/3D/UI draw in the showcase uses.
// Compiled at CI time by CafeGLSL's glslcompiler (see the workflow); never touched
// by the PPC compiler.

#version 420

layout(std140, binding = 0) uniform uf_scene
{
   mat4 mvp;
};

layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec4 in_color;
layout(location = 2) in vec2 in_uv;

layout(location = 0) out vec4 out_color;
layout(location = 1) out vec3 out_uvd;

void main()
{
   vec4 p = mvp * vec4(in_pos, 1.0);
   gl_Position = p;
   out_color = in_color;
   // z carries view depth (clip w) for the fog in scene.ps
   out_uvd = vec3(in_uv, p.w);
}
