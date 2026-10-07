// Input Lab: everything the GamePad reports, live. The GamePad draws itself with
// each button lit while held, both sticks, a touch trail, and the motion sensors.
// The TV shows a slab tilted by the accelerometer and gyro, plus raw numbers.
// A rumbles the pad.

#include "app.h"
#include "audio.h"
#include "gfx.h"
#include "ui.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#define TRAIL 28

static float sTrail[TRAIL][2];
static int sTrailN;
static float sUiM[16], sVP[16];
static Batch *sTvUi, *sDrcUi, *sSlab;
static float sAngBase[3];
static float sSlabAng[3];
static uint32_t sEverPressed;
static int sRumble;

static void inp_enter(void) { sTrailN = 0; sEverPressed = 0; }
static void inp_leave(void) {}

static void btn(Batch *b, uint32_t bit, float cx, float cy, float r, const char *label, Col c)
{
   bool on = HELD(bit);
   b_circle(b, cx, cy, r + 3.0f, C(0, 0, 0, 0.6f), 24);
   b_circle(b, cx, cy, r, on ? c : CMUL(c, 0.22f), 24);
   if (on) b_glow(b, cx, cy, r * 2.4f, CA(c, 0.5f));
   float s = r > 26.0f ? 3.0f : 2.0f;
   float w = text_width(label, s);
   b_text(b, cx - w * 0.5f, cy - 3.5f * s, s, on ? C(0, 0, 0, 1) : C(1, 1, 1, 0.75f), label);
}

static void bar(Batch *b, float x, float y, float w, float v, float range, Col c, const char *label)
{
   b_text_shadow(b, x, y - 22.0f, 2.0f, C(1, 1, 1, 0.9f), label);
   b_rect(b, x, y, w, 14.0f, C(0, 0, 0, 0.6f));
   b_rect(b, x + w * 0.5f - 1.0f, y - 3.0f, 2.0f, 20.0f, C(1, 1, 1, 0.5f));
   float f = v / range;
   if (f > 1.0f) f = 1.0f;
   if (f < -1.0f) f = -1.0f;
   float bw = w * 0.5f * fabsf(f);
   b_rect(b, f >= 0 ? x + w * 0.5f : x + w * 0.5f - bw, y, bw, 14.0f, c);
}

static void stick(Batch *b, float cx, float cy, float sx, float sy, bool click)
{
   b_circle(b, cx, cy, 66.0f, C(0, 0, 0, 0.7f), 32);
   b_ring(b, cx, cy, 62.0f, 3.0f, C(1, 1, 1, 0.35f), 32);
   b_circle(b, cx + sx * 40.0f, cy - sy * 40.0f, 30.0f, click ? C(1.0f, 0.8f, 0.3f, 1) : C(0.55f, 0.6f, 0.75f, 1), 24);
   b_ring(b, cx + sx * 40.0f, cy - sy * 40.0f, 30.0f, 3.0f, C(1, 1, 1, 0.6f), 24);
}

