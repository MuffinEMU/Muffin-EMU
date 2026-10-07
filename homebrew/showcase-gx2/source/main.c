// MuffinEMU showcase: scene manager, input and the frame loop.
//
// Frame protocol (all scenes follow it):
//   gfx_begin_frame -> scene.update (logic and shared geometry) -> scene.prepass
//   (optional offscreen passes, in the TV context) -> scene.draw(TV) -> scene.draw(DRC)

#include "app.h"
#include "audio.h"
#include "gfx.h"
#include "muffin.h"
#include "ui.h"

#include <coreinit/debug.h>
#include <coreinit/time.h>
#include <vpad/input.h>
#include <whb/gfx.h>
#include <whb/proc.h>

#include <math.h>
#include <stdio.h>
#include <string.h>

Input g_in;
double g_time;
float g_dt = 1.0f / 60.0f;
float g_fps = 60.0f;
bool g_hud = true;
bool g_tour;

static const Scene *sScenes[SCENE_COUNT] = {
   &scene_hub, &scene_world, &scene_particles, &scene_fx, &scene_mirror,
   &scene_fractal, &scene_input, &scene_sound, &scene_system,
};

static int sCur = -1;
static int sNext = 0;
static double sSceneStart;

const Scene *app_scene(int index) { return sScenes[(index % SCENE_COUNT + SCENE_COUNT) % SCENE_COUNT]; }
void app_goto(int index) { sNext = (index % SCENE_COUNT + SCENE_COUNT) % SCENE_COUNT; }
int app_current(void) { return sCur; }
float app_scene_time(void) { return (float)(g_time - sSceneStart); }

static void read_input(void)
{
   VPADStatus st;
   VPADReadError err = VPAD_READ_SUCCESS;
   int n = VPADRead(VPAD_CHAN_0, &st, 1, &err);

   g_in.trig = 0;
   g_in.rel = 0;
   g_in.touchStart = false;
   g_in.ok = (n > 0 && err == VPAD_READ_SUCCESS);
   if (!g_in.ok) return;

   g_in.hold = st.hold;
   g_in.trig = st.trigger;
   g_in.rel = st.release;
   g_in.lx = st.leftStick.x;
   g_in.ly = st.leftStick.y;
   g_in.rx = st.rightStick.x;
   g_in.ry = st.rightStick.y;

   VPADTouchData cal;
   memset(&cal, 0, sizeof(cal));
   VPADGetTPCalibratedPointEx(VPAD_CHAN_0, VPAD_TP_1280X720, &cal, &st.tpNormal);
   bool was = g_in.touch;
   g_in.touch = st.tpNormal.touched != 0 && cal.touched != 0;
   g_in.touchStart = g_in.touch && !was;
   if (g_in.touch) {
      g_in.tx = (float)cal.x;
      g_in.ty = (float)cal.y;
   }

   g_in.ax = st.accelorometer.acc.x;
   g_in.ay = st.accelorometer.acc.y;
   g_in.az = st.accelorometer.acc.z;
   g_in.gx = st.gyro.x;
   g_in.gy = st.gyro.y;
   g_in.gz = st.gyro.z;
   g_in.angx = st.angle.x;
   g_in.angy = st.angle.y;
   g_in.angz = st.angle.z;
}

static void switch_scene(void)
{
   if (sNext < 0) return;
   if (sCur >= 0 && sScenes[sCur]->leave) sScenes[sCur]->leave();
   sCur = sNext;
   sNext = -1;
   sSceneStart = g_time;
   if (sScenes[sCur]->enter) sScenes[sCur]->enter();
   OSReport("showcase: scene %d (%s)\n", sCur, sScenes[sCur]->name);
}

static void global_controls(void)
{
   if (PRESSED(VPAD_BUTTON_PLUS)) g_hud = !g_hud;
   if (PRESSED(VPAD_BUTTON_MINUS)) audio_set_muted(!g_audio.muted);

   if (sCur > 0) {
      if (PRESSED(VPAD_BUTTON_B)) {
         g_tour = false;
         audio_sfx(2);
         app_goto(0);
      } else if (PRESSED(VPAD_BUTTON_R)) {
         audio_sfx(0);
         app_goto(sCur % (SCENE_COUNT - 1) + 1);
      } else if (PRESSED(VPAD_BUTTON_L)) {
         audio_sfx(0);
         app_goto((sCur + SCENE_COUNT - 3) % (SCENE_COUNT - 1) + 1);
      }
      if (g_tour && app_scene_time() > sScenes[sCur]->tourSeconds) {
         app_goto(sCur % (SCENE_COUNT - 1) + 1);
      }
   }
}

