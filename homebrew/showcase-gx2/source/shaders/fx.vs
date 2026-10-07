// fx.vs - full-screen quad for the pixel-shader showpiece (positions are already clip space).

#version 420

layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec4 in_color;
layout(location = 2) in vec2 in_uv;

layout(location = 0) out vec4 out_color;
layout(location = 1) out vec2 out_uv;

void main()
{
   gl_Position = vec4(in_pos.xy, 0.0, 1.0);
   out_color = in_color;
   out_uv = in_uv;
}
