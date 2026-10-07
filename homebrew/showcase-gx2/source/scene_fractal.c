// Core Fractal: a double-precision Mandelbrot renderer spread over all three PPC cores.
// Three worker threads, one pinned to each core, interleave the rows of a 256x144
// texture; the main thread uploads whatever has been finished so far every frame, so
// the picture fills in live. The view dives toward three famous points by itself
// (as fast as the machine can render it) or can be steered by hand.

#include "app.h"
#include "audio.h"
#include "gfx.h"
#include "ui.h"

#include <coreinit/cache.h>
#include <coreinit/debug.h>
#include <coreinit/thread.h>
#include <coreinit/time.h>
#include <gx2/mem.h>
#include <gx2/utils.h>

#include <malloc.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#define FW 256
#define FH 144
#define WORKERS 3
#define STACK 0x10000

typedef struct { double cx, cy, scale; int maxIter; } View;

static Tex sTex;
static uint8_t *sPix;
static uint32_t sPitch;
static OSThread *sThr[WORKERS];
static uint8_t *sStk[WORKERS];
static bool sThreadsMade;

static volatile uint32_t sGen;
static volatile int sQuit, sActive;
static volatile View sView;
static volatile uint32_t sFinGen[WORKERS];
static volatile int sRowsDone[WORKERS];
static volatile uint32_t sIters[WORKERS];
static volatile uint8_t sRowDone[FH];

static uint32_t sLut[1024];

// main-thread state
static View sTarget;
static bool sAuto = true;
static int sTargetIdx, sViewCount;
static OSTime sViewStart;
static float sLastMs, sMips;
static bool sComplete;
static float sHold;
static float sSinceBump;
static bool sDirty;
static float sUiM[16];
static Batch *sImgTv, *sUiTv, *sImgDrc, *sUiDrc;

static const double kTargets[3][2] = {
   {-0.743643887037151, 0.131825904205330},    // seahorse valley
   {0.2549870375144766, -0.0005679790528465},  // elephant valley
   {-0.10109636384562, 0.95628651080914},      // Misiurewicz spiral
};
static const char *kTargetName[3] = {"SEAHORSE VALLEY", "ELEPHANT VALLEY", "SPIRAL"};

// RGBA8 pixel as one 32-bit word: R is the first byte in memory on both byte orders
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#define PACK_RGBA(r, g, b, a) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(g) << 8) | (uint32_t)(r))
#else
#define PACK_RGBA(r, g, b, a) (((uint32_t)(r) << 24) | ((uint32_t)(g) << 16) | ((uint32_t)(b) << 8) | (uint32_t)(a))
#endif

#define IMG_X 24.0f
#define IMG_Y 90.0f
#define IMG_W 832.0f
#define IMG_H 468.0f

// ---- workers --------------------------------------------------------------

static void render_row(int y, double cx, double cy, double sc, int maxIter, uint32_t *iters)
{
   uint32_t *dst = (uint32_t *)(sPix + (size_t)y * sPitch * 4u);
   double step = sc / (double)FW;
   double ci = cy + (double)(y - FH / 2) * step;
   const double ln2 = 0.6931471805599453;
   uint32_t total = 0;
   for (int x = 0; x < FW; x++) {
      double cr = cx + (double)(x - FW / 2) * step;
      double q = (cr - 0.25) * (cr - 0.25) + ci * ci;
      uint32_t px;
      if (q * (q + (cr - 0.25)) < 0.25 * ci * ci || (cr + 1.0) * (cr + 1.0) + ci * ci < 0.0625) {
         px = PACK_RGBA(6, 3, 12, 255);   // inside the main cardioid or period-2 bulb
      } else {
         double zr = 0.0, zi = 0.0, r2 = 0.0;
         int n = 0;
         while (n < maxIter) {
            double t = zr * zr - zi * zi + cr;
            zi = 2.0 * zr * zi + ci;
            zr = t;
            r2 = zr * zr + zi * zi;
            if (r2 > 256.0) break;
            n++;
         }
         total += (uint32_t)n;
         if (n >= maxIter) {
            px = PACK_RGBA(6, 3, 12, 255);
         } else {
            double lz = 0.5 * log(r2);
            double mu = (double)n + 1.0 - log(lz) / ln2;
            int idx = (int)(mu * 9.0) & 1023;
            px = sLut[idx];
         }
      }
      dst[x] = px;
   }
   // each core has its own data cache; push this row to memory so the GPU upload sees it
   DCFlushRange(dst, FW * 4);
   *iters += total;
}

