// Immediate-mode GX2 renderer: see gfx.h.

#include "gfx.h"
#include "font.h"
#include "scene_gsh.h"
#include "fx_gsh.h"
#include "diag_gsh.h"

#include <coreinit/cache.h>
#include <coreinit/debug.h>
#include <gx2/clear.h>
#include <gx2/draw.h>
#include <gx2/enum.h>
#include <gx2/mem.h>
#include <gx2/registers.h>
#include <gx2/sampler.h>
#include <gx2/shaders.h>
#include <gx2/utils.h>
#include <gx2r/draw.h>
#include <whb/gfx.h>

#include <ctype.h>
#include <malloc.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// ---------------------------------------------------------------------------
// math
// ---------------------------------------------------------------------------

float __attribute__((noinline)) fsin(float x) { return sinf(x); }
float __attribute__((noinline)) fcos(float x) { return cosf(x); }

void m4_identity(float m[16])
{
   memset(m, 0, sizeof(float) * 16);
   m[0] = m[5] = m[10] = m[15] = 1.0f;
}

void m4_mul(float out[16], const float a[16], const float b[16])
{
   float r[16];
   for (int c = 0; c < 4; c++) {
      for (int row = 0; row < 4; row++) {
         float s = 0.0f;
         for (int k = 0; k < 4; k++) {
            s += a[k * 4 + row] * b[c * 4 + k];
         }
         r[c * 4 + row] = s;
      }
   }
   memcpy(out, r, sizeof(r));
}

void m4_translate(float m[16], float x, float y, float z)
{
   m4_identity(m);
   m[12] = x;
   m[13] = y;
   m[14] = z;
}

void m4_scale(float m[16], float x, float y, float z)
{
   m4_identity(m);
   m[0] = x;
   m[5] = y;
   m[10] = z;
}

void m4_rot_x(float m[16], float a)
{
   m4_identity(m);
   float s = fsin(a), c = fcos(a);
   m[5] = c;
   m[6] = s;
   m[9] = -s;
   m[10] = c;
}

void m4_rot_y(float m[16], float a)
{
   m4_identity(m);
   float s = fsin(a), c = fcos(a);
   m[0] = c;
   m[2] = -s;
   m[8] = s;
   m[10] = c;
}

void m4_rot_z(float m[16], float a)
{
   m4_identity(m);
   float s = fsin(a), c = fcos(a);
   m[0] = c;
   m[1] = s;
   m[4] = -s;
   m[5] = c;
}

void m4_persp(float m[16], float fovy, float aspect, float zn, float zf)
{
   float f = 1.0f / tanf(fovy * 0.5f);
   memset(m, 0, sizeof(float) * 16);
   m[0] = f / aspect;
   m[5] = f;
   m[10] = (zf + zn) / (zn - zf);
   m[11] = -1.0f;
   m[14] = (2.0f * zf * zn) / (zn - zf);
}

void m4_ortho_ui(float m[16])
{
   memset(m, 0, sizeof(float) * 16);
   m[0] = 2.0f / VW;
   m[5] = -2.0f / VH;
   m[10] = -1.0f;
   m[12] = -1.0f;
   m[13] = 1.0f;
   m[15] = 1.0f;
}

void m4_lookat(float m[16], float ex, float ey, float ez, float cx, float cy, float cz)
{
   float fx = cx - ex, fy = cy - ey, fz = cz - ez;
   float fl = sqrtf(fx * fx + fy * fy + fz * fz);
   if (fl < 1e-6f) fl = 1.0f;
   fx /= fl; fy /= fl; fz /= fl;
   // up = +Y
   float sx = fy * 0.0f - fz * 1.0f;
   float sy = fz * 0.0f - fx * 0.0f;
   float sz = fx * 1.0f - fy * 0.0f;
   float sl = sqrtf(sx * sx + sy * sy + sz * sz);
   if (sl < 1e-6f) { sx = 1.0f; sy = 0.0f; sz = 0.0f; sl = 1.0f; }
   sx /= sl; sy /= sl; sz /= sl;
   float ux = sy * fz - sz * fy;
   float uy = sz * fx - sx * fz;
   float uz = sx * fy - sy * fx;
   m4_identity(m);
   m[0] = sx;  m[4] = sy;  m[8]  = sz;
   m[1] = ux;  m[5] = uy;  m[9]  = uz;
   m[2] = -fx; m[6] = -fy; m[10] = -fz;
   m[12] = -(sx * ex + sy * ey + sz * ez);
   m[13] = -(ux * ex + uy * ey + uz * ez);
   m[14] = (fx * ex + fy * ey + fz * ez);
}

Col hsv(float h, float s, float v, float a)
{
   h = h - floorf(h);
   float r = fabsf(h * 6.0f - 3.0f) - 1.0f;
   float g = 2.0f - fabsf(h * 6.0f - 2.0f);
   float b = 2.0f - fabsf(h * 6.0f - 4.0f);
   r = r < 0 ? 0 : (r > 1 ? 1 : r);
   g = g < 0 ? 0 : (g > 1 ? 1 : g);
   b = b < 0 ? 0 : (b > 1 ? 1 : b);
   return C(v * (1.0f + s * (r - 1.0f)), v * (1.0f + s * (g - 1.0f)), v * (1.0f + s * (b - 1.0f)), a);
}