static void inp_update(float dt)
{
   (void)dt;
   m4_ortho_ui(sUiM);
   sEverPressed |= g_in.hold;

   if (g_in.touch) {
      if (sTrailN < TRAIL) {
         sTrailN++;
      }
      memmove(&sTrail[1], &sTrail[0], sizeof(sTrail[0]) * (TRAIL - 1));
      sTrail[0][0] = g_in.tx;
      sTrail[0][1] = g_in.ty;
   } else if (sTrailN > 0) {
      sTrailN--;
   }

   if (PRESSED(VPAD_BUTTON_A)) {
      static const uint8_t pat[8] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
      VPADControlMotor(VPAD_CHAN_0, pat, 8);
      sRumble = 30;
   }
   if (sRumble > 0) sRumble--;
   if (PRESSED(VPAD_BUTTON_X)) {
      sAngBase[0] = g_in.angx; sAngBase[1] = g_in.angy; sAngBase[2] = g_in.angz;
   }

   sTvUi = gfx_batch();
   sDrcUi = gfx_batch();
   sSlab = gfx_batch();

   // slab orientation: gravity gives roll and pitch, the integrated gyro gives yaw
   float roll = atan2f(g_in.ax, g_in.ay + 1e-4f);
   float pitch = atan2f(g_in.az, sqrtf(g_in.ax * g_in.ax + g_in.ay * g_in.ay) + 1e-4f);
   float yaw = (g_in.angy - sAngBase[1]) * 6.28318f;
   sSlabAng[0] = pitch; sSlabAng[1] = yaw; sSlabAng[2] = roll;

   float p[16], v[16], pv[16];
   m4_persp(p, 0.8f, VW / VH, 0.1f, 50.0f);
   m4_lookat(v, 0.0f, 1.2f, 7.0f, 0.0f, 0.0f, 0.0f);
   m4_mul(pv, p, v);
   float rx[16], ry[16], rz[16], r[16], r2[16], shift[16], full[16];
   m4_rot_x(rx, sSlabAng[0]);
   m4_rot_y(ry, sSlabAng[1]);
   m4_rot_z(rz, sSlabAng[2]);
   m4_mul(r, ry, rx);
   m4_mul(r2, r, rz);
   m4_translate(shift, -0.38f, 0.0f, 0.0f);
   m4_mul(full, pv, r2);
   m4_mul(sVP, shift, full);

   b_box(sSlab, 0, 0, 0, 2.6f, 0.22f, 1.6f, C(0.78f, 0.80f, 0.86f, 1));
   b_box(sSlab, 0, 0.23f, -0.1f, 1.7f, 0.04f, 1.0f, C(0.12f, 0.14f, 0.22f, 1));   // screen
   b_box(sSlab, -2.0f, 0.24f, 0.25f, 0.28f, 0.05f, 0.28f, C(0.3f, 0.3f, 0.35f, 1));
   b_box(sSlab, 2.0f, 0.24f, 0.45f, 0.28f, 0.05f, 0.28f, C(0.3f, 0.3f, 0.35f, 1));
   b_box(sSlab, 1.9f, 0.24f, -0.5f, 0.12f, 0.05f, 0.12f, C(1.0f, 0.4f, 0.3f, 1));
   b_box(sSlab, 2.2f, 0.24f, -0.7f, 0.12f, 0.05f, 0.12f, C(0.4f, 1.0f, 0.4f, 1));
   b_box(sSlab, -1.9f, 0.24f, -0.5f, 0.12f, 0.05f, 0.12f, C(0.4f, 0.6f, 1.0f, 1));
   b_box(sSlab, -2.2f, 0.24f, -0.7f, 0.12f, 0.05f, 0.12f, C(1.0f, 0.9f, 0.3f, 1));

   // TV numbers
   ui_header(sTvUi, "INPUT LAB", g_in.ok ? "GAMEPAD LIVE" : "NO GAMEPAD SAMPLES");
   if (g_hud) {
      float x = 760.0f, y = 110.0f;
      ui_panel(sTvUi, x - 20.0f, y - 14.0f, 520.0f, 500.0f, 0.55f);
      char buf[80];
      snprintf(buf, sizeof(buf), "HOLD    %08X", (unsigned)g_in.hold);              b_text_shadow(sTvUi, x, y, 2.2f, C(1, 1, 1, 1), buf); y += 34.0f;
      snprintf(buf, sizeof(buf), "LSTICK  %+.2f %+.2f", g_in.lx, g_in.ly);          b_text_shadow(sTvUi, x, y, 2.2f, C(0.7f, 0.9f, 1, 1), buf); y += 34.0f;
      snprintf(buf, sizeof(buf), "RSTICK  %+.2f %+.2f", g_in.rx, g_in.ry);          b_text_shadow(sTvUi, x, y, 2.2f, C(0.7f, 0.9f, 1, 1), buf); y += 34.0f;
      snprintf(buf, sizeof(buf), "TOUCH   %s %4.0f %4.0f", g_in.touch ? "DOWN" : "UP  ", g_in.tx, g_in.ty); b_text_shadow(sTvUi, x, y, 2.2f, C(1, 0.9f, 0.6f, 1), buf); y += 34.0f;
      snprintf(buf, sizeof(buf), "ACCEL   %+.2f %+.2f %+.2f", g_in.ax, g_in.ay, g_in.az); b_text_shadow(sTvUi, x, y, 2.2f, C(0.7f, 1, 0.7f, 1), buf); y += 34.0f;
      snprintf(buf, sizeof(buf), "GYRO    %+.2f %+.2f %+.2f", g_in.gx, g_in.gy, g_in.gz);  b_text_shadow(sTvUi, x, y, 2.2f, C(0.7f, 1, 0.7f, 1), buf); y += 34.0f;
      snprintf(buf, sizeof(buf), "ANGLE   %+.2f %+.2f %+.2f", g_in.angx, g_in.angy, g_in.angz); b_text_shadow(sTvUi, x, y, 2.2f, C(0.7f, 1, 0.7f, 1), buf); y += 44.0f;
      int seen = 0;
      for (int i = 0; i < 32; i++) if (sEverPressed & (1u << i)) seen++;
      snprintf(buf, sizeof(buf), "DISTINCT INPUTS USED  %d", seen);
      b_text_shadow(sTvUi, x, y, 2.2f, C(1.0f, 0.85f, 0.4f, 1), buf); y += 34.0f;
      b_text_shadow(sTvUi, x, y, 2.0f, C(1, 1, 1, 0.7f), "PRESS EVERYTHING");
      ui_footer(sTvUi, "A: RUMBLE   X: RE-CENTRE YAW   TILT THE PAD TO TILT THE SLAB   B: MENU");
   }

   // GamePad diagram
   Batch *d = sDrcUi;
   ui_header(d, "THE GAMEPAD", g_in.touch ? "TOUCH DOWN" : "TOUCH THE SCREEN");
   b_rect(d, 110.0f, 110.0f, 1060.0f, 500.0f, C(0.16f, 0.17f, 0.22f, 1));
   b_rect(d, 110.0f, 110.0f, 1060.0f, 4.0f, C(1, 1, 1, 0.15f));
   b_rect(d, 400.0f, 150.0f, 480.0f, 270.0f, C(0.02f, 0.03f, 0.08f, 1));
   b_text_center(d, 640.0f, 270.0f, 2.2f, C(0.4f, 0.5f, 0.8f, 0.8f), "SCREEN");

   stick(d, 245.0f, 250.0f, g_in.lx, g_in.ly, HELD(VPAD_BUTTON_STICK_L));
   stick(d, 1035.0f, 420.0f, g_in.rx, g_in.ry, HELD(VPAD_BUTTON_STICK_R));

   // d-pad
   struct { uint32_t bit; float dx, dy; } dp[4] = {{VPAD_BUTTON_UP, 0, -50}, {VPAD_BUTTON_DOWN, 0, 50}, {VPAD_BUTTON_LEFT, -50, 0}, {VPAD_BUTTON_RIGHT, 50, 0}};
   for (int i = 0; i < 4; i++) {
      bool on = HELD(dp[i].bit);
      b_rect(d, 245.0f + dp[i].dx - 22.0f, 440.0f + dp[i].dy - 22.0f, 44.0f, 44.0f, on ? C(1.0f, 0.85f, 0.3f, 1) : C(0.08f, 0.08f, 0.12f, 1));
   }
   b_rect(d, 245.0f - 22.0f, 440.0f - 22.0f, 44.0f, 44.0f, C(0.08f, 0.08f, 0.12f, 1));

   btn(d, VPAD_BUTTON_A, 1100.0f, 250.0f, 32.0f, "A", C(1.0f, 0.35f, 0.35f, 1));
   btn(d, VPAD_BUTTON_B, 1035.0f, 310.0f, 32.0f, "B", C(1.0f, 0.85f, 0.3f, 1));
   btn(d, VPAD_BUTTON_X, 1035.0f, 190.0f, 32.0f, "X", C(0.35f, 0.6f, 1.0f, 1));
   btn(d, VPAD_BUTTON_Y, 970.0f, 250.0f, 32.0f, "Y", C(0.4f, 0.95f, 0.5f, 1));
   btn(d, VPAD_BUTTON_MINUS, 560.0f, 520.0f, 18.0f, "-", C(0.8f, 0.8f, 0.9f, 1));
   btn(d, VPAD_BUTTON_PLUS, 720.0f, 520.0f, 18.0f, "+", C(0.8f, 0.8f, 0.9f, 1));
   btn(d, VPAD_BUTTON_HOME, 640.0f, 560.0f, 24.0f, "H", C(0.8f, 0.8f, 0.9f, 1));
   struct { uint32_t bit; float x, w; const char *l; } sh[4] = {
      {VPAD_BUTTON_ZL, 130.0f, 160.0f, "ZL"}, {VPAD_BUTTON_L, 300.0f, 120.0f, "L"},
      {VPAD_BUTTON_R, 860.0f, 120.0f, "R"}, {VPAD_BUTTON_ZR, 990.0f, 160.0f, "ZR"}};
   for (int i = 0; i < 4; i++) {
      bool on = HELD(sh[i].bit);
      b_rect(d, sh[i].x, 80.0f, sh[i].w, 26.0f, on ? C(1.0f, 0.55f, 0.3f, 1) : C(0.25f, 0.26f, 0.34f, 1));
      b_text_center(d, sh[i].x + sh[i].w * 0.5f, 85.0f, 2.2f, on ? C(0, 0, 0, 1) : C(1, 1, 1, 0.7f), sh[i].l);
   }

   // sensors along the bottom of the left half
   bar(d, 130.0f, 560.0f, 200.0f, g_in.ax, 1.5f, C(1.0f, 0.5f, 0.5f, 1), "ACC X");
   bar(d, 130.0f, 610.0f, 200.0f, g_in.ay, 1.5f, C(0.5f, 1.0f, 0.5f, 1), "ACC Y");
   bar(d, 350.0f, 560.0f, 180.0f, g_in.az, 1.5f, C(0.5f, 0.6f, 1.0f, 1), "ACC Z");
   bar(d, 350.0f, 610.0f, 180.0f, g_in.gy, 0.6f, C(1.0f, 0.8f, 0.4f, 1), "GYRO Y");
   bar(d, 760.0f, 560.0f, 190.0f, g_in.gx, 0.6f, C(1.0f, 0.8f, 0.4f, 1), "GYRO X");
   bar(d, 760.0f, 610.0f, 190.0f, g_in.gz, 0.6f, C(1.0f, 0.8f, 0.4f, 1), "GYRO Z");

   // touch trail
   for (int i = 0; i < sTrailN; i++) {
      float k = 1.0f - (float)i / (float)TRAIL;
      b_glow(d, sTrail[i][0], sTrail[i][1], 14.0f + 26.0f * k, C(0.5f + 0.5f * k, 0.9f, 1.0f, 0.55f * k));
   }
   if (g_in.touch) b_ring(d, g_in.tx, g_in.ty, 38.0f, 4.0f, C(1, 1, 1, 0.95f), 28);
   if (sRumble > 0) b_rect(d, 0, 0, VW, 6.0f, C(1.0f, 0.4f, 0.3f, 1));
   ui_footer(d, "PRESS ANYTHING   A: RUMBLE   X: RE-CENTRE");
}

