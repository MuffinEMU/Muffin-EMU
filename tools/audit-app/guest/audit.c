// audit.rpx - the MuffinEMU Audit guest program (phase 1).
//
// A real Wii U homebrew program that drives the emulator through the same path a game does
// (GX2 -> Latte -> renderer, AX -> audio, VPAD -> input, coreinit timing) and talks to the Audit
// app over the probe protocol in audit_protocol.h. The app tells it which test to run; the guest
// draws pathological, deterministic scenes; at each CHECKPOINT it holds the scene still so the
// app can read the frame back from the renderer and compare it with what the scene is meant to
// look like.
//
// This file: mailbox, logging, parameters, the TV/GamePad frame loop, the drawing and texture
// helpers. The tests themselves are in tests_render.c and tests_av.c.

#include "audit_internal.h"
#include "audit_shader_gsh.h" // generated at build time from shaders/audit.{vs,ps}: kAuditShaderGsh[], kAuditShaderGshSize

#include <coreinit/thread.h>
#include <gx2/event.h>
#include <vpad/input.h>
#include <whb/proc.h>

#include <malloc.h>
#include <stddef.h>
#include <stdio.h>

#define AUDIT_BUILD "phase1"

// How long a checkpoint waits for the host before the guest gives up on it and carries on.
#define CHECKPOINT_TIMEOUT_MS 30000u

// With no Audit app attached (see the autorun sequence in main) the guest plays its tests on its own after this long.
#define AUTORUN_START_MS 8000u
#define AUTORUN_HOLD_MS  1500u

// ---------------------------------------------------------------------------------------------
// Mailbox

static volatile uint8_t gMb[AUDIT_MAILBOX_SIZE] __attribute__((aligned(64)));

static inline volatile uint32_t *MbWord(uint32_t off)
{
   return (volatile uint32_t *)(gMb + off);
}

void MbSet(uint32_t off, uint32_t v)
{
   *MbWord(off) = v;
}

uint32_t MbGet(uint32_t off)
{
   return *MbWord(off);
}

static void MbStr(uint32_t off, uint32_t cap, const char *s)
{
   volatile char *d = (volatile char *)(gMb + off);
   uint32_t i       = 0;
   for (; s && s[i] && i + 1 < cap; i++) {
      d[i] = s[i];
   }
   for (; i < cap; i++) {
      d[i] = 0;
   }
}

static void MbTouch(void)
{
   __sync_synchronize();
   MbSet(AUDIT_MB_GUEST_SEQ, MbGet(AUDIT_MB_GUEST_SEQ) + 1);
}

static uint32_t gFrames = 0;

uint32_t FramesPresented(void)
{
   return gFrames;
}

// ---------------------------------------------------------------------------------------------
// Logging, parameters, small utilities

void LogPhase(Ctx *ctx, const char *name)
{
   OSReport(AUDIT_LOG_PREFIX " PHASE %s %u %s\n", ctx->testId, (unsigned)ctx->token, name);
}

void SetMessage(const char *fmt, ...)
{
   char buf[AUDIT_MESSAGE_LEN];
   va_list ap;
   va_start(ap, fmt);
   vsnprintf(buf, sizeof(buf), fmt, ap);
   va_end(ap);
   MbStr(AUDIT_MB_MESSAGE, AUDIT_MESSAGE_LEN, buf);
}

void LogNote(Ctx *ctx, const char *fmt, ...)
{
   char buf[160];
   va_list ap;
   va_start(ap, fmt);
   vsnprintf(buf, sizeof(buf), fmt, ap);
   va_end(ap);
   OSReport(AUDIT_LOG_PREFIX " NOTE %s %u %s\n", ctx->testId, (unsigned)ctx->token, buf);
}

void LogSelf(Ctx *ctx, const char *verdict, const char *fmt, ...)
{
   char buf[160];
   va_list ap;
   va_start(ap, fmt);
   vsnprintf(buf, sizeof(buf), fmt, ap);
   va_end(ap);
   if (strcmp(verdict, "fail") == 0) {
      ctx->errors++;
      MbSet(AUDIT_MB_GUEST_ERRORS, ctx->errors);
      SetMessage("%s", buf);
   }
   OSReport(AUDIT_LOG_PREFIX " SELF %s %u %s %s\n", ctx->testId, (unsigned)ctx->token, verdict, buf);
}

void Fold(Ctx *ctx, uint32_t value)
{
   ctx->checksum = (ctx->checksum ^ value) * 16777619u;
}

uint32_t Rand32(uint32_t *state)
{
   uint32_t x = *state ? *state : 0x9E3779B9u;
   x ^= x << 13;
   x ^= x >> 17;
   x ^= x << 5;
   *state = x;
   return x;
}