Col pal(float t, float a)
{
   return C(0.5f + 0.5f * fcos(6.28318f * (t + 0.00f)),
            0.5f + 0.5f * fcos(6.28318f * (t + 0.33f)),
            0.5f + 0.5f * fcos(6.28318f * (t + 0.67f)), a);
}

// ---------------------------------------------------------------------------
// state
// ---------------------------------------------------------------------------

#define BATCH_CAP  (32768u)
#define POOL_SIZE  (14)

#define ATLAS_W 128
#define ATLAS_H 96

static WHBGfxShaderGroup gSceneGroup;
static WHBGfxShaderGroup gFxGroup;
static WHBGfxShaderGroup gDiagGroup;
static bool gDiagOk;
static Mesh gProbe[3];
static Batch gPool[2][POOL_SIZE];
static int gSet = 0;
static int gUsed = 0;
static Tex gAtlas;
static const Tex *gCurTex = &gAtlas;
static Mesh gFullscreen;

// GX2 uniform blocks are passed to the GPU by address, not copied, and the GPU may read
// them after the CPU has moved on. Every draw therefore gets its own slot in a
// persistent, 256-byte-aligned ring (double-buffered with the vertex batches).
#define UNI_SLOTS 1024
#define UNI_SLOT_SIZE 256
static uint8_t *gUni[2];
static uint32_t gUniUsed;

static void *uni_copy(const void *src, uint32_t size)
{
   uint8_t *slot = gUni[gSet] + (size_t)(gUniUsed++ % UNI_SLOTS) * UNI_SLOT_SIZE;
   memcpy(slot, src, size);
   GX2Invalidate((GX2InvalidateMode)(GX2_INVALIDATE_MODE_CPU | GX2_INVALIDATE_MODE_UNIFORM_BLOCK), slot, UNI_SLOT_SIZE);
   return slot;
}
uint32_t g_gfxVerts, g_gfxDraws;          // last finished frame
static uint32_t sVerts, sDraws;

static bool init_group(WHBGfxShaderGroup *g, const void *gsh, const char *name)
{
   memset(g, 0, sizeof(*g));
   if (!WHBGfxLoadGFDShaderGroup(g, 0, gsh)) {
      OSReport("showcase: shader group '%s' failed to load\n", name);
      return false;
   }
   WHBGfxInitShaderAttribute(g, "in_pos", 0, offsetof(Vtx, x), GX2_ATTRIB_FORMAT_FLOAT_32_32_32);
   WHBGfxInitShaderAttribute(g, "in_color", 0, offsetof(Vtx, r), GX2_ATTRIB_FORMAT_FLOAT_32_32_32_32);
   WHBGfxInitShaderAttribute(g, "in_uv", 0, offsetof(Vtx, u), GX2_ATTRIB_FORMAT_FLOAT_32_32);
   WHBGfxInitFetchShader(g);
   OSReport("showcase: shader group '%s' ready\n", name);
   return true;
}

static bool create_vbuf(GX2RBuffer *buf, uint32_t count)
{
   memset(buf, 0, sizeof(*buf));
   buf->flags = GX2R_RESOURCE_BIND_VERTEX_BUFFER | GX2R_RESOURCE_USAGE_CPU_READ |
                GX2R_RESOURCE_USAGE_CPU_WRITE | GX2R_RESOURCE_USAGE_GPU_READ;
   buf->elemSize = sizeof(Vtx);
   buf->elemCount = count;
   return GX2RCreateBuffer(buf) != 0;
}

static void texture_from_pixels(Tex *t, int w, int h, uint8_t **pixels, uint32_t *pitch,
                                GX2TexClampMode clamp, GX2TexXYFilterMode filter)
{
   memset(t, 0, sizeof(*t));
   t->tex.surface.dim = GX2_SURFACE_DIM_TEXTURE_2D;
   t->tex.surface.width = w;
   t->tex.surface.height = h;
   t->tex.surface.depth = 1;
   t->tex.surface.mipLevels = 1;
   t->tex.surface.format = GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8;
   t->tex.surface.aa = GX2_AA_MODE1X;
   t->tex.surface.use = GX2_SURFACE_USE_TEXTURE;
   t->tex.surface.tileMode = GX2_TILE_MODE_LINEAR_ALIGNED;
   GX2CalcSurfaceSizeAndAlignment(&t->tex.surface);
   t->tex.surface.image = memalign(t->tex.surface.alignment, t->tex.surface.imageSize);
   memset(t->tex.surface.image, 0, t->tex.surface.imageSize);
   t->tex.viewFirstMip = 0;
   t->tex.viewNumMips = 1;
   t->tex.viewFirstSlice = 0;
   t->tex.viewNumSlices = 1;
   t->tex.compMap = GX2_COMP_MAP(GX2_SQ_SEL_R, GX2_SQ_SEL_G, GX2_SQ_SEL_B, GX2_SQ_SEL_A);
   GX2InitTextureRegs(&t->tex);
   GX2InitSampler(&t->samp, clamp, filter);
   *pixels = (uint8_t *)t->tex.surface.image;
   *pitch = t->tex.surface.pitch;
}

