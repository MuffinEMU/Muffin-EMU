// MuffinEMU Showcase - main loop: title card, scene menu, auto-demo, TV + GamePad rendering.
// MPL-2.0. Original code; see README.md.
#include "showcase.h"

#include <coreinit/screen.h>
#include <coreinit/thread.h>
#include <coreinit/time.h>
#include <string.h>
#include <whb/proc.h>

const Scene *const g_scenes[NUM_SCENES] = {
   &sc_landscape, &sc_particles, &sc_shader, &sc_mesh, &sc_inputlab, &sc_audio, &sc_stress
};

Stats g_stats;
float g_time;
int g_demo;
int g_frame;
int g_audio_track_override = -1;

enum { ST_TITLE, ST_MENU, ST_SCENE };

static int s_state = ST_TITLE, s_cur, s_sel;
static float s_idle, s_demo_t, s_fadein, s_stick_cd;
static int s_quality_manual;

// A small pixel-art muffin: tan dome with chocolate chips over a striped paper cup.
void draw_muffin(Surf *s, int cx, int cy, int sz)
{
   for (int dy = -sz; dy <= sz / 2; dy++)
   {
      float t = (float)dy / (float)sz;
      float hw = (float)sz * 1.3f * m_sqrt(m_clamp(1.0f - t * t * (t < 0 ? 1.0f : 3.2f), 0.0f, 1.0f));
      int w = (int)hw;
      u32 c = col_mix(RGB(238, 176, 92), RGB(176, 108, 48), (dy + sz) * 256 / (sz * 3 / 2 + 1));
      s_rect(s, cx - w, cy + dy, 2 * w, 1, c);
   }
   for (int i = 0; i < 9; i++)
   {
      u32 h = hash2(i, 31);
      int x = cx + (int)(h % (u32)(sz * 2)) - sz;
      int y = cy - (int)((h >> 8) % (u32)(sz)) ;
      s_disc(s, x, y, sz / 9 + 1, RGB(62, 36, 24));
   }
   s_disc(s, cx - sz / 2, cy - sz * 3 / 4, sz / 6, RGB(255, 225, 160));
   int top = cy + sz / 2, hgt = sz;
   for (int dy = 0; dy < hgt; dy++)
   {
      int hw = sz * 11 / 10 - dy * sz / (hgt * 4);
      for (int x = -hw; x < hw; x += 1)
      {
         int stripe = ((x + 1000) / (sz / 4 + 1)) & 1;
         s_rect(s, cx + x, top + dy, 1, 1, stripe ? RGB(255, 120, 150) : RGB(255, 200, 215));
      }
   }
}

static void bg_plasma(float dim256)
{
   const int B = 4;
   for (int j = 0; j < g_sh; j += B)
      for (int i = 0; i < g_sw; i += B)
      {
         float x = (float)i * 0.045f, y = (float)j * 0.06f, t = g_time;
         float v = m_sin(x + t * 0.8f) + m_sin(y * 1.3f - t * 1.1f) + m_sin((x + y) * 0.7f + t * 0.6f);
         int k = (int)((v * 0.17f + 0.5f) * 255.0f);
         u32 c = RGB(40 + (k >> 2), 14 + (k >> 3), 80 + (k >> 1));
         c = col_scale(c, (int)dim256);
         for (int dy = 0; dy < B && j + dy < g_sh; dy++)
            for (int dx = 0; dx < B && i + dx < g_sw; dx++) S_SCN.p[(j + dy) * g_sw + i + dx] = c;
      }
}

static void goto_scene(int i)
{
   s_cur = (i + NUM_SCENES) % NUM_SCENES;
   s_state = ST_SCENE;
   s_fadein = 0.0f;
   s_demo_t = 0.0f;
   s_fill(&S_SCN, RGB(0, 0, 0));
   if (g_scenes[s_cur]->enter) g_scenes[s_cur]->enter();
}

