// Particle Storm: up to 3,600 additive glow sprites simulated on the CPU every frame.
// Four emitters (fountain, galaxy, fireworks, touch stream). The TV shows the 3D view;
// the GamePad shows a top-down radar of the same particles and takes touch input:
// touching the radar pulls every particle toward that point.

#include "app.h"
#include "audio.h"
#include "gfx.h"
#include "ui.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#define MAXP 3600

typedef struct { float p[3], v[3], life, maxLife, hue, size; } Particle;

enum { M_FOUNTAIN, M_GALAXY, M_FIREWORKS, M_STREAM, M_COUNT };
static const char *kModeName[M_COUNT] = {"FOUNTAIN", "GALAXY", "FIREWORKS", "STREAM"};
static const int kCounts[5] = {256, 600, 1200, 2200, 3600};

static Particle sP[MAXP];
static int sMode, sCountIdx = 2;
static float sBurstTimer, sBurstHue;
static float sBurstPos[3];
static float sEmitter[3];
static bool sAttract;
static float sAttractPos[3];
static float sCamA;
static uint32_t sRng = 0xC0FFEE11u;

static Batch *sWorld, *sRadar;
static float sViewProj[16], sUiM[16];

#define RADAR_X 640.0f
#define RADAR_Y 400.0f
#define RADAR_S 20.0f

static float rnd(void)
{
   sRng ^= sRng << 13;
   sRng ^= sRng >> 17;
   sRng ^= sRng << 5;
   return (float)(sRng & 0xFFFFFFu) * (1.0f / 16777216.0f);
}

static void spawn(Particle *p, int mode)
{
   float a = rnd() * 6.28318f;
   switch (mode) {
   case M_FOUNTAIN: {
      float c = rnd() * 0.38f, sp = 9.0f + rnd() * 5.0f;
      p->p[0] = (rnd() - 0.5f) * 0.4f; p->p[1] = 0.2f; p->p[2] = (rnd() - 0.5f) * 0.4f;
      p->v[0] = sp * fsin(c) * fcos(a); p->v[1] = sp * fcos(c); p->v[2] = sp * fsin(c) * fsin(a);
      p->maxLife = p->life = 2.8f + rnd() * 2.2f;
      p->hue = 0.52f + 0.28f * rnd() + (float)g_time * 0.03f;
      p->size = 0.9f + rnd() * 0.6f;
      break;
   }
   case M_GALAXY: {
      float r = 0.8f + 12.0f * powf(rnd(), 1.5f);
      float arm = floorf(rnd() * 3.0f) * 2.0944f;
      float th = arm + r * 0.38f + (rnd() - 0.5f) * 0.7f;
      p->v[0] = r; p->v[1] = th; p->v[2] = 5.0f / (r + 3.0f);
      p->p[0] = r * fcos(th); p->p[1] = (rnd() - 0.5f) * 1.6f / (1.0f + r * 0.25f); p->p[2] = r * fsin(th);
      p->maxLife = p->life = 1e9f;
      p->hue = 0.62f - r * 0.035f + 0.1f * rnd();
      p->size = 0.6f + rnd() * 0.9f;
      break;
   }
   case M_FIREWORKS: {
      float z = rnd() * 2.0f - 1.0f, rr = sqrtf(1.0f - z * z), sp = 4.0f + rnd() * 5.5f;
      p->p[0] = sBurstPos[0]; p->p[1] = sBurstPos[1]; p->p[2] = sBurstPos[2];
      p->v[0] = rr * fcos(a) * sp; p->v[1] = z * sp; p->v[2] = rr * fsin(a) * sp;
      p->maxLife = p->life = 1.5f + rnd() * 1.2f;
      p->hue = sBurstHue + 0.08f * rnd();
      p->size = 0.7f + rnd() * 0.6f;
      break;
   }
   default: {
      p->p[0] = sEmitter[0] + (rnd() - 0.5f) * 0.3f; p->p[1] = sEmitter[1] + (rnd() - 0.5f) * 0.3f;
      p->p[2] = sEmitter[2] + (rnd() - 0.5f) * 0.3f;
      p->v[0] = (rnd() - 0.5f) * 2.2f; p->v[1] = 0.5f + rnd() * 2.0f; p->v[2] = (rnd() - 0.5f) * 2.2f;
      p->maxLife = p->life = 1.6f + rnd() * 1.6f;
      p->hue = (float)g_time * 0.12f + rnd() * 0.12f;
      p->size = 0.8f + rnd() * 0.5f;
      break;
   }
   }
}

static void reset_all(void)
{
   for (int i = 0; i < MAXP; i++) {
      spawn(&sP[i], sMode);
      if (sMode == M_FOUNTAIN || sMode == M_STREAM) sP[i].life *= rnd();   // stagger
      if (sMode == M_FIREWORKS) sP[i].life = 0.0f;
   }
   sBurstTimer = 0.2f;
}