static void build_atlas(void)
{
   uint8_t *px;
   uint32_t pitch;
   texture_from_pixels(&gAtlas, ATLAS_W, ATLAS_H, &px, &pitch, GX2_TEX_CLAMP_MODE_CLAMP, GX2_TEX_XY_FILTER_MODE_LINEAR);

   // everything starts as transparent white so filtering never darkens an edge
   for (int y = 0; y < ATLAS_H; y++) {
      for (int x = 0; x < ATLAS_W; x++) {
         uint8_t *p = px + ((uint32_t)y * pitch + (uint32_t)x) * 4u;
         p[0] = p[1] = p[2] = 255;
         p[3] = 0;
      }
   }

   // glyph cells: 16 per row, 8x8 each, glyph drawn at x+1, y+0
   for (int i = 0; i < 64; i++) {
      int cx = (i % 16) * 8, cy = (i / 16) * 8;
      for (int col = 0; col < 5; col++) {
         unsigned char bits = kFont5x7[i][col];
         for (int row = 0; row < 7; row++) {
            if ((bits >> row) & 1) {
               uint8_t *p = px + ((uint32_t)(cy + row) * pitch + (uint32_t)(cx + 1 + col)) * 4u;
               p[3] = 255;
            }
         }
      }
   }

   // solid cell at (0,32)
   for (int y = 32; y < 40; y++) {
      for (int x = 0; x < 8; x++) {
         px[((uint32_t)y * pitch + (uint32_t)x) * 4u + 3] = 255;
      }
   }

   // soft glow sprite at (0,48), 32x32
   for (int y = 0; y < 32; y++) {
      for (int x = 0; x < 32; x++) {
         float dx = ((float)x + 0.5f - 16.0f) / 16.0f;
         float dy = ((float)y + 0.5f - 16.0f) / 16.0f;
         float d = sqrtf(dx * dx + dy * dy);
         float a = 1.0f - d;
         if (a < 0.0f) a = 0.0f;
         a = a * a * (3.0f - 2.0f * a);   // smoothstep falloff
         px[((uint32_t)(48 + y) * pitch + (uint32_t)x) * 4u + 3] = (uint8_t)(a * 255.0f);
      }
   }

   GX2Invalidate(GX2_INVALIDATE_MODE_CPU_TEXTURE, gAtlas.tex.surface.image, gAtlas.tex.surface.imageSize);
}

bool gfx_init(void)
{
   if (!init_group(&gSceneGroup, kSceneGsh, "scene")) return false;
   if (!init_group(&gFxGroup, kFxGsh, "fx")) return false;
   gDiagOk = init_group(&gDiagGroup, kDiagGsh, "diag");   // probe only: not fatal

   // The shaders use uniform blocks, so GX2 must be in block mode for every draw.
   GX2SetShaderMode(GX2_SHADER_MODE_UNIFORM_BLOCK);

   for (int s = 0; s < 2; s++) {
      gUni[s] = (uint8_t *)memalign(UNI_SLOT_SIZE, (size_t)UNI_SLOTS * UNI_SLOT_SIZE);
      if (!gUni[s]) {
         OSReport("showcase: uniform ring alloc failed\n");
         return false;
      }
      memset(gUni[s], 0, (size_t)UNI_SLOTS * UNI_SLOT_SIZE);
      for (int i = 0; i < POOL_SIZE; i++) {
         Batch *b = &gPool[s][i];
         if (!create_vbuf(&b->buf, BATCH_CAP)) {
            OSReport("showcase: batch buffer alloc failed\n");
            return false;
         }
         b->cap = BATCH_CAP;
      }
   }

   build_atlas();

   static const Vtx quad[6] = {
      {-1, -1, 0, 1, 1, 1, 1, 0, 0}, {1, -1, 0, 1, 1, 1, 1, 1, 0}, {1, 1, 0, 1, 1, 1, 1, 1, 1},
      {-1, -1, 0, 1, 1, 1, 1, 0, 0}, {1, 1, 0, 1, 1, 1, 1, 1, 1}, {-1, 1, 0, 1, 1, 1, 1, 0, 1},
   };
   gFullscreen = gfx_mesh_from(quad, 6);

   // probe squares in clip space, bottom centre-right, above the footer
   static const float px[3][2] = {{0.40f, 0.52f}, {0.56f, 0.68f}, {0.72f, 0.84f}};
   static const Col pc[3] = {{1.0f, 0.55f, 0.0f, 1}, {0.1f, 1.0f, 0.3f, 1}, {0.7f, 0.2f, 1.0f, 1}};
   for (int i = 0; i < 3; i++) {
      float x0 = px[i][0], x1 = px[i][1], y0 = -0.82f, y1 = -0.58f;
      Vtx q6[6] = {
         {x0, y0, 0, pc[i].r, pc[i].g, pc[i].b, 1, SOLID_U, SOLID_V}, {x1, y0, 0, pc[i].r, pc[i].g, pc[i].b, 1, SOLID_U, SOLID_V},
         {x1, y1, 0, pc[i].r, pc[i].g, pc[i].b, 1, SOLID_U, SOLID_V}, {x0, y0, 0, pc[i].r, pc[i].g, pc[i].b, 1, SOLID_U, SOLID_V},
         {x1, y1, 0, pc[i].r, pc[i].g, pc[i].b, 1, SOLID_U, SOLID_V}, {x0, y1, 0, pc[i].r, pc[i].g, pc[i].b, 1, SOLID_U, SOLID_V},
      };
      gProbe[i] = gfx_mesh_from(q6, 6);
   }
   return gFullscreen.n == 6;
}