// Finds "key=" at the start of params or after a ';'. Returns a pointer to the value or NULL.
static const char *FindParam(const Ctx *ctx, const char *key)
{
   size_t klen     = strlen(key);
   const char *p   = ctx->params;
   while (*p) {
      if (strncmp(p, key, klen) == 0 && p[klen] == '=') {
         return p + klen + 1;
      }
      const char *semi = strchr(p, ';');
      if (!semi) {
         break;
      }
      p = semi + 1;
   }
   return NULL;
}

int32_t ParamInt(const Ctx *ctx, const char *key, int32_t def)
{
   const char *v = FindParam(ctx, key);
   return v ? (int32_t)strtol(v, NULL, 10) : def;
}

BOOL ParamStr(const Ctx *ctx, const char *key, char *out, uint32_t outSize)
{
   const char *v = FindParam(ctx, key);
   if (!v || outSize == 0) {
      return FALSE;
   }
   uint32_t i = 0;
   while (v[i] && v[i] != ';' && i + 1 < outSize) {
      out[i] = v[i];
      i++;
   }
   out[i] = 0;
   return TRUE;
}

// ---------------------------------------------------------------------------------------------
// Host commands

static BOOL gContinueSeen = FALSE;
static BOOL gHostSeen     = FALSE; // any command has ever arrived from an Audit app
static BOOL gAutorun      = FALSE; // running the built-in sequence with no host attached
static BOOL gExitRequested = FALSE;
static BOOL gRunPending    = FALSE;
static Ctx gPendingRun;

BOOL PollHost(Ctx *ctx)
{
   uint32_t seq = MbGet(AUDIT_MB_CMD_SEQ);
   if (seq != 0) {
      gHostSeen = TRUE;
   }
   if (seq == MbGet(AUDIT_MB_ACK_SEQ)) {
      return FALSE;
   }
   __sync_synchronize();
   uint32_t cmd = MbGet(AUDIT_MB_CMD);
   BOOL cont    = FALSE;

   switch (cmd) {
   case AUDIT_CMD_CONTINUE:
      gContinueSeen = TRUE;
      cont          = TRUE;
      break;
   case AUDIT_CMD_ABORT:
      if (ctx) {
         ctx->aborted = TRUE;
      }
      break;
   case AUDIT_CMD_EXIT:
      gExitRequested = TRUE;
      break;
   case AUDIT_CMD_PING:
      MbSet(AUDIT_MB_PING_ECHO, seq);
      break;
   case AUDIT_CMD_RUN:
      if (!ctx && !gRunPending) {
         memset(&gPendingRun, 0, sizeof(gPendingRun));
         const volatile char *id     = (const volatile char *)(gMb + AUDIT_MB_CMD_TEST_ID);
         const volatile char *params = (const volatile char *)(gMb + AUDIT_MB_CMD_PARAMS);
         for (uint32_t i = 0; i + 1 < AUDIT_NAME_LEN && id[i]; i++) {
            gPendingRun.testId[i] = id[i];
         }
         for (uint32_t i = 0; i + 1 < AUDIT_PARAMS_LEN && params[i]; i++) {
            gPendingRun.params[i] = params[i];
         }
         gPendingRun.token      = MbGet(AUDIT_MB_CMD_RUN_TOKEN);
         gPendingRun.seed       = MbGet(AUDIT_MB_CMD_SEED);
         gPendingRun.durationMs = MbGet(AUDIT_MB_CMD_DURATION_MS);
         gRunPending            = TRUE;
      } else {
         OSReport(AUDIT_LOG_PREFIX " NOTE - 0 RUN ignored while busy\n");
      }
      break;
   default:
      break;
   }
   MbSet(AUDIT_MB_ACK_SEQ, seq);
   return cont;
}

BOOL ConsumeContinue(void)
{
   BOOL v        = gContinueSeen;
   gContinueSeen = FALSE;
   return v;
}

// ---------------------------------------------------------------------------------------------
// Shader, vertex pool and the default sampler/texture

typedef struct Vertex
{
   float pos[3];
   float color[4];
   float uv[2];
} Vertex;

#define POOL_VERTS (16384u)

static WHBGfxShaderGroup gGroup;
static Vertex *gPool       = NULL;
static uint32_t gCursor    = 0;
static GX2Sampler gSamplerPoint;
static GX2Sampler gSamplerLinear;
static Tex gWhite;
static BOOL gGfxReady = FALSE;

static const float kIdentity[16] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};

void SetBlend(const BlendState *b)
{
   GX2SetBlendControl(GX2_RENDER_TARGET_0, b->colorSrc, b->colorDst, b->colorCombine, TRUE, b->alphaSrc,
                      b->alphaDst, b->alphaCombine);
   GX2SetColorControl(GX2_LOGIC_OP_COPY, b->enable ? 0x01 : 0x00, FALSE, TRUE);
}