static int worker(int id, const char **argv)
{
   (void)argv;
   uint32_t last = 0;
   while (!sQuit) {
      uint32_t g = sGen;
      if (g == last || !sActive) {
         OSSleepTicks(OSMillisecondsToTicks(3));
         continue;
      }
      __sync_synchronize();
      View v;
      v.cx = sView.cx; v.cy = sView.cy; v.scale = sView.scale; v.maxIter = sView.maxIter;
      __sync_synchronize();
      if (sGen != g) continue;

      sRowsDone[id] = 0;
      bool aborted = false;
      uint32_t iters = 0;
      for (int y = id; y < FH; y += WORKERS) {
         render_row(y, v.cx, v.cy, v.scale, v.maxIter, &iters);
         if (sGen != g || sQuit) { aborted = true; break; }
         sRowDone[y] = 1;
         sRowsDone[id]++;
         sIters[id] += iters;
         iters = 0;
      }
      if (!aborted) {
         sFinGen[id] = g;
         last = g;
      }
   }
   return 0;
}

static void make_threads(void)
{
   if (sThreadsMade) return;
   static const int attr[WORKERS] = {OS_THREAD_ATTRIB_AFFINITY_CPU0, OS_THREAD_ATTRIB_AFFINITY_CPU1, OS_THREAD_ATTRIB_AFFINITY_CPU2};
   for (int i = 0; i < WORKERS; i++) {
      sStk[i] = (uint8_t *)memalign(16, STACK);
      sThr[i] = (OSThread *)memalign(16, sizeof(OSThread));
      if (!sStk[i] || !sThr[i]) return;
      if (!OSCreateThread(sThr[i], worker, i, NULL, sStk[i] + STACK, STACK, 20, attr[i])) {
         OSReport("showcase: fractal worker %d create failed\n", i);
         return;
      }
      OSSetThreadName(sThr[i], "showcase fractal");
      OSResumeThread(sThr[i]);
   }
   sThreadsMade = true;
}

void fractal_quit(void)
{
   if (!sThreadsMade) return;
   sQuit = 1;
   for (int i = 0; i < WORKERS; i++) {
      int r;
      OSJoinThread(sThr[i], &r);
   }
   sThreadsMade = false;
}

// ---- main-thread side -------------------------------------------------------

static void start_view(void)
{
   int it = 90 + (int)(34.0 * log(3.4 / sTarget.scale) / 0.6931);
   if (it < 90) it = 90;
   if (it > 700) it = 700;
   sTarget.maxIter = it;
   sView.cx = sTarget.cx; sView.cy = sTarget.cy; sView.scale = sTarget.scale; sView.maxIter = sTarget.maxIter;
   for (int y = 0; y < FH; y++) sRowDone[y] = 0;
   for (int i = 0; i < WORKERS; i++) { sRowsDone[i] = 0; sIters[i] = 0; }
   __sync_synchronize();
   sGen++;
   sViewStart = OSGetTime();
   sComplete = false;
   sDirty = false;
   sSinceBump = 0.0f;
   sViewCount++;
}