void gfx_shutdown(void)
{
   for (int s = 0; s < 2; s++) {
      for (int i = 0; i < POOL_SIZE; i++) {
         Batch *b = &gPool[s][i];
         if (b->locked) {
            GX2RUnlockBufferEx(&b->buf, 0);
            b->locked = false;
         }
         GX2RDestroyBufferEx(&b->buf, 0);
      }
   }
   GX2RDestroyBufferEx(&gFullscreen.buf, 0);
   free(gAtlas.tex.surface.image);
   free(gUni[0]);
   free(gUni[1]);
   WHBGfxFreeShaderGroup(&gSceneGroup);
   WHBGfxFreeShaderGroup(&gFxGroup);
}

void gfx_begin_frame(void)
{
   g_gfxVerts = sVerts;
   g_gfxDraws = sDraws;
   sVerts = sDraws = 0;
   gSet ^= 1;
   gUsed = 0;
   gUniUsed = 0;
   for (int i = 0; i < POOL_SIZE; i++) {
      Batch *b = &gPool[gSet][i];
      if (b->locked) {
         GX2RUnlockBufferEx(&b->buf, 0);
         b->locked = false;
      }
      b->n = 0;
      b->p = NULL;
   }
   gCurTex = &gAtlas;
}

Batch *gfx_batch(void)
{
   static Batch sDummy;   // cap 0: every push is ignored
   if (gUsed >= POOL_SIZE) {
      OSReport("showcase: batch pool exhausted\n");
      return &sDummy;
   }
   Batch *b = &gPool[gSet][gUsed++];
   if (!b->locked) {
      b->p = (Vtx *)GX2RLockBufferEx(&b->buf, 0);
      b->locked = true;
      b->n = 0;
      b->cap = b->p ? BATCH_CAP : 0;
   }
   return b;
}

static void seal(Batch *b)
{
   if (b->locked) {
      GX2RUnlockBufferEx(&b->buf, 0);
      b->locked = false;
   }
}

Mesh gfx_mesh_from(const Vtx *v, uint32_t n)
{
   Mesh m;
   memset(&m, 0, sizeof(m));
   if (!create_vbuf(&m.buf, n)) return m;
   Vtx *dst = (Vtx *)GX2RLockBufferEx(&m.buf, 0);
   memcpy(dst, v, sizeof(Vtx) * n);
   GX2RUnlockBufferEx(&m.buf, 0);
   m.n = n;
   return m;
}

void gfx_use_texture(const Tex *t) { gCurTex = t ? t : &gAtlas; }
const Tex *gfx_atlas(void) { return &gAtlas; }

static void apply_state(BlendMode bm, DepthMode dm)
{
   GX2SetCullOnlyControl(GX2_FRONT_FACE_CCW, FALSE, FALSE);
   switch (dm) {
   case DEPTH_ON:   GX2SetDepthOnlyControl(TRUE, TRUE, GX2_COMPARE_FUNC_LEQUAL); break;
   case DEPTH_READ: GX2SetDepthOnlyControl(TRUE, FALSE, GX2_COMPARE_FUNC_LEQUAL); break;
   default:         GX2SetDepthOnlyControl(FALSE, FALSE, GX2_COMPARE_FUNC_ALWAYS); break;
   }
   switch (bm) {
   case BLEND_ALPHA:
      GX2SetBlendControl(GX2_RENDER_TARGET_0,
                         GX2_BLEND_MODE_SRC_ALPHA, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD,
                         TRUE,
                         GX2_BLEND_MODE_ONE, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD);
      GX2SetColorControl(GX2_LOGIC_OP_COPY, 0x01, FALSE, TRUE);
      break;
   case BLEND_ADD:
      GX2SetBlendControl(GX2_RENDER_TARGET_0,
                         GX2_BLEND_MODE_SRC_ALPHA, GX2_BLEND_MODE_ONE, GX2_BLEND_COMBINE_MODE_ADD,
                         TRUE,
                         GX2_BLEND_MODE_ZERO, GX2_BLEND_MODE_ONE, GX2_BLEND_COMBINE_MODE_ADD);
      GX2SetColorControl(GX2_LOGIC_OP_COPY, 0x01, FALSE, TRUE);
      break;
   default:
      GX2SetColorControl(GX2_LOGIC_OP_COPY, 0x00, FALSE, TRUE);
      break;
   }
}

static void bind_scene(const float mvp[16], const Fog *fog)
{
   GX2SetShaderMode(GX2_SHADER_MODE_UNIFORM_BLOCK);
   GX2SetFetchShader(&gSceneGroup.fetchShader);
   GX2SetVertexShader(gSceneGroup.vertexShader);
   GX2SetPixelShader(gSceneGroup.pixelShader);
   GX2SetVertexUniformBlock(0, sizeof(float) * 16, uni_copy(mvp, sizeof(float) * 16));
   Fog f = fog ? *fog : fog_none();
   GX2SetPixelUniformBlock(0, sizeof(Fog), uni_copy(&f, sizeof(Fog)));
   GX2SetPixelTexture(&gCurTex->tex, 0);
   GX2SetPixelSampler(&gCurTex->samp, 0);
}