void SetBlendStandard(void)
{
   BlendState b = {TRUE,
                   GX2_BLEND_MODE_SRC_ALPHA, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD,
                   GX2_BLEND_MODE_SRC_ALPHA, GX2_BLEND_MODE_INV_SRC_ALPHA, GX2_BLEND_COMBINE_MODE_ADD};
   SetBlend(&b);
}

void SetBlendOff(void)
{
   BlendState b = {FALSE,
                   GX2_BLEND_MODE_ONE, GX2_BLEND_MODE_ZERO, GX2_BLEND_COMBINE_MODE_ADD,
                   GX2_BLEND_MODE_ONE, GX2_BLEND_MODE_ZERO, GX2_BLEND_COMBINE_MODE_ADD};
   SetBlend(&b);
}

void SetDepth(BOOL test, BOOL write, GX2CompareFunction func)
{
   GX2SetDepthOnlyControl(test, write, func);
}

void BindTexture(const GX2Texture *tex, BOOL linear)
{
   GX2SetPixelTexture(tex, 0);
   GX2SetPixelSampler(linear ? &gSamplerLinear : &gSamplerPoint, 0);
}

void BindWhite(void)
{
   BindTexture(&gWhite.tex, FALSE);
}

void ApplyDefaultState(void)
{
   GX2SetFetchShader(&gGroup.fetchShader);
   GX2SetVertexShader(gGroup.vertexShader);
   GX2SetPixelShader(gGroup.pixelShader);
   GX2SetVertexUniformBlock(0, sizeof(kIdentity), kIdentity);
   GX2SetAttribBuffer(0, POOL_VERTS * sizeof(Vertex), sizeof(Vertex), gPool);
   SetBlendStandard();
   SetDepth(FALSE, FALSE, GX2_COMPARE_FUNC_ALWAYS);
   BindWhite();
}

static void EmitQuad(float x, float y, float w, float h, float z, const float c[4], float u0, float v0, float u1,
                     float v1)
{
   if (gCursor + 6 > POOL_VERTS) {
      return; // out of vertex space for this frame; the scene is simply drawn incomplete and the host sees it
   }
   float x0 = x * 2.0f - 1.0f;
   float x1 = (x + w) * 2.0f - 1.0f;
   float y0 = 1.0f - y * 2.0f;
   float y1 = 1.0f - (y + h) * 2.0f;

   Vertex *v = &gPool[gCursor];
   Vertex a  = {{x0, y0, z}, {c[0], c[1], c[2], c[3]}, {u0, v0}};
   Vertex b  = {{x1, y0, z}, {c[0], c[1], c[2], c[3]}, {u1, v0}};
   Vertex d  = {{x1, y1, z}, {c[0], c[1], c[2], c[3]}, {u1, v1}};
   Vertex e  = {{x0, y1, z}, {c[0], c[1], c[2], c[3]}, {u0, v1}};
   v[0]      = a;
   v[1]      = b;
   v[2]      = d;
   v[3]      = a;
   v[4]      = d;
   v[5]      = e;
   GX2Invalidate(GX2_INVALIDATE_MODE_CPU_ATTRIBUTE_BUFFER, v, 6 * sizeof(Vertex));
   GX2DrawEx(GX2_PRIMITIVE_MODE_TRIANGLES, 6, gCursor, 1);
   gCursor += 6;
}

void DrawRect(float x, float y, float w, float h, float z, float r, float g, float b, float a)
{
   float c[4] = {r, g, b, a};
   BindWhite();
   EmitQuad(x, y, w, h, z, c, 0, 0, 1, 1);
}

void DrawTexRect(float x, float y, float w, float h, float z, float r, float g, float b, float a)
{
   float c[4] = {r, g, b, a};
   EmitQuad(x, y, w, h, z, c, 0, 0, 1, 1);
}

void DrawTexRectUV(float x, float y, float w, float h, float z, float u0, float v0, float u1, float v1)
{
   float c[4] = {1, 1, 1, 1};
   EmitQuad(x, y, w, h, z, c, u0, v0, u1, v1);
}

// ---------------------------------------------------------------------------------------------
// Textures

static BOOL IsBC(GX2SurfaceFormat f)
{
   switch (f) {
   case GX2_SURFACE_FORMAT_UNORM_BC1:
   case GX2_SURFACE_FORMAT_UNORM_BC2:
   case GX2_SURFACE_FORMAT_UNORM_BC3:
   case GX2_SURFACE_FORMAT_UNORM_BC4:
   case GX2_SURFACE_FORMAT_UNORM_BC5:
   case GX2_SURFACE_FORMAT_SRGB_BC1:
   case GX2_SURFACE_FORMAT_SRGB_BC2:
   case GX2_SURFACE_FORMAT_SRGB_BC3:
      return TRUE;
   default:
      return FALSE;
   }
}

