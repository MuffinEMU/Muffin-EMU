// Menu: a synthwave sunset with the rotating muffin, and the scene list.
// Identical on the TV and the GamePad; the GamePad rows are touchable.

#include "app.h"
#include "audio.h"
#include "gfx.h"
#include "muffin.h"
#include "ui.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#define ROWS 8
#define ROW_X 650.0f
#define ROW_Y 168.0f
#define ROW_W 590.0f
#define ROW_H 56.0f
#define ROW_STEP 60.0f

static int sSel;
static float sStickLatch;
static Batch *sBg, *sGlow, *sUi;
static float sViewProj[16];
static float sModel[16];

static float hash01(uint32_t a)
{
   a = (a ^ (a >> 16)) * 0x45d9f3bu;
   a = (a ^ (a >> 16)) * 0x45d9f3bu;
   a ^= a >> 16;
   return (float)(a & 0xFFFFu) / 65535.0f;
}

static void hub_enter(void)
{
   muffin_build();
}

static void hub_leave(void) {}

static void activate(int i)
{
   sSel = i;
   audio_sfx(1);
   app_goto(i + 1);
}

static void build_background(float t)
{
   const float horizon = 470.0f;
   float beat = g_audio.beat;

   ui_sky(sBg, C(0.05f, 0.03f, 0.20f, 1), C(0.50f, 0.16f, 0.46f, 1), C(1.0f, 0.55f, 0.36f, 1));
   // ground
   b_rect_grad(sBg, 0, horizon, VW, VH - horizon, C(0.20f, 0.04f, 0.28f, 1), C(0.05f, 0.01f, 0.12f, 1));

   // striped sun behind the muffin
   float sx = 330.0f, sy = 395.0f, sr = 175.0f + 10.0f * beat;
   b_circle(sBg, sx, sy, sr, C(1.0f, 0.78f, 0.30f, 1), 48);
   b_circle(sBg, sx, sy + sr * 0.35f, sr * 0.65f, C(1.0f, 0.45f, 0.45f, 0.55f), 40);
   for (int i = 0; i < 7; i++) {
      float y = sy + 8.0f + (float)i * 22.0f;
      float h = 3.0f + (float)i * 2.2f;
      if (y + h < horizon) b_rect(sBg, sx - sr, y, sr * 2.0f, h, C(0.45f, 0.13f, 0.40f, 1));
   }
   b_rect(sBg, 0, horizon, VW, 3.0f, C(1.0f, 0.7f, 0.9f, 0.9f));

   // perspective grid
   for (int k = -16; k <= 16; k++) {
      b_line(sBg, 640.0f + (float)k * 14.0f, horizon, 640.0f + (float)k * 150.0f, VH, 2.0f, C(1.0f, 0.3f, 0.8f, 0.55f));
   }
   float scroll = t * 0.35f;
   scroll -= floorf(scroll);
   for (int i = 0; i < 10; i++) {
      float z = ((float)i + scroll) / 10.0f;
      float y = horizon + (VH - horizon) * z * z;
      b_line(sBg, 0, y, VW, y, 1.0f + 2.5f * z, C(1.0f, 0.35f, 0.85f, 0.15f + 0.5f * z));
   }

   // stars
   for (int i = 0; i < 90; i++) {
      float x = hash01((uint32_t)i * 3u) * VW;
      float y = hash01((uint32_t)i * 3u + 1u) * (horizon - 120.0f);
      float tw = 0.5f + 0.5f * fsin(t * (1.0f + hash01((uint32_t)i * 3u + 2u) * 3.0f) + (float)i);
      float s = 5.0f + 7.0f * tw;
      b_glow(sGlow, x, y, s, C(1.0f, 0.95f, 0.85f, 0.35f + 0.5f * tw));
   }
   b_glow(sGlow, sx, sy, 420.0f + 80.0f * beat, C(1.0f, 0.55f, 0.35f, 0.30f + 0.20f * beat));
   // light pool under the muffin
   b_glow(sGlow, 330.0f, 590.0f, 230.0f, C(1.0f, 0.4f, 0.8f, 0.30f + 0.2f * beat));
}