// fade-in after a scene change, and the tour badge
static void overlay(Target t)
{
   Batch *b = gfx_batch();
   float fade = 1.0f - app_scene_time() / 0.45f;
   if (fade > 0.0f) b_rect(b, 0, 0, VW, VH, C(0, 0, 0, fade));
   if (g_tour && g_hud) {
      char buf[48];
      snprintf(buf, sizeof(buf), "AUTO TOUR   B: STOP");
      float w = text_width(buf, 2.0f);
      b_rect(b, VW - w - 44.0f, VH - 96.0f, w + 32.0f, 36.0f, C(0.0f, 0.0f, 0.0f, 0.6f));
      b_text_shadow(b, VW - w - 28.0f, VH - 87.0f, 2.0f, C(1.0f, 0.85f, 0.4f, 1), buf);
   }
   float mvp[16];
   m4_ortho_ui(mvp);
   gfx_draw_batch(b, mvp, BLEND_ALPHA, DEPTH_OFF, NULL);
   (void)t;
}

static void error_screen(const char *why)
{
   OSReport("showcase: FATAL %s\n", why);
   while (WHBProcIsRunning()) {
      WHBGfxBeginRender();
      WHBGfxBeginRenderTV();
      WHBGfxClearColor(0.5f, 0.05f, 0.08f, 1.0f);
      WHBGfxFinishRenderTV();
      WHBGfxBeginRenderDRC();
      WHBGfxClearColor(0.5f, 0.05f, 0.08f, 1.0f);
      WHBGfxFinishRenderDRC();
      WHBGfxFinishRender();
   }
}

int main(int argc, char **argv)
{
   (void)argc;
   (void)argv;

   WHBProcInit();
   WHBGfxInit();
   OSReport("showcase: starting\n");

   if (!gfx_init()) {
      error_screen("gfx_init failed (shader load or buffer allocation)");
      WHBGfxShutdown();
      WHBProcShutdown();
      return 1;
   }
   muffin_build();
   if (!audio_init()) OSReport("showcase: audio unavailable, continuing silently\n");

   OSTime t0 = OSGetSystemTime();
   OSTime last = t0;

   while (WHBProcIsRunning()) {
      OSTime now = OSGetSystemTime();
      float dt = (float)((double)(now - last) / (double)OSTimerClockSpeed);
      last = now;
      if (dt > 0.1f) dt = 0.1f;
      if (dt < 0.0005f) dt = 0.0005f;
      g_dt = dt;
      g_time = (double)(now - t0) / (double)OSTimerClockSpeed;
      g_fps += (1.0f / dt - g_fps) * 0.05f;

      read_input();
      global_controls();
      switch_scene();
      audio_update(dt);

      const Scene *sc = sScenes[sCur];
      gfx_begin_frame();
      sc->update(dt);

      WHBGfxBeginRender();
      if (sc->prepass) {
         WHBGfxBeginRenderTV();
         sc->prepass();
      }

      WHBGfxBeginRenderTV();
      WHBGfxClearColor(0.0f, 0.0f, 0.0f, 1.0f);
      sc->draw(TARGET_TV);
      overlay(TARGET_TV);
      WHBGfxFinishRenderTV();

      WHBGfxBeginRenderDRC();
      WHBGfxClearColor(0.0f, 0.0f, 0.0f, 1.0f);
      sc->draw(TARGET_DRC);
      overlay(TARGET_DRC);
      WHBGfxFinishRenderDRC();

      WHBGfxFinishRender();
   }

   OSReport("showcase: shutting down\n");
   if (sCur >= 0 && sScenes[sCur]->leave) sScenes[sCur]->leave();
   fractal_quit();
   audio_shutdown();
   gfx_shutdown();
   WHBGfxShutdown();
   WHBProcShutdown();
   return 0;
}