static void fractal_enter(void)
{
   if (!sPix) {
      memset(&sTex, 0, sizeof(sTex));
      GX2Surface *s = &sTex.tex.surface;
      s->dim = GX2_SURFACE_DIM_TEXTURE_2D;
      s->width = FW; s->height = FH; s->depth = 1; s->mipLevels = 1;
      s->format = GX2_SURFACE_FORMAT_UNORM_R8_G8_B8_A8;
      s->aa = GX2_AA_MODE1X;
      s->use = GX2_SURFACE_USE_TEXTURE;
      s->tileMode = GX2_TILE_MODE_LINEAR_ALIGNED;
      GX2CalcSurfaceSizeAndAlignment(s);
      s->image = memalign(s->alignment, s->imageSize);
      memset(s->image, 0, s->imageSize);
      sTex.tex.viewFirstMip = 0; sTex.tex.viewNumMips = 1; sTex.tex.viewFirstSlice = 0; sTex.tex.viewNumSlices = 1;
      sTex.tex.compMap = GX2_COMP_MAP(GX2_SQ_SEL_R, GX2_SQ_SEL_G, GX2_SQ_SEL_B, GX2_SQ_SEL_A);
      GX2InitTextureRegs(&sTex.tex);
      GX2InitSampler(&sTex.samp, GX2_TEX_CLAMP_MODE_CLAMP, GX2_TEX_XY_FILTER_MODE_LINEAR);
      sPix = (uint8_t *)s->image;
      sPitch = s->pitch;

      for (int i = 0; i < 1024; i++) {
         float t = (float)i / 1024.0f;
         Col c = pal(t * 2.0f + 0.05f, 1.0f);
         float v = 0.35f + 0.65f * (0.5f + 0.5f * fsin(t * 6.28318f * 4.0f));
         sLut[i] = PACK_RGBA((uint32_t)(c.r * v * 255.0f), (uint32_t)(c.g * v * 255.0f), (uint32_t)(c.b * v * 255.0f), 255);
      }
   }
   make_threads();
   sActive = 1;
   sAuto = true;
   sTargetIdx = 0;
   sViewCount = 0;
   sTarget.cx = -0.5; sTarget.cy = 0.0; sTarget.scale = 3.4;
   start_view();
}

static void fractal_leave(void) { sActive = 0; }

static void next_dive_step(void)
{
   sTarget.scale *= 0.62;
   if (sTarget.scale < 6e-5) {
      sTargetIdx = (sTargetIdx + 1) % 3;
      sTarget.scale = 3.4;
      sTarget.cx = -0.5; sTarget.cy = 0.0;
   }
   // glide the centre toward the target as the view tightens
   double k = 1.0 - sTarget.scale / 3.4;
   k = k * k;
   sTarget.cx = -0.5 + (kTargets[sTargetIdx][0] + 0.5) * (k > 1.0 ? 1.0 : k) * 1.0;
   sTarget.cy = kTargets[sTargetIdx][1] * (k > 1.0 ? 1.0 : k);
   if (sTarget.scale < 0.4) { sTarget.cx = kTargets[sTargetIdx][0]; sTarget.cy = kTargets[sTargetIdx][1]; }
   start_view();
}