static void hud_common(const Scene *sc)
{
   s_rect_a(&S_TV, 0, 0, TV_W, 52, RGB(0, 0, 0), 130);
   s_text_sh(&S_TV, 20, 14, 3, COL_ACCENT, sc->name);
   char buf[48];
   int n = 0;
   n = (int)(g_stats.fps + 0.5f);
   buf[0] = 0;
   s_textf(&S_TV, TV_W - 150, 18, 2, n >= 25 ? COL_GREEN : (n >= 12 ? COL_ACCENT : COL_RED), "%d FPS", n);
   if (audio_muted()) s_text_sh(&S_TV, TV_W - 250, 18, 2, COL_RED, "MUTE");
   if (g_demo && ((g_frame >> 4) & 1)) s_text_sh(&S_TV, TV_W / 2 - text_w("AUTO DEMO  PRESS ANY BUTTON", 2) / 2, 18, 2, COL_CYAN, "AUTO DEMO  PRESS ANY BUTTON");
   s_text(&S_TV, TV_W - text_w("-:MENU  L/R:SCENE  +:MUTE  Y:QUALITY", 2) - 16, TV_H - 22, 2, COL_DIM, "-:MENU  L/R:SCENE  +:MUTE  Y:QUALITY");
   (void)buf;
}

static void draw_title_tv(void)
{
   bg_plasma(230.0f);
   draw_muffin(&S_SCN, g_sw / 2, g_sh * 30 / 100 + (int)(m_sin(g_time * 2.0f) * 2.0f), g_sh / 8);
   gfx_present_scene();
   const char *t = "MUFFINEMU";
   int sc = 11, x = (TV_W - text_w(t, sc)) / 2;
   for (int i = 0; t[i]; i++)
   {
      char ch[2] = { t[i], 0 };
      int yo = (int)(m_sin(g_time * 3.0f + (float)i * 0.7f) * 10.0f);
      s_text_sh(&S_TV, x + i * 6 * sc, 330 + yo, sc, hsv(g_time * 0.1f + (float)i * 0.04f, 0.45f, 1.0f), ch);
   }
   s_text_sh(&S_TV, (TV_W - text_w("SHOWCASE", 6)) / 2, 430, 6, COL_WHITE, "SHOWCASE");
   if ((g_frame >> 5) & 1) { /* blink off */ }
   else s_text_sh(&S_TV, (TV_W - text_w("PRESS A OR TOUCH THE GAMEPAD", 3)) / 2, 530, 3, COL_ACCENT, "PRESS A OR TOUCH THE GAMEPAD");
   int tp = 100, ap = audio_progress();
   if (!terrain_ready()) tp = 50;
   if (ap < 100 || tp < 100)
      s_textf(&S_TV, (TV_W - 380) / 2, 600, 2, COL_DIM, "PREPARING  TERRAIN %s  MUSIC %d%%", terrain_ready() ? "OK" : "...", ap);
   s_text(&S_TV, (TV_W - text_w("A WII U HOMEBREW DEMO FOR MUFFINEMU", 2)) / 2, 670, 2, COL_DIM, "A WII U HOMEBREW DEMO FOR MUFFINEMU");
}

static void draw_menu_tv(void)
{
   bg_plasma(150.0f);
   gfx_present_scene();
   s_text_sh(&S_TV, 60, 50, 5, COL_WHITE, "CHOOSE A SCENE");
   for (int i = 0; i < NUM_SCENES; i++)
   {
      int y = 112 + i * 76, on = (i == s_sel);
      int x = on ? 76 : 60;
      s_rect_a(&S_TV, x, y, 800, 68, on ? RGB(70, 40, 20) : COL_PANEL, 215);
      s_box_outline(&S_TV, x, y, 800, 68, on ? COL_ACCENT : RGB(60, 55, 100));
      if (on) s_box_outline(&S_TV, x + 1, y + 1, 798, 66, COL_ACCENT);
      s_textf(&S_TV, x + 18, y + 8, 4, on ? COL_ACCENT : COL_WHITE, "%d  %s", i + 1, g_scenes[i]->name);
      s_text(&S_TV, x + 18, y + 44, 2, COL_DIM, g_scenes[i]->blurb);
   }
   s_panel(&S_TV, 920, 112, 300, 200, COL_CYAN);
   s_text_sh(&S_TV, 936, 126, 2, COL_CYAN, "NOW PLAYING");
   s_text_sh(&S_TV, 936, 158, 2, COL_WHITE, audio_track_name(audio_track()));
   s_textf(&S_TV, 936, 190, 2, COL_DIM, "%d BPM", audio_track_bpm(audio_track()));
   s_text(&S_TV, 936, 222, 2, audio_muted() ? COL_RED : COL_GREEN, audio_muted() ? "MUTED" : "SOUND ON");
   s_text(&S_TV, 936, 262, 2, COL_DIM, "+ TO MUTE");
   s_text(&S_TV, 60, 676, 2, COL_DIM, "UP/DOWN: PICK   A: START   B: TITLE   OR TOUCH THE GAMEPAD");
}