void gfx_draw_batch_range(Batch *b, uint32_t first, uint32_t count, const float mvp[16],
                          BlendMode bm, DepthMode dm, const Fog *fog)
{
   seal(b);
   if (count == 0 || first >= b->n) return;
   if (first + count > b->n) count = b->n - first;
   bind_scene(mvp, fog);
   apply_state(bm, dm);
   GX2RSetAttributeBuffer(&b->buf, 0, b->buf.elemSize, 0);
   GX2DrawEx(GX2_PRIMITIVE_MODE_TRIANGLES, count, first, 1);
   sVerts += count;
   sDraws++;
}

void gfx_draw_batch(Batch *b, const float mvp[16], BlendMode bm, DepthMode dm, const Fog *fog)
{
   gfx_draw_batch_range(b, 0, b->n, mvp, bm, dm, fog);
}

void gfx_draw_mesh(const Mesh *m, const float mvp[16], BlendMode bm, DepthMode dm, const Fog *fog)
{
   if (!m->n) return;
   bind_scene(mvp, fog);
   apply_state(bm, dm);
   GX2RSetAttributeBuffer((GX2RBuffer *)&m->buf, 0, m->buf.elemSize, 0);
   GX2DrawEx(GX2_PRIMITIVE_MODE_TRIANGLES, m->n, 0, 1);
   sVerts += m->n;
   sDraws++;
}

void gfx_draw_fx(float mode, float aspect, float time, float audio, float px, float py, float zoom, float aux)
{
   float u[8] = {time, aspect, mode, audio, px, py, zoom, aux};
   GX2SetShaderMode(GX2_SHADER_MODE_UNIFORM_BLOCK);
   GX2SetFetchShader(&gFxGroup.fetchShader);
   GX2SetVertexShader(gFxGroup.vertexShader);
   GX2SetPixelShader(gFxGroup.pixelShader);
   GX2SetPixelUniformBlock(0, sizeof(u), uni_copy(u, sizeof(u)));
   apply_state(BLEND_OPAQUE, DEPTH_OFF);
   GX2RSetAttributeBuffer(&gFullscreen.buf, 0, gFullscreen.buf.elemSize, 0);
   GX2DrawEx(GX2_PRIMITIVE_MODE_TRIANGLES, 6, 0, 1);
   sVerts += 6;
   sDraws++;
}

// ---------------------------------------------------------------------------
// render targets
// ---------------------------------------------------------------------------

bool gfx_rt_create(RTarget *rt, int w, int h)
{
   memset(rt, 0, sizeof(*rt));
   rt->w = w;
   rt->h = h;

   rt->cb.surface.use = GX2_SURFACE_USE_TEXTURE | GX2_SURFACE_USE_COLOR_BUFFER;
   rt->cb.surface.dim = GX2_SURFACE_DIM_TEXTURE_2D;
   rt->cb.surface.width = w;
   rt->cb.surface.height = h;
   rt->cb.surface.depth = 1;
   rt->cb.surface.mipLevels = 1;
   rt->cb.surface.format = GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8;
   rt->cb.surface.aa = GX2_AA_MODE1X;
   rt->cb.surface.tileMode = GX2_TILE_MODE_DEFAULT;
   rt->cb.viewNumSlices = 1;
   GX2CalcSurfaceSizeAndAlignment(&rt->cb.surface);
   GX2InitColorBufferRegs(&rt->cb);
   rt->cb.surface.image = memalign(rt->cb.surface.alignment, rt->cb.surface.imageSize);
   if (!rt->cb.surface.image) return false;
   memset(rt->cb.surface.image, 0, rt->cb.surface.imageSize);
   GX2Invalidate(GX2_INVALIDATE_MODE_CPU, rt->cb.surface.image, rt->cb.surface.imageSize);

   rt->db.surface.use = GX2_SURFACE_USE_DEPTH_BUFFER | GX2_SURFACE_USE_TEXTURE;
   rt->db.surface.dim = GX2_SURFACE_DIM_TEXTURE_2D;
   rt->db.surface.width = w;
   rt->db.surface.height = h;
   rt->db.surface.depth = 1;
   rt->db.surface.mipLevels = 1;
   rt->db.surface.format = GX2_SURFACE_FORMAT_FLOAT_R32;
   rt->db.surface.aa = GX2_AA_MODE1X;
   rt->db.surface.tileMode = GX2_TILE_MODE_DEFAULT;
   rt->db.viewNumSlices = 1;
   rt->db.depthClear = 1.0f;
   GX2CalcSurfaceSizeAndAlignment(&rt->db.surface);
   GX2InitDepthBufferRegs(&rt->db);
   rt->db.surface.image = memalign(rt->db.surface.alignment, rt->db.surface.imageSize);
   if (!rt->db.surface.image) return false;
   GX2Invalidate(GX2_INVALIDATE_MODE_CPU, rt->db.surface.image, rt->db.surface.imageSize);

   // a texture view of the colour buffer
   rt->tex.tex.surface = rt->cb.surface;
   rt->tex.tex.viewFirstMip = 0;
   rt->tex.tex.viewNumMips = 1;
   rt->tex.tex.viewFirstSlice = 0;
   rt->tex.tex.viewNumSlices = 1;
   rt->tex.tex.compMap = GX2_COMP_MAP(GX2_SQ_SEL_R, GX2_SQ_SEL_G, GX2_SQ_SEL_B, GX2_SQ_SEL_A);
   GX2InitTextureRegs(&rt->tex.tex);
   GX2InitSampler(&rt->tex.samp, GX2_TEX_CLAMP_MODE_CLAMP, GX2_TEX_XY_FILTER_MODE_LINEAR);
   return true;
}

