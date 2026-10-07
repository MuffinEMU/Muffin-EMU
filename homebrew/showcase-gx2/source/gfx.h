// Minimal immediate-mode GX2 renderer used by every scene.
//
// One vertex format, one textured+vertex-coloured+fogged shader ("scene"), one
// full-screen pixel-shader showpiece ("fx"), and a single procedurally generated
// atlas that holds the font, a solid-colour cell and a soft glow sprite. Dynamic
// geometry goes through a pool of GX2R vertex buffers, double-buffered per frame.
#pragma once

#include <gx2/sampler.h>
#include <gx2/texture.h>
#include <gx2r/buffer.h>
#include <gx2/surface.h>

#include "app.h"

typedef struct { float x, y, z; float r, g, b, a; float u, v; } Vtx;
typedef struct { float r, g, b, a; } Col;

static inline Col C(float r, float g, float b, float a) { Col c = {r, g, b, a}; return c; }
static inline Col CA(Col c, float a) { c.a = a; return c; }
static inline Col CMUL(Col c, float k) { c.r *= k; c.g *= k; c.b *= k; return c; }
static inline Col CMIX(Col a, Col b, float t)
{
   return C(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
}

typedef struct
{
   GX2RBuffer buf;
   Vtx *p;
   uint32_t n, cap;
   bool locked;
} Batch;

typedef struct { GX2RBuffer buf; uint32_t n; } Mesh;

typedef struct { GX2Texture tex; GX2Sampler samp; } Tex;

typedef struct
{
   GX2ColorBuffer cb;
   GX2DepthBuffer db;
   Tex tex;
   int w, h;
} RTarget;

typedef enum { BLEND_OPAQUE, BLEND_ALPHA, BLEND_ADD } BlendMode;
typedef enum { DEPTH_ON, DEPTH_READ, DEPTH_OFF } DepthMode;

// Pixel-shader block for scene.ps: fog colour (density in .density, 0 = off), fog range,
// brightness and an RGB tint. Both are stored RELATIVE to 1.0 (0 = unchanged) so that a block
// the GPU reads back as all zeros still gives a normal picture, not a black one.
typedef struct
{
   float r, g, b, density;
   float start, end, bright, pad0;
   float tr, tg, tb, pad1;
} Fog;
static inline Fog fog_none(void) { Fog f = {0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0}; return f; }

// ---- math (column-major, matches GLSL mat4 uploads) ------------------------
float fsin(float x);   // never call sinf/cosf directly: GCC folds the pair into
float fcos(float x);   // sincosf, which newlib on this target does not provide
void m4_identity(float m[16]);
void m4_mul(float out[16], const float a[16], const float b[16]);
void m4_translate(float m[16], float x, float y, float z);
void m4_scale(float m[16], float x, float y, float z);
void m4_rot_x(float m[16], float a);
void m4_rot_y(float m[16], float a);
void m4_rot_z(float m[16], float a);
void m4_persp(float m[16], float fovy, float aspect, float zn, float zf);
void m4_ortho_ui(float m[16]);   // 0..VW, 0..VH, y down
void m4_lookat(float m[16], float ex, float ey, float ez, float cx, float cy, float cz);

extern uint32_t g_gfxVerts, g_gfxDraws;   // vertices and draw calls submitted last frame

// ---- lifetime --------------------------------------------------------------
bool gfx_init(void);
void gfx_shutdown(void);
void gfx_begin_frame(void);

// ---- batches and meshes ----------------------------------------------------
Batch *gfx_batch(void);                    // fresh, writable, valid for this frame
Mesh gfx_mesh_from(const Vtx *v, uint32_t n);
void gfx_draw_batch(Batch *b, const float mvp[16], BlendMode bm, DepthMode dm, const Fog *fog);
void gfx_draw_batch_range(Batch *b, uint32_t first, uint32_t count, const float mvp[16],
                          BlendMode bm, DepthMode dm, const Fog *fog);
void gfx_draw_mesh(const Mesh *m, const float mvp[16], BlendMode bm, DepthMode dm, const Fog *fog);
void gfx_use_texture(const Tex *t);        // default is the atlas
const Tex *gfx_atlas(void);
// Three tiny squares, one per pipeline path, drawn on top of everything for a few seconds after
// launch: [orange] no uniforms or textures, [green] pixel uniforms only, [purple] the scene shader.
void gfx_draw_probes(void);
void gfx_draw_fx(float mode, float aspect, float time, float audio, float px, float py, float zoom, float aux);

// ---- render targets --------------------------------------------------------
bool gfx_rt_create(RTarget *rt, int w, int h);
void gfx_rt_begin(RTarget *rt, float r, float g, float b, float a, bool clear);
void gfx_rt_end(RTarget *rt);   // restore the TV target (call inside the TV context)

// ---- 2D (virtual 1280x720, y down) ----------------------------------------
void b_tri(Batch *b, Vtx a, Vtx c, Vtx d);
void b_rect(Batch *b, float x, float y, float w, float h, Col c);
void b_rect_grad(Batch *b, float x, float y, float w, float h, Col top, Col bottom);
void b_rect_gradx(Batch *b, float x, float y, float w, float h, Col left, Col right);
void b_rect_uv(Batch *b, float x, float y, float w, float h, float u0, float v0, float u1, float v1, Col c);
void b_circle(Batch *b, float cx, float cy, float r, Col c, int segs);
void b_ring(Batch *b, float cx, float cy, float r, float thick, Col c, int segs);
void b_line(Batch *b, float x0, float y0, float x1, float y1, float thick, Col c);
void b_glow(Batch *b, float cx, float cy, float r, Col c);
float b_text(Batch *b, float x, float y, float s, Col c, const char *str);
float b_text_shadow(Batch *b, float x, float y, float s, Col c, const char *str);
float b_text_center(Batch *b, float cx, float y, float s, Col c, const char *str);
float text_width(const char *str, float s);
void b_textf(Batch *b, float x, float y, float s, Col c, const char *fmt, ...);

// ---- 3D --------------------------------------------------------------------
void b_quad3(Batch *b, const float p0[3], const float p1[3], const float p2[3], const float p3[3], Col c);
void b_quad3_uv(Batch *b, const float p0[3], const float p1[3], const float p2[3], const float p3[3],
                Col c, float u0, float v0, float u1, float v1);
void b_billboard(Batch *b, const float pos[3], const float right[3], const float up[3], float size, Col c);
void b_box(Batch *b, float cx, float cy, float cz, float sx, float sy, float sz, Col c);
void b_vtx(Batch *b, float x, float y, float z, Col c, float u, float v);

// Atlas coordinates of the solid-white cell, for untextured vertex-coloured geometry.
#define SOLID_U 0.03125f
#define SOLID_V 0.375f

// ---- colour helpers --------------------------------------------------------
Col hsv(float h, float s, float v, float a);
Col pal(float t, float a);   // smooth cosine palette