// Bytes of one texel, or of one 4x4 block for the compressed formats.
static uint32_t ElementBytes(GX2SurfaceFormat f)
{
   switch (f) {
   case GX2_SURFACE_FORMAT_UNORM_BC1:
   case GX2_SURFACE_FORMAT_SRGB_BC1:
   case GX2_SURFACE_FORMAT_UNORM_BC4:
      return 8;
   case GX2_SURFACE_FORMAT_UNORM_BC2:
   case GX2_SURFACE_FORMAT_UNORM_BC3:
   case GX2_SURFACE_FORMAT_UNORM_BC5:
   case GX2_SURFACE_FORMAT_SRGB_BC2:
   case GX2_SURFACE_FORMAT_SRGB_BC3:
      return 16;
   case GX2_SURFACE_FORMAT_FLOAT_R16_G16_B16_A16:
   case GX2_SURFACE_FORMAT_UNORM_R16_G16_B16_A16:
      return 8;
   case GX2_SURFACE_FORMAT_FLOAT_R32_G32_B32_A32:
      return 16;
   case GX2_SURFACE_FORMAT_UNORM_R8:
      return 1;
   case GX2_SURFACE_FORMAT_UNORM_R8_G8:
   case GX2_SURFACE_FORMAT_UNORM_R5_G6_B5:
   case GX2_SURFACE_FORMAT_UNORM_R5_G5_B5_A1:
   case GX2_SURFACE_FORMAT_UNORM_R4_G4_B4_A4:
   case GX2_SURFACE_FORMAT_UNORM_R16:
      return 2;
   default:
      return 4;
   }
}

uint32_t TexRowBytes(const Tex *t)
{
   GX2SurfaceFormat f = t->tex.surface.format;
   if (IsBC(f)) {
      return (t->tex.surface.pitch / 4u) * ElementBytes(f);
   }
   return t->tex.surface.pitch * ElementBytes(f);
}

uint32_t TexRowCount(const Tex *t)
{
   GX2SurfaceFormat f = t->tex.surface.format;
   return IsBC(f) ? (t->tex.surface.height + 3u) / 4u : t->tex.surface.height;
}

BOOL TexCreate(Tex *t, GX2SurfaceFormat format, uint32_t width, uint32_t height)
{
   memset(t, 0, sizeof(*t));
   GX2Surface *s = &t->tex.surface;
   s->dim        = GX2_SURFACE_DIM_TEXTURE_2D;
   s->width      = width;
   s->height     = height;
   s->depth      = 1;
   s->mipLevels  = 1;
   s->format     = format;
   s->aa         = GX2_AA_MODE1X;
   s->use        = GX2_SURFACE_USE_TEXTURE;
   s->tileMode   = GX2_TILE_MODE_LINEAR_ALIGNED;
   GX2CalcSurfaceSizeAndAlignment(s);

   t->image = memalign(s->alignment ? s->alignment : 0x100, s->imageSize);
   if (!t->image) {
      return FALSE;
   }
   memset(t->image, 0, s->imageSize);
   s->image = t->image;

   t->tex.viewFirstMip   = 0;
   t->tex.viewNumMips    = 1;
   t->tex.viewFirstSlice = 0;
   t->tex.viewNumSlices  = 1;
   t->tex.compMap        = GX2_COMP_MAP(GX2_SQ_SEL_R, GX2_SQ_SEL_G, GX2_SQ_SEL_B, GX2_SQ_SEL_A);
   GX2InitTextureRegs(&t->tex);
   return TRUE;
}

void TexUploaded(Tex *t)
{
   GX2Invalidate(GX2_INVALIDATE_MODE_CPU_TEXTURE, t->image, t->tex.surface.imageSize);
}

void TexDestroy(Tex *t)
{
   if (t->image) {
      free(t->image);
   }
   if (t->mips) {
      free(t->mips);
   }
   memset(t, 0, sizeof(*t));
}

// ---------------------------------------------------------------------------------------------
// Render targets