void gfx_rt_begin(RTarget *rt, float r, float g, float b, float a, bool clear)
{
   if (clear) {
      GX2ClearColor(&rt->cb, r, g, b, a);
      GX2ClearDepthStencilEx(&rt->db, rt->db.depthClear, 0, GX2_CLEAR_FLAGS_DEPTH | GX2_CLEAR_FLAGS_STENCIL);
      GX2SetContextState(WHBGfxGetTVContextState());
   }
   GX2SetColorBuffer(&rt->cb, GX2_RENDER_TARGET_0);
   GX2SetDepthBuffer(&rt->db);
   GX2SetViewport(0, 0, (float)rt->w, (float)rt->h, 0.0f, 1.0f);
   GX2SetScissor(0, 0, (uint32_t)rt->w, (uint32_t)rt->h);
}

void gfx_rt_end(RTarget *rt)
{
   GX2ColorBuffer *cb = WHBGfxGetTVColourBuffer();
   GX2DepthBuffer *db = WHBGfxGetTVDepthBuffer();
   GX2SetColorBuffer(cb, GX2_RENDER_TARGET_0);
   GX2SetDepthBuffer(db);
   GX2SetViewport(0, 0, (float)cb->surface.width, (float)cb->surface.height, 0.0f, 1.0f);
   GX2SetScissor(0, 0, cb->surface.width, cb->surface.height);
   GX2Invalidate(GX2_INVALIDATE_MODE_TEXTURE, rt->cb.surface.image, rt->cb.surface.imageSize);
}

// ---------------------------------------------------------------------------
// geometry helpers
// ---------------------------------------------------------------------------

void b_vtx(Batch *b, float x, float y, float z, Col c, float u, float v)
{
   if (b->n >= b->cap) return;
   Vtx *p = &b->p[b->n++];
   p->x = x; p->y = y; p->z = z;
   p->r = c.r; p->g = c.g; p->b = c.b; p->a = c.a;
   p->u = u; p->v = v;
}

void b_tri(Batch *b, Vtx a, Vtx c, Vtx d)
{
   if (b->n + 3 > b->cap) return;
   b->p[b->n++] = a;
   b->p[b->n++] = c;
   b->p[b->n++] = d;
}

void b_rect_uv(Batch *b, float x, float y, float w, float h, float u0, float v0, float u1, float v1, Col c)
{
   if (b->n + 6 > b->cap) return;
   b_vtx(b, x, y, 0, c, u0, v0);
   b_vtx(b, x + w, y, 0, c, u1, v0);
   b_vtx(b, x + w, y + h, 0, c, u1, v1);
   b_vtx(b, x, y, 0, c, u0, v0);
   b_vtx(b, x + w, y + h, 0, c, u1, v1);
   b_vtx(b, x, y + h, 0, c, u0, v1);
}

void b_rect(Batch *b, float x, float y, float w, float h, Col c)
{
   b_rect_uv(b, x, y, w, h, SOLID_U, SOLID_V, SOLID_U, SOLID_V, c);
}

void b_rect_grad(Batch *b, float x, float y, float w, float h, Col top, Col bottom)
{
   if (b->n + 6 > b->cap) return;
   b_vtx(b, x, y, 0, top, SOLID_U, SOLID_V);
   b_vtx(b, x + w, y, 0, top, SOLID_U, SOLID_V);
   b_vtx(b, x + w, y + h, 0, bottom, SOLID_U, SOLID_V);
   b_vtx(b, x, y, 0, top, SOLID_U, SOLID_V);
   b_vtx(b, x + w, y + h, 0, bottom, SOLID_U, SOLID_V);
   b_vtx(b, x, y + h, 0, bottom, SOLID_U, SOLID_V);
}

void b_rect_gradx(Batch *b, float x, float y, float w, float h, Col left, Col right)
{
   if (b->n + 6 > b->cap) return;
   b_vtx(b, x, y, 0, left, SOLID_U, SOLID_V);
   b_vtx(b, x + w, y, 0, right, SOLID_U, SOLID_V);
   b_vtx(b, x + w, y + h, 0, right, SOLID_U, SOLID_V);
   b_vtx(b, x, y, 0, left, SOLID_U, SOLID_V);
   b_vtx(b, x + w, y + h, 0, right, SOLID_U, SOLID_V);
   b_vtx(b, x, y + h, 0, left, SOLID_U, SOLID_V);
}