static void build_menu(float t)
{
   // title
   static const char *title = "MUFFINEMU";
   float x = 44.0f;
   for (int i = 0; title[i]; i++) {
      char one[2] = {title[i], 0};
      float y = 34.0f + 7.0f * fsin(t * 3.0f + (float)i * 0.7f);
      Col c = hsv(0.08f + 0.04f * fsin(t + (float)i), 0.55f, 1.0f, 1.0f);
      b_text(sUi, x + 5.0f, y + 5.0f, 9.0f, C(0.2f, 0.0f, 0.25f, 0.8f), one);
      b_text(sUi, x, y, 9.0f, c, one);
      x += 6.0f * 9.0f;
   }
   b_text_shadow(sUi, 48.0f, 108.0f, 4.6f, C(1.0f, 0.95f, 0.85f, 1), "SHOWCASE");
   b_text_shadow(sUi, 50.0f, 156.0f, 2.2f, C(1.0f, 0.82f, 0.9f, 0.95f), "THE WII U, IN YOUR HANDS.");

   // rows
   for (int i = 0; i < ROWS; i++) {
      const Scene *sc = app_scene(i + 1);
      float y = ROW_Y + (float)i * ROW_STEP;
      bool sel = (i == sSel);
      float pulse = sel ? 0.5f + 0.5f * fsin(t * 6.0f) : 0.0f;
      b_rect(sUi, ROW_X - 3.0f, y - 3.0f, ROW_W + 6.0f, ROW_H + 6.0f, C(0, 0, 0, sel ? 0.45f : 0.25f));
      if (sel) {
         b_rect_gradx(sUi, ROW_X, y, ROW_W, ROW_H, C(1.0f, 0.55f, 0.30f, 0.95f), C(0.85f, 0.20f, 0.55f, 0.95f));
         b_rect(sUi, ROW_X - 14.0f - 4.0f * pulse, y + 8.0f, 8.0f, ROW_H - 16.0f, C(1.0f, 0.9f, 0.5f, 1));
      } else {
         b_rect_gradx(sUi, ROW_X, y, ROW_W, ROW_H, C(0.16f, 0.07f, 0.30f, 0.80f), C(0.10f, 0.05f, 0.22f, 0.80f));
      }
      char num[4];
      snprintf(num, sizeof(num), "%d", i + 1);
      b_text_shadow(sUi, ROW_X + 14.0f, y + 12.0f, 4.0f, sel ? C(1, 1, 1, 1) : C(1.0f, 0.7f, 0.5f, 1), num);
      b_text_shadow(sUi, ROW_X + 56.0f, y + 7.0f, 3.2f, sel ? C(1, 1, 1, 1) : C(1.0f, 0.92f, 0.85f, 1), sc->name);
      b_text(sUi, ROW_X + 58.0f, y + 36.0f, 1.55f, sel ? C(1.0f, 0.95f, 0.85f, 1) : C(0.78f, 0.70f, 0.95f, 0.95f), sc->feat);
   }

   // music status
   if (!g_audio.ready) {
      char buf[48];
      snprintf(buf, sizeof(buf), "SYNTHESIZING MUSIC ON CORE 2  %d%%", g_audio.synthPct);
      b_text_shadow(sUi, 48.0f, 630.0f, 2.0f, C(1.0f, 0.9f, 0.6f, 1), buf);
      ui_bar(sUi, 48.0f, 654.0f, 360.0f, 12.0f, (float)g_audio.synthPct / 100.0f, C(1.0f, 0.65f, 0.3f, 1));
   } else {
      char buf[64];
      snprintf(buf, sizeof(buf), "%s  BAR %d/%d  %s", g_audio.muted ? "MUTED" : "NOW PLAYING", g_audio.bar + 1, SONG_BARS,
               synth_chord_name(g_audio.bar));
      b_text_shadow(sUi, 48.0f, 632.0f, 2.0f, C(1.0f, 0.9f, 0.6f, 1), buf);
      ui_music_strip(sUi, 48.0f, 656.0f);
   }
   if (g_hud) {
      ui_footer(sUi, "UP/DOWN + A: START   TOUCH A ROW   Y: AUTO TOUR   -: MUTE   +: HIDE TEXT");
   }
}

static void hub_update(float dt)
{
   (void)dt;
   float t = (float)g_time;

   // selection
   int step = 0;
   if (PRESSED(VPAD_BUTTON_DOWN)) step = 1;
   if (PRESSED(VPAD_BUTTON_UP)) step = -1;
   if (g_in.ly < -0.6f && sStickLatch >= -0.6f) step = 1;
   if (g_in.ly > 0.6f && sStickLatch <= 0.6f) step = -1;
   sStickLatch = g_in.ly;
   if (step) {
      sSel = (sSel + step + ROWS) % ROWS;
      audio_sfx(0);
   }
   if (PRESSED(VPAD_BUTTON_A)) activate(sSel);
   if (PRESSED(VPAD_BUTTON_Y)) {
      g_tour = true;
      audio_sfx(1);
      app_goto(1);
   }
   if (g_in.touchStart) {
      for (int i = 0; i < ROWS; i++) {
         if (ui_hit(g_in.tx, g_in.ty, ROW_X, ROW_Y + (float)i * ROW_STEP, ROW_W, ROW_H + 4.0f)) {
            activate(i);
            break;
         }
      }
   }

   sBg = gfx_batch();
   sGlow = gfx_batch();
   sUi = gfx_batch();
   build_background(t);
   build_menu(t);

   // the hero muffin, orbited by the camera so its baked lighting stays put
   float a = t * 0.55f;
   float eye[3] = {fsin(a) * 5.6f, 2.5f + 0.35f * fsin(t * 0.7f), fcos(a) * 5.6f};
   float v[16], p[16], shift[16], pv[16];
   m4_lookat(v, eye[0], eye[1], eye[2], 0.0f, 1.15f, 0.0f);
   m4_persp(p, 0.78f, VW / VH, 0.1f, 60.0f);
   m4_translate(shift, -0.36f, -0.10f, 0.0f);
   m4_mul(pv, p, v);
   m4_mul(sViewProj, shift, pv);
   m4_translate(sModel, 0.0f, 0.12f * fsin(t * 1.4f) + 0.5f * g_audio.beat * 0.2f, 0.0f);
}

static void hub_draw(Target tg)
{
   (void)tg;
   float ui[16];
   m4_ortho_ui(ui);
   gfx_draw_batch(sBg, ui, BLEND_ALPHA, DEPTH_OFF, NULL);
   gfx_draw_batch(sGlow, ui, BLEND_ADD, DEPTH_OFF, NULL);
   muffin_draw(sModel, sViewProj, NULL);
   gfx_draw_batch(sUi, ui, BLEND_ALPHA, DEPTH_OFF, NULL);
}

const Scene scene_hub = {
   "MENU", "", hub_enter, hub_leave, hub_update, NULL, hub_draw, 0.0f,
};
