// Mirror Hall: render-to-texture video feedback. Every frame the previous frame's
// 512x512 colour buffer is drawn, slightly zoomed and rotated and faded, into the
// other buffer, then fresh shapes are added on top. The result is shown on both
// screens and mapped onto two spinning cubes. Touch the GamePad to paint into it.

#include "app.h"
#include "audio.h"
#include "gfx.h"
#include "ui.h"

#include <coreinit/debug.h>

#include <math.h>
#include <stdio.h>
#include <string.h>

#define RT_SIZE 512
#define RS 720.0f   // render-target virtual size

static RTarget sRt[2];
static bool sMade, sFailed, sFirst = true;
static int sShown;
static int sPreset;
static float sHueSpin;
static float sPaint[2];
static bool sPainting;
static float sUiM[16], sRtM[16];
static float sTwist;
static Batch *sBgTv, *sUiTv, *sUiDrc, *sCubes, *sBgDrc;
static float sCubeVP[2][16];

static const struct { float rot, zoom; const char *name; } kPreset[3] = {
   {0.012f, 1.035f, "TUNNEL"}, {0.045f, 1.060f, "SWIRL"}, {-0.030f, 1.050f, "COUNTER-SPIN"},
};

static void mirror_enter(void)
{
   if (!sMade && !sFailed) {
      sMade = gfx_rt_create(&sRt[0], RT_SIZE, RT_SIZE) && gfx_rt_create(&sRt[1], RT_SIZE, RT_SIZE);
      sFailed = !sMade;
      OSReport("showcase: render targets %s\n", sMade ? "ready" : "FAILED");
   }
   sFirst = true;
}

static void mirror_leave(void) {}

static void rt_ortho(float m[16])
{
   memset(m, 0, sizeof(float) * 16);
   m[0] = 2.0f / RS;
   m[5] = -2.0f / RS;
   m[10] = -1.0f;
   m[12] = -1.0f;
   m[13] = 1.0f;
   m[15] = 1.0f;
}