void b_circle(Batch *b, float cx, float cy, float r, Col c, int segs)
{
   if (segs < 3) segs = 3;
   float step = 2.0f * PI_F / (float)segs;
   for (int i = 0; i < segs; i++) {
      float a0 = step * (float)i, a1 = step * (float)(i + 1);
      b_vtx(b, cx, cy, 0, c, SOLID_U, SOLID_V);
      b_vtx(b, cx + fcos(a0) * r, cy + fsin(a0) * r, 0, c, SOLID_U, SOLID_V);
      b_vtx(b, cx + fcos(a1) * r, cy + fsin(a1) * r, 0, c, SOLID_U, SOLID_V);
   }
}

void b_ring(Batch *b, float cx, float cy, float r, float thick, Col c, int segs)
{
   if (segs < 3) segs = 3;
   float step = 2.0f * PI_F / (float)segs;
   float ri = r - thick;
   for (int i = 0; i < segs; i++) {
      float a0 = step * (float)i, a1 = step * (float)(i + 1);
      float c0 = fcos(a0), s0 = fsin(a0), c1 = fcos(a1), s1 = fsin(a1);
      b_vtx(b, cx + c0 * r, cy + s0 * r, 0, c, SOLID_U, SOLID_V);
      b_vtx(b, cx + c1 * r, cy + s1 * r, 0, c, SOLID_U, SOLID_V);
      b_vtx(b, cx + c1 * ri, cy + s1 * ri, 0, c, SOLID_U, SOLID_V);
      b_vtx(b, cx + c0 * r, cy + s0 * r, 0, c, SOLID_U, SOLID_V);
      b_vtx(b, cx + c1 * ri, cy + s1 * ri, 0, c, SOLID_U, SOLID_V);
      b_vtx(b, cx + c0 * ri, cy + s0 * ri, 0, c, SOLID_U, SOLID_V);
   }
}

void b_line(Batch *b, float x0, float y0, float x1, float y1, float thick, Col c)
{
   float dx = x1 - x0, dy = y1 - y0;
   float l = sqrtf(dx * dx + dy * dy);
   if (l < 1e-4f) return;
   float nx = -dy / l * thick * 0.5f, ny = dx / l * thick * 0.5f;
   b_vtx(b, x0 + nx, y0 + ny, 0, c, SOLID_U, SOLID_V);
   b_vtx(b, x1 + nx, y1 + ny, 0, c, SOLID_U, SOLID_V);
   b_vtx(b, x1 - nx, y1 - ny, 0, c, SOLID_U, SOLID_V);
   b_vtx(b, x0 + nx, y0 + ny, 0, c, SOLID_U, SOLID_V);
   b_vtx(b, x1 - nx, y1 - ny, 0, c, SOLID_U, SOLID_V);
   b_vtx(b, x0 - nx, y0 - ny, 0, c, SOLID_U, SOLID_V);
}

// glow sprite lives at atlas (0,48)-(32,80)
#define GLOW_U0 (0.5f / ATLAS_W)
#define GLOW_V0 (48.5f / ATLAS_H)
#define GLOW_U1 (31.5f / ATLAS_W)
#define GLOW_V1 (79.5f / ATLAS_H)

void b_glow(Batch *b, float cx, float cy, float r, Col c)
{
   b_rect_uv(b, cx - r, cy - r, r * 2.0f, r * 2.0f, GLOW_U0, GLOW_V0, GLOW_U1, GLOW_V1, c);
}

static int glyph_index(char ch)
{
   unsigned char c = (unsigned char)ch;
   if (c >= 'a' && c <= 'z') c = (unsigned char)(c - 32);
   if (c < 32 || c > 95) c = '?';
   return c - 32;
}

float text_width(const char *str, float s)
{
   float n = 0;
   for (; *str; str++) n += 1.0f;
   return n * 6.0f * s - s;
}

float b_text(Batch *b, float x, float y, float s, Col c, const char *str)
{
   float cx = x;
   for (; *str; str++) {
      if (*str != ' ') {
         int i = glyph_index(*str);
         float u0 = (float)((i % 16) * 8) / ATLAS_W;
         float v0 = (float)((i / 16) * 8) / ATLAS_H;
         b_rect_uv(b, cx - s, y, 8.0f * s, 8.0f * s, u0, v0, u0 + 8.0f / ATLAS_W, v0 + 8.0f / ATLAS_H, c);
      }
      cx += 6.0f * s;
   }
   return cx - x - s;
}

float b_text_shadow(Batch *b, float x, float y, float s, Col c, const char *str)
{
   b_text(b, x + s, y + s, s, C(0, 0, 0, c.a * 0.75f), str);
   return b_text(b, x, y, s, c, str);
}

float b_text_center(Batch *b, float cx, float y, float s, Col c, const char *str)
{
   float w = text_width(str, s);
   b_text_shadow(b, cx - w * 0.5f, y, s, c, str);
   return w;
}

void b_textf(Batch *b, float x, float y, float s, Col c, const char *fmt, ...)
{
   char buf[160];
   va_list ap;
   va_start(ap, fmt);
   vsnprintf(buf, sizeof(buf), fmt, ap);
   va_end(ap);
   b_text_shadow(b, x, y, s, c, buf);
}