static void inp_draw(Target tg)
{
   if (tg == TARGET_TV) {
      Batch *bg = gfx_batch();
      ui_sky(bg, C(0.04f, 0.04f, 0.12f, 1), C(0.08f, 0.07f, 0.20f, 1), C(0.14f, 0.09f, 0.26f, 1));
      gfx_draw_batch(bg, sUiM, BLEND_OPAQUE, DEPTH_OFF, NULL);
      gfx_draw_batch(sSlab, sVP, BLEND_OPAQUE, DEPTH_ON, NULL);
      gfx_draw_batch(sTvUi, sUiM, BLEND_ALPHA, DEPTH_OFF, NULL);
   } else {
      Batch *bg = gfx_batch();
      b_rect(bg, 0, 0, VW, VH, C(0.05f, 0.05f, 0.09f, 1));
      gfx_draw_batch(bg, sUiM, BLEND_OPAQUE, DEPTH_OFF, NULL);
      gfx_draw_batch(sDrcUi, sUiM, BLEND_ALPHA, DEPTH_OFF, NULL);
   }
}

const Scene scene_input = {
   "INPUT LAB", "BUTTONS, STICKS, TOUCH, GYRO AND RUMBLE", inp_enter, inp_leave, inp_update, NULL, inp_draw, 14.0f,
};