BOOL RTCreate(RT *rt, uint32_t width, uint32_t height, uint32_t mipLevels, GX2SurfaceFormat format,
              GX2SurfaceFormat depthFormat)
{
   memset(rt, 0, sizeof(*rt));
   rt->width  = width;
   rt->height = height;

   GX2Surface *s = &rt->cb.surface;
   s->dim        = GX2_SURFACE_DIM_TEXTURE_2D;
   s->width      = width;
   s->height     = height;
   s->depth      = 1;
   s->mipLevels  = mipLevels ? mipLevels : 1;
   s->format     = format;
   s->aa         = GX2_AA_MODE1X;
   s->use        = (GX2SurfaceUse)(GX2_SURFACE_USE_TEXTURE | GX2_SURFACE_USE_COLOR_BUFFER);
   s->tileMode   = GX2_TILE_MODE_DEFAULT;
   rt->cb.viewNumSlices = 1;
   GX2CalcSurfaceSizeAndAlignment(s);

   rt->image = memalign(s->alignment ? s->alignment : 0x100, s->imageSize);
   if (!rt->image) {
      return FALSE;
   }
   s->image = rt->image;
   GX2Invalidate(GX2_INVALIDATE_MODE_CPU, rt->image, s->imageSize);
   if (s->mipLevels > 1 && s->mipmapSize) {
      rt->mips = memalign(s->alignment ? s->alignment : 0x100, s->mipmapSize);
      if (!rt->mips) {
         free(rt->image);
         rt->image = NULL;
         return FALSE;
      }
      s->mipmaps = rt->mips;
      GX2Invalidate(GX2_INVALIDATE_MODE_CPU, rt->mips, s->mipmapSize);
   }
   GX2InitColorBufferRegs(&rt->cb);

   if (depthFormat != GX2_SURFACE_FORMAT_INVALID) {
      GX2Surface *d = &rt->db.surface;
      if (depthFormat == GX2_SURFACE_FORMAT_UNORM_R24_X8 || depthFormat == GX2_SURFACE_FORMAT_FLOAT_D24_S8) {
         d->use = GX2_SURFACE_USE_DEPTH_BUFFER;
      } else {
         d->use = (GX2SurfaceUse)(GX2_SURFACE_USE_DEPTH_BUFFER | GX2_SURFACE_USE_TEXTURE);
      }
      d->dim       = GX2_SURFACE_DIM_TEXTURE_2D;
      d->width     = width;
      d->height    = height;
      d->depth     = 1;
      d->mipLevels = 1;
      d->format    = depthFormat;
      d->aa        = GX2_AA_MODE1X;
      d->tileMode  = GX2_TILE_MODE_DEFAULT;
      rt->db.viewNumSlices = 1;
      rt->db.depthClear    = 1.0f;
      GX2CalcSurfaceSizeAndAlignment(d);
      rt->depthImage = memalign(d->alignment ? d->alignment : 0x100, d->imageSize);
      if (!rt->depthImage) {
         RTDestroy(rt);
         return FALSE;
      }
      d->image = rt->depthImage;
      GX2Invalidate(GX2_INVALIDATE_MODE_CPU, rt->depthImage, d->imageSize);
      GX2InitDepthBufferRegs(&rt->db);
      rt->hasDepth = TRUE;
   }
   return TRUE;
}

void RTDestroy(RT *rt)
{
   // Make sure the GPU is no longer using this memory before it goes back to the heap.
   GX2DrawDone();
   if (rt->image) {
      free(rt->image);
   }
   if (rt->mips) {
      free(rt->mips);
   }
   if (rt->depthImage) {
      free(rt->depthImage);
   }
   memset(rt, 0, sizeof(*rt));
}

void RTBegin(RT *rt, uint32_t mip, const float clear[4])
{
   rt->cb.viewMip = mip;
   GX2InitColorBufferRegs(&rt->cb);
   GX2SetColorBuffer(&rt->cb, GX2_RENDER_TARGET_0);
   if (rt->hasDepth && mip == 0) {
      GX2SetDepthBuffer(&rt->db);
   } else {
      GX2SetDepthBuffer(WHBGfxGetTVDepthBuffer());
   }
   uint32_t mw = rt->width >> mip;
   uint32_t mh = rt->height >> mip;
   if (mw == 0) {
      mw = 1;
   }
   if (mh == 0) {
      mh = 1;
   }
   GX2SetViewport(0.0f, 0.0f, (float)mw, (float)mh, 0.0f, 1.0f);
   GX2SetScissor(0, 0, mw, mh);
   GX2ClearColor(&rt->cb, clear[0], clear[1], clear[2], clear[3]);
   if (rt->hasDepth && mip == 0) {
      GX2ClearDepthStencilEx(&rt->db, 1.0f, 0, GX2_CLEAR_FLAGS_BOTH);
   }
   // The clear functions use their own state on hardware; putting the context back is what WHBGfxClearColor does too.
   GX2SetContextState(WHBGfxGetTVContextState());
   ApplyDefaultState();
}

void RTEnd(RT *rt)
{
   GX2ColorBuffer *tv = WHBGfxGetTVColourBuffer();
   GX2SetColorBuffer(tv, GX2_RENDER_TARGET_0);
   GX2SetDepthBuffer(WHBGfxGetTVDepthBuffer());
   GX2SetViewport(0.0f, 0.0f, (float)tv->surface.width, (float)tv->surface.height, 0.0f, 1.0f);
   GX2SetScissor(0, 0, tv->surface.width, tv->surface.height);
   GX2Invalidate((GX2InvalidateMode)(GX2_INVALIDATE_MODE_COLOR_BUFFER | GX2_INVALIDATE_MODE_TEXTURE), rt->image,
                 rt->cb.surface.imageSize);
   if (rt->mips) {
      GX2Invalidate((GX2InvalidateMode)(GX2_INVALIDATE_MODE_COLOR_BUFFER | GX2_INVALIDATE_MODE_TEXTURE), rt->mips,
                    rt->cb.surface.mipmapSize);
   }
   ApplyDefaultState();
}