static void part_enter(void) { reset_all(); }
static void part_leave(void) {}

static void set_mode(int m)
{
   sMode = (m + M_COUNT) % M_COUNT;
   reset_all();
   audio_sfx(1);
}

static void part_update(float dt)
{
   float t = (float)g_time;
   int count = kCounts[sCountIdx];

   if (PRESSED(VPAD_BUTTON_A) || PRESSED(VPAD_BUTTON_RIGHT)) set_mode(sMode + 1);
   if (PRESSED(VPAD_BUTTON_LEFT)) set_mode(sMode - 1);
   if (PRESSED(VPAD_BUTTON_ZR) || PRESSED(VPAD_BUTTON_UP)) {
      if (sCountIdx < 4) sCountIdx++;
      audio_sfx(0);
   }
   if (PRESSED(VPAD_BUTTON_ZL) || PRESSED(VPAD_BUTTON_DOWN)) {
      if (sCountIdx > 0) sCountIdx--;
      audio_sfx(0);
   }
   if (g_in.touchStart) {
      for (int i = 0; i < M_COUNT; i++) {
         if (ui_hit(g_in.tx, g_in.ty, 30.0f, 100.0f + (float)i * 62.0f, 230.0f, 52.0f)) set_mode(i);
      }
      if (ui_hit(g_in.tx, g_in.ty, 1030.0f, 100.0f, 220.0f, 52.0f) && sCountIdx < 4) { sCountIdx++; audio_sfx(0); }
      if (ui_hit(g_in.tx, g_in.ty, 1030.0f, 162.0f, 220.0f, 52.0f) && sCountIdx > 0) { sCountIdx--; audio_sfx(0); }
   }
   count = kCounts[sCountIdx];

   // touching the radar attracts everything
   sAttract = false;
   if (g_in.touch && ui_hit(g_in.tx, g_in.ty, RADAR_X - 290.0f, 90.0f, 580.0f, 560.0f)) {
      sAttract = true;
      sAttractPos[0] = (g_in.tx - RADAR_X) / RADAR_S;
      sAttractPos[1] = 3.0f;
      sAttractPos[2] = (g_in.ty - RADAR_Y) / RADAR_S;
   }

   // emitter position: touch, else the right stick, else a lissajous path
   if (sAttract) {
      sEmitter[0] = sAttractPos[0]; sEmitter[1] = 2.5f; sEmitter[2] = sAttractPos[2];
   } else if (fabsf(g_in.rx) + fabsf(g_in.ry) > 0.2f) {
      sEmitter[0] += g_in.rx * 12.0f * dt; sEmitter[2] -= g_in.ry * 12.0f * dt;
   } else {
      sEmitter[0] = 8.0f * fsin(t * 0.9f); sEmitter[1] = 3.0f + 2.0f * fsin(t * 1.7f); sEmitter[2] = 5.0f * fsin(t * 1.3f);
   }

   if (sMode == M_FIREWORKS) {
      sBurstTimer -= dt;
      if (sBurstTimer <= 0.0f) {
         sBurstTimer = 0.55f + rnd() * 0.7f;
         sBurstPos[0] = (rnd() - 0.5f) * 14.0f; sBurstPos[1] = 7.0f + rnd() * 6.0f; sBurstPos[2] = (rnd() - 0.5f) * 8.0f;
         sBurstHue = rnd();
         int want = count / 5, made = 0;
         for (int i = 0; i < count && made < want; i++) {
            if (sP[i].life <= 0.0f) { spawn(&sP[i], M_FIREWORKS); made++; }
         }
         audio_sfx(0);
      }
   }

   float emit = (sMode == M_STREAM) ? (float)count / 2.4f * dt : 0.0f;
   int emitN = (int)emit;
   if (rnd() < emit - (float)emitN) emitN++;

   for (int i = 0; i < count; i++) {
      Particle *p = &sP[i];
      if (sMode == M_GALAXY) {
         p->v[1] += p->v[2] * dt * (1.0f + g_audio.master * 0.6f);
         p->p[0] = p->v[0] * fcos(p->v[1]); p->p[2] = p->v[0] * fsin(p->v[1]);
         if (sAttract) {
            p->p[0] += (sAttractPos[0] - p->p[0]) * 0.35f * (0.4f + g_audio.master);
            p->p[2] += (sAttractPos[2] - p->p[2]) * 0.35f * (0.4f + g_audio.master);
         }
         continue;
      }
      if (p->life <= 0.0f) {
         if (sMode == M_FOUNTAIN) spawn(p, sMode);
         else if (sMode == M_STREAM && emitN > 0) { spawn(p, sMode); emitN--; }
         continue;
      }
      p->life -= dt;
      if (sMode == M_FOUNTAIN) {
         p->v[1] -= 9.8f * dt;
         if (p->p[1] < 0.0f && p->v[1] < 0.0f) { p->p[1] = 0.0f; p->v[1] *= -0.55f; p->v[0] *= 0.8f; p->v[2] *= 0.8f; }
      } else if (sMode == M_FIREWORKS) {
         float drag = 1.0f - 1.6f * dt;
         p->v[0] *= drag; p->v[1] = p->v[1] * drag - 3.5f * dt; p->v[2] *= drag;
      } else {
         p->v[1] += 0.4f * dt;
         p->v[0] += fsin(t * 2.0f + p->hue * 20.0f) * 0.8f * dt;
      }
      if (sAttract) {
         float dx = sAttractPos[0] - p->p[0], dy = sAttractPos[1] - p->p[1], dz = sAttractPos[2] - p->p[2];
         float d2 = dx * dx + dy * dy + dz * dz + 4.0f;
         float k = 90.0f / d2;
         p->v[0] += dx * k * dt; p->v[1] += dy * k * dt; p->v[2] += dz * k * dt;
      }
      p->p[0] += p->v[0] * dt; p->p[1] += p->v[1] * dt; p->p[2] += p->v[2] * dt;
   }

   // camera
   sCamA += dt * (sMode == M_GALAXY ? 0.18f : 0.10f);
   float eye[3], tgt[3];
   switch (sMode) {
   case M_GALAXY:    eye[0] = fsin(sCamA) * 18.0f; eye[1] = 10.0f; eye[2] = fcos(sCamA) * 18.0f; tgt[0] = 0; tgt[1] = 0; tgt[2] = 0; break;
   case M_FIREWORKS: eye[0] = fsin(sCamA * 0.5f) * 6.0f; eye[1] = 4.0f; eye[2] = 24.0f; tgt[0] = 0; tgt[1] = 9.0f; tgt[2] = 0; break;
   case M_STREAM:    eye[0] = fsin(sCamA) * 15.0f; eye[1] = 6.0f; eye[2] = fcos(sCamA) * 15.0f; tgt[0] = 0; tgt[1] = 3.0f; tgt[2] = 0; break;
   default:          eye[0] = fsin(sCamA) * 17.0f; eye[1] = 7.0f; eye[2] = fcos(sCamA) * 17.0f; tgt[0] = 0; tgt[1] = 4.5f; tgt[2] = 0; break;
   }
   float v[16], pr[16];
   m4_lookat(v, eye[0], eye[1], eye[2], tgt[0], tgt[1], tgt[2]);
   m4_persp(pr, 0.95f, VW / VH, 0.2f, 200.0f);
   m4_mul(sViewProj, pr, v);
   m4_ortho_ui(sUiM);

   sWorld = gfx_batch();
   sRadar = gfx_batch();

   // ground: pulsing rings and a light pool
   float right[3] = {v[0], v[4], v[8]}, up[3] = {v[1], v[5], v[9]};
   float flatR[3] = {1, 0, 0}, flatU[3] = {0, 0, 1}, origin[3] = {0, 0.03f, 0};
   b_billboard(sWorld, origin, flatR, flatU, 16.0f, C(0.35f, 0.25f, 0.9f, 0.20f + 0.25f * g_audio.beat));
   for (int r = 1; r <= 6; r++) {
      float rad = (float)r * 2.6f + 0.6f * g_audio.beat;
      for (int s = 0; s < 40; s++) {
         float a0 = (float)s / 40.0f * 6.28318f, a1 = (float)(s + 1) / 40.0f * 6.28318f;
         float p0[3] = {fcos(a0) * rad, 0.02f, fsin(a0) * rad}, p1[3] = {fcos(a1) * rad, 0.02f, fsin(a1) * rad};
         float p2[3] = {fcos(a1) * (rad + 0.07f), 0.02f, fsin(a1) * (rad + 0.07f)}, p3[3] = {fcos(a0) * (rad + 0.07f), 0.02f, fsin(a0) * (rad + 0.07f)};
         b_quad3(sWorld, p0, p1, p2, p3, C(0.5f, 0.4f, 1.0f, 0.55f));
      }
   }

   float beatSize = 1.0f + 0.25f * g_audio.beat;
   for (int i = 0; i < count; i++) {
      Particle *p = &sP[i];
      if (p->life <= 0.0f) continue;
      float k = p->life / p->maxLife;
      float a = k > 0.25f ? 1.0f : k * 4.0f;
      if (a > 1.0f) a = 1.0f;
      Col c = hsv(p->hue, 0.6f, 1.0f, a * 0.8f);
      b_billboard(sWorld, p->p, right, up, 0.20f * p->size * beatSize, c);
      // radar dot
      float px = RADAR_X + p->p[0] * RADAR_S, py = RADAR_Y + p->p[2] * RADAR_S;
      if (px > 60.0f && px < VW - 60.0f && py > 90.0f && py < VH - 50.0f) {
         b_glow(sRadar, px, py, 4.0f + 2.5f * p->size + 0.6f * (p->p[1] > 0 ? (p->p[1] > 10 ? 10 : p->p[1]) : 0.0f), CA(c, a * 0.55f));
      }
   }
   if (sAttract) {
      b_billboard(sWorld, sAttractPos, right, up, 1.6f, C(1.0f, 0.9f, 0.6f, 0.9f));
   }
}

