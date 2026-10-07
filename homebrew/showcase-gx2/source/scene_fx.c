// Shader Lab: four full-screen pixel-shader programs written in GLSL and compiled
// ahead of time to Wii U Latte microcode. Real loops, branches, atan, pow, log2.
// The TV shows the selected program, the GamePad runs the next one at the same time.

#include "app.h"
#include "audio.h"
#include "gfx.h"
#include "ui.h"

#include <math.h>
#include <stdio.h>

#define MODES 4
static const char *kName[MODES] = {"PLASMA", "RAYMARCH", "JULIA SET", "TUNNEL"};
static const char *kNote[MODES] = {
   "DOMAIN-WARPED SINE FIELDS",
   "56-STEP SPHERE TRACING, SMOOTH UNION, FRESNEL",
   "80-ITERATION LOOP WITH SMOOTH COLOURING",
   "ATAN POLAR MAPPING AND A CHECKER WARP",
};

static int sMode;
static float sPanX, sPanY, sZoom = 1.0f;
static float sUiM[16];
static Batch *sTv, *sDrc;

static void fx_enter(void) {}
static void fx_leave(void) {}

static void set_mode(int m)
{
   sMode = (m + MODES) % MODES;
   audio_sfx(1);
}

static void fx_update(float dt)
{
   if (PRESSED(VPAD_BUTTON_A) || PRESSED(VPAD_BUTTON_RIGHT)) set_mode(sMode + 1);
   if (PRESSED(VPAD_BUTTON_LEFT)) set_mode(sMode - 1);

   // pan/zoom drive the Julia set, and are harmless for the others
   sPanX += g_in.rx * dt * 0.8f / sZoom;
   sPanY += g_in.ry * dt * 0.8f / sZoom;
   if (HELD(VPAD_BUTTON_ZR)) sZoom *= 1.0f + dt * 1.2f;
   if (HELD(VPAD_BUTTON_ZL)) sZoom /= 1.0f + dt * 1.2f;
   if (sZoom < 0.4f) sZoom = 0.4f;
   if (sZoom > 400.0f) sZoom = 400.0f;
   if (PRESSED(VPAD_BUTTON_X)) { sPanX = sPanY = 0.0f; sZoom = 1.0f; }

   if (g_in.touchStart) {
      for (int i = 0; i < MODES; i++) {
         if (ui_hit(g_in.tx, g_in.ty, 30.0f + (float)i * 300.0f, 628.0f, 280.0f, 56.0f)) set_mode(i);
      }
   }
   if (g_in.touch && g_in.ty < 620.0f) {
      sPanX += ((g_in.tx / VW - 0.5f) * 2.0f) * dt * 0.8f / sZoom;
      sPanY += -((g_in.ty / VH - 0.5f) * 2.0f) * dt * 0.8f / sZoom;
   }

   m4_ortho_ui(sUiM);
   sTv = gfx_batch();
   sDrc = gfx_batch();

   char sub[96];
   snprintf(sub, sizeof(sub), "%s: %s", kName[sMode], kNote[sMode]);
   ui_header(sTv, "SHADER LAB", sub);
   ui_footer(sTv, "A: NEXT SHADER   RIGHT STICK: PAN   ZL/ZR: ZOOM   X: RESET   B: MENU");

   ui_header(sDrc, "SHADER LAB", "THE GAMEPAD RUNS A DIFFERENT SHADER");
   if (g_hud) {
      for (int i = 0; i < MODES; i++) {
         ui_button(sDrc, 30.0f + (float)i * 300.0f, 628.0f, 280.0f, 56.0f, kName[i], i == sMode, hsv(0.08f + 0.22f * (float)i, 0.6f, 0.95f, 1));
      }
      b_text_shadow(sDrc, 30.0f, 590.0f, 2.0f, C(1, 1, 1, 0.9f), "TAP A SHADER FOR THE TV   DRAG TO PAN");
   }
}

static void fx_draw(Target tg)
{
   float t = (float)g_time;
   float au = g_audio.master * 0.6f + g_audio.beat * 0.4f;
   int mode = tg == TARGET_TV ? sMode : (sMode + 1) % MODES;
   gfx_draw_fx((float)mode, VW / VH, t, au, sPanX, sPanY, sZoom, 0.0f);
   gfx_draw_batch(tg == TARGET_TV ? sTv : sDrc, sUiM, BLEND_ALPHA, DEPTH_OFF, NULL);
}

const Scene scene_fx = {
   "SHADER LAB", "RAYMARCHING AND FRACTALS RUNNING ON THE GPU", fx_enter, fx_leave, fx_update, NULL, fx_draw, 28.0f,
};