void RTAsTexture(RT *rt, GX2Texture *out, uint32_t mip)
{
   memset(out, 0, sizeof(*out));
   out->surface        = rt->cb.surface;
   out->viewFirstMip   = mip;
   out->viewNumMips    = 1;
   out->viewFirstSlice = 0;
   out->viewNumSlices  = 1;
   out->compMap        = GX2_COMP_MAP(GX2_SQ_SEL_R, GX2_SQ_SEL_G, GX2_SQ_SEL_B, GX2_SQ_SEL_A);
   GX2InitTextureRegs(out);
}

// ---------------------------------------------------------------------------------------------
// Frames

static float gPadBg[4] = {0.10f, 0.00f, 0.20f, 1.0f};

void SetPadClear(float r, float g, float b, float a)
{
   gPadBg[0] = r;
   gPadBg[1] = g;
   gPadBg[2] = b;
   gPadBg[3] = a;
}

static void PadScene(void)
{
   // Orientation markers like the TV's, so a pad capture can be read the same way.
   DrawRect(0.85f, 0.05f, 0.10f, 0.10f, 0.5f, 1.0f, 0.0f, 0.0f, 1.0f);
   DrawRect(0.05f, 0.85f, 0.10f, 0.10f, 0.5f, 0.0f, 1.0f, 0.0f, 1.0f);
}

BOOL PresentFrame(Ctx *ctx, const float bg[4], SceneFn scene, void *user, uint32_t frame)
{
   WHBGfxBeginRender();

   WHBGfxBeginRenderTV();
   WHBGfxClearColor(bg[0], bg[1], bg[2], bg[3]);
   ApplyDefaultState();
   gCursor = 0;
   if (scene) {
      scene(ctx, user, frame);
   }
   WHBGfxFinishRenderTV();

   WHBGfxBeginRenderDRC();
   WHBGfxClearColor(gPadBg[0], gPadBg[1], gPadBg[2], gPadBg[3]);
   ApplyDefaultState();
   gCursor = 0;
   PadScene();
   WHBGfxFinishRenderDRC();

   WHBGfxFinishRender(); // swap + flush + GX2DrawDone: the previous frame's GPU work is finished after this

   gFrames++;
   MbSet(AUDIT_MB_FRAMES, gFrames);
   PollHost(ctx);
   return !(ctx && ctx->aborted);
}

BOOL HoldScene(Ctx *ctx, const char *checkpoint, uint32_t minFrames, const float bg[4], SceneFn scene, void *user)
{
   uint32_t frame = 0;
   for (; frame < minFrames; frame++) {
      if (!PresentFrame(ctx, bg, scene, user, frame)) {
         return FALSE;
      }
   }

   // Raise the checkpoint. The host reads the frame back while this scene keeps being presented,
   // then answers CONTINUE.
   gContinueSeen = FALSE;
   MbStr(AUDIT_MB_CHECKPOINT_NAME, AUDIT_NAME_LEN, checkpoint);
   MbSet(AUDIT_MB_CHECKPOINT_SEQ, MbGet(AUDIT_MB_CHECKPOINT_SEQ) + 1);
   MbSet(AUDIT_MB_GUEST_STATE, AUDIT_STATE_CHECKPOINT);
   MbTouch();
   OSReport(AUDIT_LOG_PREFIX " CHECKPOINT %s %u %s frame=%u\n", ctx->testId, (unsigned)ctx->token, checkpoint,
            (unsigned)gFrames);

   OSTime start = OSGetTime();
   while (!gContinueSeen) {
      if (!PresentFrame(ctx, bg, scene, user, frame++)) {
         return FALSE;
      }
      if (gAutorun) {
         // No host is attached: a checkpoint is just a still moment, held long enough to look at.
         if (OSTicksToMilliseconds(OSGetTime() - start) > AUTORUN_HOLD_MS) {
            break;
         }
      } else if (OSTicksToMilliseconds(OSGetTime() - start) > CHECKPOINT_TIMEOUT_MS) {
         LogSelf(ctx, "fail", "host did not answer checkpoint %s in %u ms", checkpoint, CHECKPOINT_TIMEOUT_MS);
         break;
      }
   }

   MbSet(AUDIT_MB_GUEST_STATE, AUDIT_STATE_RUNNING);
   MbTouch();
   Fold(ctx, frame);
   return TRUE;
}

// ---------------------------------------------------------------------------------------------
// Idle loop and test dispatch