static void draw_title_drc(void)
{
   s_vgrad(&S_DRC, 0, 0, DRC_W, DRC_H, RGB(34, 18, 70), RGB(10, 8, 28));
   draw_muffin(&S_DRC, DRC_W / 2, 160, 70);
   s_text_sh(&S_DRC, (DRC_W - text_w("MUFFINEMU SHOWCASE", 4)) / 2, 270, 4, COL_WHITE, "MUFFINEMU SHOWCASE");
   if (!((g_frame >> 5) & 1))
      s_text_sh(&S_DRC, (DRC_W - text_w("TOUCH TO START", 3)) / 2, 340, 3, COL_ACCENT, "TOUCH TO START");
   s_text(&S_DRC, (DRC_W - text_w("TV: SCENE   GAMEPAD: CONTROL PANEL", 2)) / 2, 420, 2, COL_DIM, "TV: SCENE   GAMEPAD: CONTROL PANEL");
}

static void draw_menu_drc(void)
{
   s_vgrad(&S_DRC, 0, 0, DRC_W, DRC_H, RGB(24, 14, 52), RGB(8, 6, 22));
   s_text_sh(&S_DRC, 16, 12, 3, COL_ACCENT, "TOUCH A SCENE");
   for (int i = 0; i < NUM_SCENES; i++)
   {
      int cx = 16 + (i & 1) * 424, cy = 50 + (i >> 1) * 76, on = (i == s_sel);
      s_rect(&S_DRC, cx, cy, 406, 68, on ? RGB(110, 60, 20) : COL_PANEL);
      s_box_outline(&S_DRC, cx, cy, 406, 68, on ? COL_ACCENT : COL_DIM);
      s_textf(&S_DRC, cx + 14, cy + 10, 3, on ? COL_ACCENT : COL_WHITE, "%d", i + 1);
      s_text_sh(&S_DRC, cx + 50, cy + 12, 2, COL_WHITE, g_scenes[i]->name);
      s_text(&S_DRC, cx + 14, cy + 44, 1, COL_DIM, g_scenes[i]->blurb);
   }
   s_rect(&S_DRC, 16, 354, 406, 52, audio_muted() ? COL_RED : COL_PANEL);
   s_box_outline(&S_DRC, 16, 354, 406, 52, COL_DIM);
   s_text_sh(&S_DRC, 16 + (406 - text_w(audio_muted() ? "UNMUTE MUSIC" : "MUTE MUSIC", 2)) / 2, 372, 2, COL_WHITE, audio_muted() ? "UNMUTE MUSIC" : "MUTE MUSIC");
   s_rect(&S_DRC, 440, 354, 406, 52, COL_PANEL);
   s_box_outline(&S_DRC, 440, 354, 406, 52, COL_CYAN);
   s_text_sh(&S_DRC, 440 + (406 - text_w("START AUTO DEMO", 2)) / 2, 372, 2, COL_CYAN, "START AUTO DEMO");
   s_textf(&S_DRC, 16, 428, 2, COL_DIM, "NOW PLAYING  %s", audio_track_name(audio_track()));
   s_text(&S_DRC, 16, 452, 2, COL_DIM, "IDLE FOR A WHILE AND THE DEMO STARTS BY ITSELF");
}