static void fractal_update(float dt)
{
   m4_ortho_ui(sUiM);

   if (!sThreadsMade) {
      // threads could not start: say so rather than showing a black picture
      sImgTv = gfx_batch(); sUiTv = gfx_batch(); sImgDrc = gfx_batch(); sUiDrc = gfx_batch();
      ui_header(sUiTv, "CORE FRACTAL", "WORKER THREADS UNAVAILABLE");
      ui_header(sUiDrc, "CORE FRACTAL", "WORKER THREADS UNAVAILABLE");
      return;
   }

   // input
   bool changed = false;
   if (PRESSED(VPAD_BUTTON_A)) { sAuto = !sAuto; audio_sfx(1); }
   if (PRESSED(VPAD_BUTTON_X)) { sTarget.cx = -0.5; sTarget.cy = 0.0; sTarget.scale = 3.4; sAuto = false; changed = true; audio_sfx(2); }
   if (PRESSED(VPAD_BUTTON_Y)) { sTargetIdx = (sTargetIdx + 1) % 3; sTarget.cx = kTargets[sTargetIdx][0]; sTarget.cy = kTargets[sTargetIdx][1]; sTarget.scale = 0.05; sAuto = false; changed = true; audio_sfx(1); }
   if (HELD(VPAD_BUTTON_ZR)) { sTarget.scale *= 1.0 - (double)dt * 0.9; sAuto = false; changed = true; }
   if (HELD(VPAD_BUTTON_ZL)) { sTarget.scale *= 1.0 + (double)dt * 0.9; sAuto = false; changed = true; }
   if (fabsf(g_in.rx) + fabsf(g_in.ry) > 0.15f) {
      sTarget.cx += (double)g_in.rx * sTarget.scale * (double)dt * 0.8;
      sTarget.cy -= (double)g_in.ry * sTarget.scale * (double)dt * 0.8;
      sAuto = false;
      changed = true;
   }
   if (g_in.touchStart) {
      if (ui_hit(g_in.tx, g_in.ty, IMG_X, IMG_Y, IMG_W, IMG_H)) {
         double fx = (double)(g_in.tx - IMG_X) / IMG_W, fy = (double)(g_in.ty - IMG_Y) / IMG_H;
         sTarget.cx += (fx - 0.5) * sTarget.scale;
         sTarget.cy += (fy - 0.5) * sTarget.scale * (double)FH / (double)FW;
         sTarget.scale *= 0.45;
         sAuto = false;
         changed = true;
         audio_sfx(0);
      }
      if (ui_hit(g_in.tx, g_in.ty, 890.0f, 560.0f, 170.0f, 56.0f)) { sAuto = !sAuto; audio_sfx(1); }
      if (ui_hit(g_in.tx, g_in.ty, 1070.0f, 560.0f, 180.0f, 56.0f)) { sTarget.scale *= 2.5; sAuto = false; changed = true; audio_sfx(2); }
      if (ui_hit(g_in.tx, g_in.ty, 890.0f, 624.0f, 360.0f, 52.0f)) { sTarget.cx = -0.5; sTarget.cy = 0.0; sTarget.scale = 3.4; sAuto = false; changed = true; audio_sfx(2); }
   }
   if (sTarget.scale > 6.0) sTarget.scale = 6.0;
   if (sTarget.scale < 1e-13) sTarget.scale = 1e-13;

   // completion
   sSinceBump += dt;
   if (!sComplete) {
      uint32_t g = sGen;
      bool all = true;
      for (int i = 0; i < WORKERS; i++) if (sFinGen[i] != g) all = false;
      if (all) {
         sComplete = true;
         sHold = 0.0f;
         sLastMs = (float)((double)(OSGetTime() - sViewStart) * 1000.0 / (double)OSTimerClockSpeed);
         uint32_t total = 0;
         for (int i = 0; i < WORKERS; i++) total += sIters[i];
         sMips = sLastMs > 0.0f ? (float)total / sLastMs / 1000.0f : 0.0f;
      }
   } else {
      sHold += dt;
   }

   if (changed) sDirty = true;
   if (sDirty && sSinceBump > 0.07f) start_view();
   else if (sAuto && sComplete && sHold > 0.45f) next_dive_step();

   // upload whatever is finished so far
   GX2Invalidate(GX2_INVALIDATE_MODE_CPU_TEXTURE, sTex.tex.surface.image, sTex.tex.surface.imageSize);

   sImgTv = gfx_batch(); sUiTv = gfx_batch(); sImgDrc = gfx_batch(); sUiDrc = gfx_batch();
   b_rect_uv(sImgTv, 0, 0, VW, VH, 0, 0, 1, 1, C(1, 1, 1, 1));
   b_rect(sImgDrc, 0, 0, VW, VH, C(0.03f, 0.03f, 0.08f, 1));
   b_rect_uv(sImgDrc, IMG_X, IMG_Y, IMG_W, IMG_H, 0, 0, 1, 1, C(1, 1, 1, 1));

   static const Col coreCol[WORKERS] = {{1.0f, 0.35f, 0.35f, 1}, {0.4f, 1.0f, 0.45f, 1}, {0.45f, 0.6f, 1.0f, 1}};
   int rowsPer = FH / WORKERS;
   char buf[96];

   // TV: stats panel, bottom left
   if (g_hud) {
      char sub[96];
      snprintf(sub, sizeof(sub), "3 CORES  %s  VIEW %d  MAX ITER %d", sAuto ? kTargetName[sTargetIdx] : "MANUAL", sViewCount, sTarget.maxIter);
      ui_header(sUiTv, "CORE FRACTAL", sub);
      ui_panel(sUiTv, 20.0f, VH - 150.0f, 470.0f, 100.0f, 0.65f);
      for (int i = 0; i < WORKERS; i++) {
         snprintf(buf, sizeof(buf), "CORE %d", i);
         b_text_shadow(sUiTv, 34.0f, VH - 140.0f + (float)i * 28.0f, 2.0f, coreCol[i], buf);
         ui_bar(sUiTv, 150.0f, VH - 140.0f + (float)i * 28.0f, 320.0f, 18.0f, (float)sRowsDone[i] / (float)rowsPer, coreCol[i]);
      }
      ui_footer(sUiTv, "A: AUTO DIVE   RIGHT STICK: PAN   ZL/ZR: ZOOM   Y: NEXT SPOT   X: RESET   B: MENU");
   }

   // GamePad
   ui_header(sUiDrc, "CORE FRACTAL", "TAP THE PICTURE TO ZOOM THERE");
   if (g_hud) {
      b_rect(sUiDrc, IMG_X - 3.0f, IMG_Y - 3.0f, IMG_W + 6.0f, 3.0f, C(1, 1, 1, 0.5f));
      // row strip: each of the 144 rows coloured by the core that owns it
      for (int y = 0; y < FH; y++) {
         Col c = coreCol[y % WORKERS];
         b_rect(sUiDrc, 892.0f, 94.0f + (float)y * 3.0f, 40.0f, 3.0f, sRowDone[y] ? c : CMUL(c, 0.18f));
      }
      for (int i = 0; i < WORKERS; i++) {
         snprintf(buf, sizeof(buf), "CORE %d", i);
         b_text_shadow(sUiDrc, 950.0f, 110.0f + (float)i * 70.0f, 2.4f, coreCol[i], buf);
         ui_bar(sUiDrc, 950.0f, 140.0f + (float)i * 70.0f, 300.0f, 16.0f, (float)sRowsDone[i] / (float)rowsPer, coreCol[i]);
      }
      snprintf(buf, sizeof(buf), "%.0f MS PER VIEW", sLastMs);
      b_text_shadow(sUiDrc, 950.0f, 330.0f, 2.2f, C(1, 1, 1, 1), buf);
      snprintf(buf, sizeof(buf), "%.2f M ITERATIONS/S", sMips);
      b_text_shadow(sUiDrc, 950.0f, 362.0f, 2.2f, C(1.0f, 0.9f, 0.5f, 1), buf);
      snprintf(buf, sizeof(buf), "ZOOM %.1e", 3.4 / sTarget.scale);
      b_text_shadow(sUiDrc, 950.0f, 394.0f, 2.2f, C(0.8f, 0.9f, 1.0f, 1), buf);
      snprintf(buf, sizeof(buf), "RE %+.10f", sTarget.cx);
      b_text_shadow(sUiDrc, 38.0f, 580.0f, 2.2f, C(1, 1, 1, 0.95f), buf);
      snprintf(buf, sizeof(buf), "IM %+.10f", sTarget.cy);
      b_text_shadow(sUiDrc, 38.0f, 612.0f, 2.2f, C(1, 1, 1, 0.95f), buf);
      ui_button(sUiDrc, 890.0f, 560.0f, 170.0f, 56.0f, sAuto ? "AUTO" : "MANUAL", sAuto, C(0.3f, 0.7f, 0.5f, 1));
      ui_button(sUiDrc, 1070.0f, 560.0f, 180.0f, 56.0f, "ZOOM OUT", true, C(0.8f, 0.5f, 0.3f, 1));
      ui_button(sUiDrc, 890.0f, 624.0f, 360.0f, 52.0f, "RESET VIEW", true, C(0.5f, 0.4f, 0.8f, 1));
   }
}

static void fractal_draw(Target tg)
{
   if (sThreadsMade) {
      gfx_use_texture(&sTex);
      gfx_draw_batch(tg == TARGET_TV ? sImgTv : sImgDrc, sUiM, BLEND_OPAQUE, DEPTH_OFF, NULL);
      gfx_use_texture(NULL);
   }
   gfx_draw_batch(tg == TARGET_TV ? sUiTv : sUiDrc, sUiM, BLEND_ALPHA, DEPTH_OFF, NULL);
}

const Scene scene_fractal = {
   "CORE FRACTAL", "MANDELBROT ON THREE CPU CORES, TAP TO ZOOM", fractal_enter, fractal_leave, fractal_update, NULL, fractal_draw, 30.0f,
};