static void mirror_update(float dt)
{
   float t = (float)g_time;
   m4_ortho_ui(sUiM);
   rt_ortho(sRtM);

   if (PRESSED(VPAD_BUTTON_A)) { sPreset = (sPreset + 1) % 3; audio_sfx(1); }
   if (PRESSED(VPAD_BUTTON_X)) { sFirst = true; audio_sfx(2); }
   if (HELD(VPAD_BUTTON_ZR)) sTwist += dt * 0.04f;
   if (HELD(VPAD_BUTTON_ZL)) sTwist -= dt * 0.04f;
   if (sTwist > 0.08f) sTwist = 0.08f;
   if (sTwist < -0.08f) sTwist = -0.08f;
   sHueSpin += dt * (0.08f + 0.2f * g_audio.master);

   // painting: touch on the GamePad square, otherwise the right stick, otherwise nothing extra
   sPainting = false;
   if (g_in.touch && g_in.tx >= 280.0f && g_in.tx <= 1000.0f) {
      sPaint[0] = g_in.tx - 280.0f;
      sPaint[1] = g_in.ty;
      sPainting = true;
   } else if (fabsf(g_in.rx) + fabsf(g_in.ry) > 0.15f) {
      sPaint[0] = RS * 0.5f + g_in.rx * 300.0f;
      sPaint[1] = RS * 0.5f - g_in.ry * 300.0f;
      sPainting = true;
   }

   // the two cubes show the live texture
   float p[16], v[16], pv[16], shift[16], rx[16], ry[16], r[16];
   m4_persp(p, 0.8f, VW / VH, 0.1f, 50.0f);
   m4_lookat(v, 0.0f, 0.0f, 6.0f, 0.0f, 0.0f, 0.0f);
   m4_mul(pv, p, v);
   for (int i = 0; i < 2; i++) {
      m4_translate(shift, i == 0 ? -0.80f : 0.80f, 0.0f, 0.0f);
      m4_rot_x(rx, t * (0.7f + 0.2f * (float)i) * (i ? -1.0f : 1.0f));
      m4_rot_y(ry, t * 0.9f * (i ? -1.0f : 1.0f));
      m4_mul(r, rx, ry);
      float s[16], sr[16], full[16];
      m4_scale(s, 1.35f, 1.35f, 1.35f);
      m4_mul(sr, r, s);
      m4_mul(full, pv, sr);
      m4_mul(sCubeVP[i], shift, full);
   }

   sBgTv = gfx_batch();
   sBgDrc = gfx_batch();
   sCubes = gfx_batch();
   sUiTv = gfx_batch();
   sUiDrc = gfx_batch();

   // backdrops: the texture stretched and dimmed
   b_rect_uv(sBgTv, 0, 0, VW, VH, 0, 0, 1, 1, C(0.30f, 0.30f, 0.34f, 1));
   b_rect_uv(sBgDrc, 0, 0, VW, VH, 0, 0, 1, 1, C(0.22f, 0.22f, 0.26f, 1));

   // cube faces, each carrying the full texture
   {
      const float h = 1.0f;
      float v8[8][3] = {{-h, -h, -h}, {h, -h, -h}, {h, h, -h}, {-h, h, -h}, {-h, -h, h}, {h, -h, h}, {h, h, h}, {-h, h, h}};
      int f[6][4] = {{4, 5, 6, 7}, {1, 0, 3, 2}, {5, 1, 2, 6}, {0, 4, 7, 3}, {7, 6, 2, 3}, {0, 1, 5, 4}};
      float shade[6] = {1.0f, 0.8f, 0.9f, 0.85f, 1.0f, 0.7f};
      for (int i = 0; i < 6; i++) {
         b_quad3_uv(sCubes, v8[f[i][0]], v8[f[i][1]], v8[f[i][2]], v8[f[i][3]], C(shade[i], shade[i], shade[i], 1), 0, 0, 1, 1);
      }
   }

   char sub[80];
   snprintf(sub, sizeof(sub), "512X512 FEEDBACK  %s  TWIST %+.0f", kPreset[sPreset].name, sTwist * 1000.0f);
   ui_header(sUiTv, "MIRROR HALL", sub);
   ui_footer(sUiTv, "A: PRESET   ZL/ZR: TWIST   X: CLEAR   RIGHT STICK OR TOUCH: PAINT   B: MENU");

   ui_header(sUiDrc, "MIRROR HALL", "TOUCH THE PICTURE TO PAINT INTO THE FEEDBACK");
   if (g_hud) {
      ui_footer(sUiDrc, "DRAG ACROSS THE SQUARE   X: CLEAR   A: PRESET");
      b_rect(sUiDrc, 278.0f, 0.0f, 724.0f, VH, C(1, 1, 1, 0.0f));
   }
   if (sFailed) {
      b_text_center(sUiTv, VW * 0.5f, 340.0f, 3.0f, C(1.0f, 0.5f, 0.5f, 1), "RENDER TARGETS UNAVAILABLE");
      b_text_center(sUiDrc, VW * 0.5f, 340.0f, 3.0f, C(1.0f, 0.5f, 0.5f, 1), "RENDER TARGETS UNAVAILABLE");
   }
}