static void IdleScene(Ctx *ctx, void *user, uint32_t frame)
{
   (void)ctx;
   (void)user;
   // A dim field with a slow marker, so a capture of the idle guest is recognisably not a test.
   float x = (float)(frame % 240u) / 240.0f * 0.9f;
   DrawRect(x, 0.92f, 0.08f, 0.04f, 0.5f, 0.3f, 0.3f, 0.35f, 1.0f);
}

static const TestEntry *FindTest(const char *id)
{
   for (const TestEntry *t = kRenderTests; t->id; t++) {
      if (strcmp(t->id, id) == 0) {
         return t;
      }
   }
   for (const TestEntry *t = kAvTests; t->id; t++) {
      if (strcmp(t->id, id) == 0) {
         return t;
      }
   }
   return NULL;
}

static void RunTest(Ctx *ctx)
{
   const TestEntry *entry = FindTest(ctx->testId);

   MbSet(AUDIT_MB_RUN_TOKEN, ctx->token);
   MbStr(AUDIT_MB_TEST_ID, AUDIT_NAME_LEN, ctx->testId);
   MbSet(AUDIT_MB_TEST_RESULT, AUDIT_RESULT_NONE);
   MbSet(AUDIT_MB_GUEST_ERRORS, 0);
   MbSet(AUDIT_MB_AUDIO_STATE, 0);
   MbSet(AUDIT_MB_AUDIO_STEP, 0);
   MbSet(AUDIT_MB_INPUT_READS, 0);
   MbSet(AUDIT_MB_INPUT_CHANGES, 0);
   MbSet(AUDIT_MB_GUEST_STATE, AUDIT_STATE_RUNNING);
   MbTouch();
   OSReport(AUDIT_LOG_PREFIX " TEST_BEGIN %s %u seed=%u %s\n", ctx->testId, (unsigned)ctx->token,
            (unsigned)ctx->seed, ctx->params);

   uint32_t result;
   const char *word;
   uint32_t startFrames = gFrames;
   if (!entry) {
      result = AUDIT_RESULT_UNKNOWN;
      word   = "error";
      ctx->errors++;
      SetMessage("no test named %s in this build", ctx->testId);
   } else {
      entry->fn(ctx);
      if (ctx->aborted) {
         result = AUDIT_RESULT_ABORTED;
         word   = "aborted";
      } else if (ctx->errors) {
         result = AUDIT_RESULT_ERROR;
         word   = "error";
      } else {
         result = AUDIT_RESULT_OK;
         word   = "ok";
      }
   }

   MbSet(AUDIT_MB_CHECKSUM, ctx->checksum);
   MbSet(AUDIT_MB_GUEST_ERRORS, ctx->errors);
   MbSet(AUDIT_MB_TEST_RESULT, result);
   MbSet(AUDIT_MB_GUEST_STATE, AUDIT_STATE_IDLE);
   MbTouch();
   OSReport(AUDIT_LOG_PREFIX " TEST_END %s %u %s checksum=%08x frames=%u errors=%u\n", ctx->testId,
            (unsigned)ctx->token, word, (unsigned)ctx->checksum, (unsigned)(gFrames - startFrames),
            (unsigned)ctx->errors);
}

// A guest that cannot draw still answers the mailbox, so the host can say why instead of timing out.
static void FatalLoop(const char *why)
{
   MbSet(AUDIT_MB_GUEST_STATE, AUDIT_STATE_FATAL);
   SetMessage("%s", why);
   MbSet(AUDIT_MB_MAGIC, AUDIT_MAILBOX_MAGIC);
   MbTouch();
   OSReport(AUDIT_LOG_PREFIX " HELLO %u %s mailbox=0x%08x tv=0x0 fatal=%s\n", (unsigned)AUDIT_PROTOCOL_VERSION,
            AUDIT_BUILD, (unsigned)(uintptr_t)gMb, why);
   while (WHBProcIsRunning() && !gExitRequested) {
      PollHost(NULL);
      OSSleepTicks(OSMillisecondsToTicks(50));
   }
}