void b_quad3_uv(Batch *b, const float p0[3], const float p1[3], const float p2[3], const float p3[3],
                Col c, float u0, float v0, float u1, float v1)
{
   if (b->n + 6 > b->cap) return;
   b_vtx(b, p0[0], p0[1], p0[2], c, u0, v0);
   b_vtx(b, p1[0], p1[1], p1[2], c, u1, v0);
   b_vtx(b, p2[0], p2[1], p2[2], c, u1, v1);
   b_vtx(b, p0[0], p0[1], p0[2], c, u0, v0);
   b_vtx(b, p2[0], p2[1], p2[2], c, u1, v1);
   b_vtx(b, p3[0], p3[1], p3[2], c, u0, v1);
}

void b_quad3(Batch *b, const float p0[3], const float p1[3], const float p2[3], const float p3[3], Col c)
{
   b_quad3_uv(b, p0, p1, p2, p3, c, SOLID_U, SOLID_V, SOLID_U, SOLID_V);
}

void b_billboard(Batch *b, const float pos[3], const float right[3], const float up[3], float size, Col c)
{
   float rx = right[0] * size, ry = right[1] * size, rz = right[2] * size;
   float ux = up[0] * size, uy = up[1] * size, uz = up[2] * size;
   float p0[3] = {pos[0] - rx + ux, pos[1] - ry + uy, pos[2] - rz + uz};
   float p1[3] = {pos[0] + rx + ux, pos[1] + ry + uy, pos[2] + rz + uz};
   float p2[3] = {pos[0] + rx - ux, pos[1] + ry - uy, pos[2] + rz - uz};
   float p3[3] = {pos[0] - rx - ux, pos[1] - ry - uy, pos[2] - rz - uz};
   b_quad3_uv(b, p0, p1, p2, p3, c, GLOW_U0, GLOW_V0, GLOW_U1, GLOW_V1);
}

void b_box(Batch *b, float cx, float cy, float cz, float sx, float sy, float sz, Col c)
{
   float x0 = cx - sx, x1 = cx + sx, y0 = cy - sy, y1 = cy + sy, z0 = cz - sz, z1 = cz + sz;
   float v[8][3] = {{x0, y0, z0}, {x1, y0, z0}, {x1, y1, z0}, {x0, y1, z0},
                    {x0, y0, z1}, {x1, y0, z1}, {x1, y1, z1}, {x0, y1, z1}};
   // faces shaded by a fixed directional light baked into the vertex colour
   b_quad3(b, v[4], v[5], v[6], v[7], CMUL(c, 0.85f));   // +z
   b_quad3(b, v[1], v[0], v[3], v[2], CMUL(c, 0.55f));   // -z
   b_quad3(b, v[5], v[1], v[2], v[6], CMUL(c, 0.70f));   // +x
   b_quad3(b, v[0], v[4], v[7], v[3], CMUL(c, 0.62f));   // -x
   b_quad3(b, v[7], v[6], v[2], v[3], CMUL(c, 1.00f));   // +y
   b_quad3(b, v[0], v[1], v[5], v[4], CMUL(c, 0.40f));   // -y
}

// ---------------------------------------------------------------------------
// startup probe: tells which pipeline path is broken if the screen stays black
// ---------------------------------------------------------------------------

void gfx_draw_probes(void)
{
   // 1. no uniforms, no textures
   if (gDiagOk && gProbe[0].n) {
      GX2SetShaderMode(GX2_SHADER_MODE_UNIFORM_BLOCK);
      GX2SetFetchShader(&gDiagGroup.fetchShader);
      GX2SetVertexShader(gDiagGroup.vertexShader);
      GX2SetPixelShader(gDiagGroup.pixelShader);
      apply_state(BLEND_OPAQUE, DEPTH_OFF);
      GX2RSetAttributeBuffer(&gProbe[0].buf, 0, gProbe[0].buf.elemSize, 0);
      GX2DrawEx(GX2_PRIMITIVE_MODE_TRIANGLES, 6, 0, 1);
   }
   // 2. the fx shader pair, pixel uniform block only, constant output (mode 9)
   if (gProbe[1].n) {
      float u[8] = {0, 1, 9.0f, 0, 0, 0, 1, 0};
      GX2SetShaderMode(GX2_SHADER_MODE_UNIFORM_BLOCK);
      GX2SetFetchShader(&gFxGroup.fetchShader);
      GX2SetVertexShader(gFxGroup.vertexShader);
      GX2SetPixelShader(gFxGroup.pixelShader);
      GX2SetPixelUniformBlock(0, sizeof(u), uni_copy(u, sizeof(u)));
      apply_state(BLEND_OPAQUE, DEPTH_OFF);
      GX2RSetAttributeBuffer(&gProbe[1].buf, 0, gProbe[1].buf.elemSize, 0);
      GX2DrawEx(GX2_PRIMITIVE_MODE_TRIANGLES, 6, 0, 1);
   }
   // 3. the scene shader: vertex uniform block + pixel uniform block + texture
   if (gProbe[2].n) {
      float id[16];
      m4_identity(id);
      gfx_use_texture(NULL);
      gfx_draw_mesh(&gProbe[2], id, BLEND_OPAQUE, DEPTH_OFF, NULL);
   }
}