// Starts at 640x360 and steps down (320x180, then 160x90) when the host cannot keep up. It never
// steps back up on its own, so a borderline machine does not flap between two sizes.
static void update_quality(void)
{
   static float acc;
   static int n;
   acc += g_stats.frame_ms; n++;
   // Judge quickly (12 frames) so a slow host does not sit through a long crawl at 640x360.
   if (n >= 12)
   {
      if (!s_quality_manual && g_scale < 8 && acc / (float)n > (g_scale == 2 ? 48.0f : 85.0f))
         gfx_set_scale(g_scale == 2 ? 4 : 8);
      acc = 0; n = 0;
   }
}

int main(int argc, char **argv)
{
   (void)argc; (void)argv;
   WHBProcInit();
   util_init();
   par_init();
   gfx_init();
   input_init();
   audio_init();
   audio_set_track(0);

   OSTime last = OSGetSystemTime();
   int seen_running = 0, drc_tick = 0;
   float fps_acc = 0.0f;
   int fps_n = 0;

   for (;;)
   {
      int running = WHBProcIsRunning();
      if (running) seen_running = 1;
      else if (seen_running) break;       // HOME menu / quit; never leave on a broken ProcUI

      OSTime now = OSGetSystemTime();
      float frame_ms = (float)OSTicksToMicroseconds(now - last) / 1000.0f;
      last = now;
      float dt = frame_ms * 0.001f;
      if (dt > 0.1f) dt = 0.1f;
      if (dt < 0.0005f) dt = 0.0005f;
      g_time += dt;
      g_frame++;
      g_stats.frame_ms = g_stats.frame_ms * 0.9f + frame_ms * 0.1f;
      g_stats.hist[g_stats.hist_pos] = frame_ms;
      g_stats.hist_pos = (g_stats.hist_pos + 1) % 120;
      fps_acc += dt; fps_n++;
      if (fps_acc >= 0.5f) { g_stats.fps = (float)fps_n / fps_acc; fps_acc = 0; fps_n = 0; }
      update_quality();

      // ---------------------------------------------------------------- input
      OSTime t_up = OSGetSystemTime();
      Input in;
      input_poll(&in);
      int touched_any = in.any;
      if (touched_any) s_idle = 0.0f; else s_idle += dt;
      if (g_demo && touched_any)
      {
         g_demo = 0;
         in.trig = 0; in.touch_trig = 0; in.hold = 0;
         s_idle = 0.0f;
      }
      if (in.trig & B_PLUS) audio_set_mute(!audio_muted());
      if (in.trig & B_Y) { s_quality_manual = 1; gfx_set_scale(g_scale == 2 ? 4 : (g_scale == 4 ? 8 : 2)); }

      if (s_state == ST_TITLE)
      {
         terrain_gen_step(5);
         if ((in.trig & B_A) || in.touch_trig) { s_state = ST_MENU; s_sel = 0; drc_tick = 0; in.trig = 0; }
         else if (s_idle > 10.0f && terrain_ready() && audio_ready(0)) { g_demo = 1; goto_scene(0); drc_tick = 0; }
      }
      else if (s_state == ST_MENU)
      {
         terrain_gen_step(5);
         s_stick_cd -= dt;
         if ((in.trig & B_DOWN) || (in.ly < -0.6f && s_stick_cd <= 0)) { s_sel = (s_sel + 1) % NUM_SCENES; s_stick_cd = 0.22f; }
         if ((in.trig & B_UP) || (in.ly > 0.6f && s_stick_cd <= 0)) { s_sel = (s_sel + NUM_SCENES - 1) % NUM_SCENES; s_stick_cd = 0.22f; }
         if (in.trig & B_B) { s_state = ST_TITLE; drc_tick = 0; }
         else if (in.trig & B_A) { goto_scene(s_sel); drc_tick = 0; in.trig = 0; }
         else if (in.touch_trig)
         {
            for (int i = 0; i < NUM_SCENES; i++)
            {
               int cx = 16 + (i & 1) * 424, cy = 50 + (i >> 1) * 76;
               if (in.tx >= cx && in.tx < cx + 406 && in.ty >= cy && in.ty < cy + 68) { s_sel = i; goto_scene(i); drc_tick = 0; in.touch_trig = 0; break; }
            }
            if (s_state == ST_MENU && in.ty >= 354 && in.ty < 406)
            {
               if (in.tx < 430) audio_set_mute(!audio_muted());
               else { g_demo = 1; goto_scene(0); drc_tick = 0; }
            }
         }
         else if (s_idle > 14.0f && terrain_ready() && audio_ready(0)) { g_demo = 1; goto_scene(0); drc_tick = 0; }
      }
      else
      {
         const Scene *sc = g_scenes[s_cur];
         if (!g_demo)
         {
            if (in.trig & (B_MINUS | B_B)) { s_state = ST_MENU; s_sel = s_cur; g_audio_track_override = -1; drc_tick = 0; }
            else if (in.trig & B_R) { goto_scene(s_cur + 1); drc_tick = 0; in.trig = 0; }
            else if (in.trig & B_L) { goto_scene(s_cur - 1); drc_tick = 0; in.trig = 0; }
         }
         else
         {
            s_demo_t += dt;
            if (s_demo_t > 14.0f) { goto_scene(s_cur + 1); drc_tick = 0; }
         }
         if (s_state == ST_SCENE) sc->update(&in, dt, g_demo);
      }
      g_stats.update_ms = (float)OSTicksToMicroseconds(OSGetSystemTime() - t_up) / 1000.0f;

      // ---------------------------------------------------------------- audio routing
      {
         int tr = 0;
         if (s_state == ST_SCENE) tr = g_scenes[s_cur]->track;
         if (g_audio_track_override >= 0 && s_state == ST_SCENE) tr = g_audio_track_override;
         audio_set_track(tr);
         audio_update(dt);
      }

      // ---------------------------------------------------------------- render TV
      OSTime t_r = OSGetSystemTime();
      if (s_state == ST_TITLE) draw_title_tv();
      else if (s_state == ST_MENU) draw_menu_tv();
      else
      {
         const Scene *sc = g_scenes[s_cur];
         sc->render();
         if (s_fadein < 1.0f)
         {
            s_fadein += dt * 2.5f;
            if (s_fadein > 1.0f) s_fadein = 1.0f;
            s_fade(&S_SCN, (int)(s_fadein * 256.0f));
         }
         g_stats.render_ms = (float)OSTicksToMicroseconds(OSGetSystemTime() - t_r) / 1000.0f;
         OSTime t_p = OSGetSystemTime();
         gfx_present_scene();
         g_stats.present_ms = (float)OSTicksToMicroseconds(OSGetSystemTime() - t_p) / 1000.0f;
         if (sc->hud) sc->hud();
         hud_common(sc);
      }
      gfx_flip_tv();

      // ---------------------------------------------------------------- GamePad (every 3rd frame)
      if (drc_tick++ % 3 == 0)
      {
         if (s_state == ST_TITLE) draw_title_drc();
         else if (s_state == ST_MENU) draw_menu_drc();
         else
         {
            g_scenes[s_cur]->drc(&in);
            if (g_demo && ((g_frame >> 4) & 1)) s_text_sh(&S_DRC, DRC_W - 250, 10, 2, COL_CYAN, "AUTO DEMO  TOUCH TO STOP");
         }
         gfx_flip_drc();
      }

      // Keep to roughly 60 Hz; never spin the CPU when a frame is cheap.
      OSTime spent = OSGetSystemTime() - now;
      float spent_us = (float)OSTicksToMicroseconds(spent);
      if (spent_us < 15000.0f) OSSleepTicks(OSMicrosecondsToTicks((uint64_t)(15500.0f - spent_us)));
   }

   input_rumble_stop();
   stress_stop_workers();
   par_shutdown();
   audio_shutdown();
   WHBProcShutdown();
   return 0;
}