static BOOL InitGraphics(void)
{
   if (!WHBGfxLoadGFDShaderGroup(&gGroup, 0, kAuditShaderGsh)) {
      return FALSE;
   }
   WHBGfxInitShaderAttribute(&gGroup, "in_pos", 0, offsetof(Vertex, pos), GX2_ATTRIB_FORMAT_FLOAT_32_32_32);
   WHBGfxInitShaderAttribute(&gGroup, "in_color", 0, offsetof(Vertex, color), GX2_ATTRIB_FORMAT_FLOAT_32_32_32_32);
   WHBGfxInitShaderAttribute(&gGroup, "in_uv", 0, offsetof(Vertex, uv), GX2_ATTRIB_FORMAT_FLOAT_32_32);
   if (!WHBGfxInitFetchShader(&gGroup)) {
      return FALSE;
   }
   GX2SetShaderMode(GX2_SHADER_MODE_UNIFORM_BLOCK);

   gPool = (Vertex *)memalign(GX2_VERTEX_BUFFER_ALIGNMENT, POOL_VERTS * sizeof(Vertex));
   if (!gPool) {
      return FALSE;
   }
   memset(gPool, 0, POOL_VERTS * sizeof(Vertex));
   GX2Invalidate(GX2_INVALIDATE_MODE_CPU_ATTRIBUTE_BUFFER, gPool, POOL_VERTS * sizeof(Vertex));

   GX2InitSampler(&gSamplerPoint, GX2_TEX_CLAMP_MODE_CLAMP, GX2_TEX_XY_FILTER_MODE_POINT);
   GX2InitSampler(&gSamplerLinear, GX2_TEX_CLAMP_MODE_CLAMP, GX2_TEX_XY_FILTER_MODE_LINEAR);

   if (!TexCreate(&gWhite, GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8, 4, 4)) {
      return FALSE;
   }
   memset(gWhite.image, 0xFF, gWhite.tex.surface.imageSize);
   TexUploaded(&gWhite);
   gGfxReady = TRUE;
   return TRUE;
}

int main(int argc, char **argv)
{
   (void)argc;
   (void)argv;

   WHBProcInit();
   memset((void *)gMb, 0, sizeof(gMb));
   MbSet(AUDIT_MB_VERSION, AUDIT_PROTOCOL_VERSION);
   MbSet(AUDIT_MB_GUEST_STATE, AUDIT_STATE_BOOT);

   if (!WHBGfxInit()) {
      FatalLoop("WHBGfxInit failed");
      WHBProcShutdown();
      return 1;
   }
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
   VPADInit(); // deprecated in this wut revision but harmless, and older revisions need it
#pragma GCC diagnostic pop

   if (!InitGraphics()) {
      FatalLoop("graphics setup failed (shader, vertex pool or white texture)");
      WHBGfxShutdown();
      WHBProcShutdown();
      return 1;
   }

   GX2ColorBuffer *tv = WHBGfxGetTVColourBuffer();
   MbSet(AUDIT_MB_GUEST_STATE, AUDIT_STATE_IDLE);
   MbSet(AUDIT_MB_MAGIC, AUDIT_MAILBOX_MAGIC); // last: the host treats the magic as "mailbox is valid"
   MbTouch();
   OSReport(AUDIT_LOG_PREFIX " HELLO %u %s mailbox=0x%08x tv=%ux%u\n", (unsigned)AUDIT_PROTOCOL_VERSION,
            AUDIT_BUILD, (unsigned)(uintptr_t)gMb, (unsigned)tv->surface.width, (unsigned)tv->surface.height);

   static const float kIdleBg[4] = {0.06f, 0.06f, 0.10f, 1.0f};
   Ctx idle;
   memset(&idle, 0, sizeof(idle));
   strcpy(idle.testId, "idle");

   // Reproducibility outside the Audit app: the same tests, in a fixed order, with their default parameters.
   // Every step is logged as MUFFINAUDIT lines, so the sequence can be watched on any Wii U emulator and its log compared.
   static const char *const kAutorun[] = {"orientation",    "clear_colours", "blend_alpha",    "depth_test", "texture_formats", "rt_copy",
                                          "rt_feedback",    "rt_lifecycle",  "flicker_static", "motion_counter", "audio_sweep",   NULL};
   BOOL autorunDone     = FALSE;
   OSTime bootTime      = OSGetTime();

   uint32_t idleFrame = 0;
   while (WHBProcIsRunning() && !gExitRequested) {
      if (!gHostSeen && !autorunDone && OSTicksToMilliseconds(OSGetTime() - bootTime) > AUTORUN_START_MS) {
         OSReport(AUDIT_LOG_PREFIX " NOTE - 0 no Audit app attached: running the built-in sequence\n");
         gAutorun = TRUE;
         for (uint32_t i = 0; kAutorun[i] && !gHostSeen && WHBProcIsRunning(); i++) {
            Ctx run;
            memset(&run, 0, sizeof(run));
            strncpy(run.testId, kAutorun[i], sizeof(run.testId) - 1);
            run.token = 9000u + i;
            run.seed  = 1u;
            RunTest(&run);
         }
         gAutorun    = FALSE;
         autorunDone = TRUE;
         OSReport(AUDIT_LOG_PREFIX " NOTE - 0 built-in sequence finished\n");
         continue;
      }
      if (gRunPending) {
         gRunPending = FALSE;
         Ctx run     = gPendingRun;
         RunTest(&run);
         continue;
      }
      PresentFrame(NULL, kIdleBg, IdleScene, &idle, idleFrame++);
   }

   OSReport(AUDIT_LOG_PREFIX " BYE\n");
   GX2DrawDone();
   WHBGfxShutdown();
   WHBProcShutdown();
   (void)gGfxReady;
   return 0;
}