// runs inside the TV context, before either screen is drawn
static void mirror_prepass(void)
{
   if (!sMade) return;
   float t = (float)g_time;
   int src = sShown, dst = sShown ^ 1;

   gfx_rt_begin(&sRt[dst], 0.02f, 0.0f, 0.05f, 1.0f, sFirst);

   // 1. last frame, zoomed, rotated and slightly darkened
   Batch *feed = gfx_batch();
   float rot = kPreset[sPreset].rot + sTwist + 0.012f * fsin(t * 0.5f);
   float zoom = kPreset[sPreset].zoom;
   float cs = fcos(rot), sn = fsin(rot);
   float hs = RS * 0.5f * zoom;
   float cx = RS * 0.5f, cy = RS * 0.5f;
   float cx4[4] = {-hs, hs, hs, -hs}, cy4[4] = {-hs, -hs, hs, hs};
   float u4[4] = {0, 1, 1, 0}, v4[4] = {0, 0, 1, 1};
   Col fade = C(0.972f + 0.02f * fsin(t * 0.7f), 0.972f + 0.02f * fsin(t * 0.7f + 2.1f), 0.972f + 0.02f * fsin(t * 0.7f + 4.2f), 1.0f);
   Vtx q[4];
   for (int i = 0; i < 4; i++) {
      q[i].x = cx + cx4[i] * cs - cy4[i] * sn;
      q[i].y = cy + cx4[i] * sn + cy4[i] * cs;
      q[i].z = 0.0f;
      q[i].r = fade.r; q[i].g = fade.g; q[i].b = fade.b; q[i].a = 1.0f;
      q[i].u = u4[i]; q[i].v = v4[i];
   }
   b_tri(feed, q[0], q[1], q[2]);
   b_tri(feed, q[0], q[2], q[3]);
   gfx_use_texture(&sRt[src].tex);
   gfx_draw_batch(feed, sRtM, BLEND_OPAQUE, DEPTH_OFF, NULL);
   gfx_use_texture(NULL);

   // 2. fresh light added on top
   Batch *sh = gfx_batch();
   for (int i = 0; i < 5; i++) {
      float a = t * (0.6f + 0.23f * (float)i) + (float)i * 1.3f;
      float r = 90.0f + 60.0f * fsin(t * 0.4f + (float)i) + 40.0f * (float)i;
      float x = cx + fcos(a) * r, y = cy + fsin(a * 1.1f) * r;
      Col c = hsv(sHueSpin + (float)i * 0.19f, 0.8f, 1.0f, 0.9f);
      b_glow(sh, x, y, 26.0f + 14.0f * g_audio.beat, c);
   }
   float spin = t * 0.9f;
   for (int k = 0; k < 6; k++) {
      float a0 = spin + (float)k * 1.0472f, a1 = spin + (float)(k + 1) * 1.0472f;
      float rr = 70.0f + 30.0f * g_audio.beat;
      b_line(sh, cx + fcos(a0) * rr, cy + fsin(a0) * rr, cx + fcos(a1) * rr, cy + fsin(a1) * rr, 5.0f,
             hsv(sHueSpin + 0.5f + (float)k * 0.05f, 0.7f, 1.0f, 0.85f));
   }
   if (g_audio.beat > 0.6f) {
      b_ring(sh, cx, cy, 30.0f + 120.0f * (1.0f - g_audio.beat), 6.0f, hsv(sHueSpin + 0.25f, 0.5f, 1.0f, 0.7f), 36);
   }
   if (sPainting) {
      b_glow(sh, sPaint[0], sPaint[1], 44.0f, hsv(sHueSpin * 3.0f, 0.6f, 1.0f, 1.0f));
      b_glow(sh, sPaint[0], sPaint[1], 18.0f, C(1, 1, 1, 1));
   }
   gfx_draw_batch(sh, sRtM, BLEND_ADD, DEPTH_OFF, NULL);

   gfx_rt_end(&sRt[dst]);
   sShown = dst;
   sFirst = false;
}

static void mirror_draw(Target tg)
{
   if (!sMade) {
      gfx_draw_batch(tg == TARGET_TV ? sUiTv : sUiDrc, sUiM, BLEND_ALPHA, DEPTH_OFF, NULL);
      return;
   }
   const Tex *tex = &sRt[sShown].tex;
   gfx_use_texture(tex);
   gfx_draw_batch(tg == TARGET_TV ? sBgTv : sBgDrc, sUiM, BLEND_OPAQUE, DEPTH_OFF, NULL);

   // the sharp square in the middle
   Batch *sq = gfx_batch();
   b_rect_uv(sq, 280.0f, 0.0f, 720.0f, 720.0f, 0, 0, 1, 1, C(1, 1, 1, 1));
   gfx_draw_batch(sq, sUiM, BLEND_OPAQUE, DEPTH_OFF, NULL);

   if (tg == TARGET_TV) {
      for (int i = 0; i < 2; i++) gfx_draw_batch(sCubes, sCubeVP[i], BLEND_OPAQUE, DEPTH_ON, NULL);
   }
   gfx_use_texture(NULL);
   gfx_draw_batch(tg == TARGET_TV ? sUiTv : sUiDrc, sUiM, BLEND_ALPHA, DEPTH_OFF, NULL);
}

const Scene scene_mirror = {
   "MIRROR HALL", "RENDER-TO-TEXTURE VIDEO FEEDBACK, DRAW ON IT", mirror_enter, mirror_leave, mirror_update, mirror_prepass, mirror_draw, 26.0f,
};