static void part_draw(Target tg)
{
   if (tg == TARGET_TV) {
      Batch *bg = gfx_batch();
      ui_sky(bg, C(0.01f, 0.01f, 0.06f, 1), C(0.05f, 0.03f, 0.16f, 1), C(0.10f, 0.05f, 0.22f, 1));
      gfx_draw_batch(bg, sUiM, BLEND_OPAQUE, DEPTH_OFF, NULL);
      gfx_draw_batch(sWorld, sViewProj, BLEND_ADD, DEPTH_READ, NULL);

      Batch *ui = gfx_batch();
      char sub[64];
      snprintf(sub, sizeof(sub), "%d PARTICLES  %s", kCounts[sCountIdx], kModeName[sMode]);
      ui_header(ui, "PARTICLE STORM", sub);
      ui_footer(ui, "A: NEXT MODE   ZL/ZR: COUNT   TOUCH THE GAMEPAD RADAR TO PULL   B: MENU");
      gfx_draw_batch(ui, sUiM, BLEND_ALPHA, DEPTH_OFF, NULL);
   } else {
      Batch *bg = gfx_batch();
      b_rect(bg, 0, 0, VW, VH, C(0.02f, 0.02f, 0.08f, 1));
      b_rect(bg, RADAR_X - 290.0f, 90.0f, 580.0f, 560.0f, C(0.04f, 0.05f, 0.14f, 1));
      for (int r = 1; r <= 6; r++) b_ring(bg, RADAR_X, RADAR_Y, (float)r * 2.6f * RADAR_S, 1.5f, C(0.4f, 0.4f, 0.9f, 0.5f), 56);
      b_line(bg, RADAR_X - 280.0f, RADAR_Y, RADAR_X + 280.0f, RADAR_Y, 1.5f, C(0.4f, 0.4f, 0.9f, 0.4f));
      b_line(bg, RADAR_X, 100.0f, RADAR_X, 640.0f, 1.5f, C(0.4f, 0.4f, 0.9f, 0.4f));
      if (sAttract) b_ring(bg, RADAR_X + sAttractPos[0] * RADAR_S, RADAR_Y + sAttractPos[2] * RADAR_S, 26.0f, 3.0f, C(1, 1, 1, 0.9f), 24);
      gfx_draw_batch(bg, sUiM, BLEND_ALPHA, DEPTH_OFF, NULL);
      gfx_draw_batch(sRadar, sUiM, BLEND_ADD, DEPTH_OFF, NULL);

      Batch *ui = gfx_batch();
      ui_header(ui, "PARTICLE RADAR", "TOUCH TO ATTRACT");
      if (g_hud) {
         for (int i = 0; i < M_COUNT; i++) {
            ui_button(ui, 30.0f, 100.0f + (float)i * 62.0f, 230.0f, 52.0f, kModeName[i], i == sMode, hsv(0.1f + 0.2f * (float)i, 0.6f, 0.9f, 1));
         }
         ui_button(ui, 1030.0f, 100.0f, 220.0f, 52.0f, "MORE", sCountIdx < 4, C(0.3f, 0.7f, 0.4f, 1));
         ui_button(ui, 1030.0f, 162.0f, 220.0f, 52.0f, "FEWER", sCountIdx > 0, C(0.8f, 0.4f, 0.3f, 1));
         b_textf(ui, 1030.0f, 232.0f, 2.4f, C(1, 1, 1, 1), "%d", kCounts[sCountIdx]);
         ui_footer(ui, "TAP A MODE   TOUCH THE RADAR   RIGHT STICK MOVES THE EMITTER");
      }
      gfx_draw_batch(ui, sUiM, BLEND_ALPHA, DEPTH_OFF, NULL);
   }
}

const Scene scene_particles = {
   "PARTICLE STORM", "THOUSANDS OF GLOWING SPRITES, ADDITIVE BLENDING", part_enter, part_leave, part_update, NULL, part_draw, 22.0f,
};
