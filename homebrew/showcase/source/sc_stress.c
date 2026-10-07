// Scene 6: stress and info. A Mandelbrot zoom is split into bands and rendered by three OSThreads,
// one pinned to each PPC core (OS_THREAD_ATTRIB_AFFINITY_CPU0/1/2), synchronised with OSSemaphores.
// X toggles one core against three so the speed-up is measured live. Also shows frame timing,
// MEM1/MEM2 and heap numbers, and scrolls the credits.
#include "showcase.h"

#include <coreinit/memory.h>
#include <coreinit/semaphore.h>
#include <coreinit/thread.h>
#include <coreinit/time.h>
#include <malloc.h>

#define WSTACK 0x8000

static OSThread s_wt[3] __attribute__((aligned(16)));
static u8 s_wstack[3][WSTACK] __attribute__((aligned(16)));
static OSSemaphore s_go[3], s_done[3];
static volatile int s_quit, s_started, s_threads_ok;
static volatile OSTime s_wtime[3];

static volatile int j_cols, j_rows, j_B, j_r0[3], j_r1[3];
static volatile float j_cre, j_cim, j_scale;

static u32 s_pal[256];
static u32 kRowColor(int c) { static const u32 k[3] = { RGB(255,110,80), RGB(110,230,140), RGB(90,190,255) }; return k[c % 3]; }
static int s_cores = 3;
static float s_ms_one, s_ms_three, s_job_ms;
static float s_core_ms[3];
static float s_credit_y;

static void render_band(int id)
{
   const int B = j_B, cols = j_cols;
   const float scale = j_scale, cre = j_cre, cim = j_cim;
   const float inv = scale / (float)cols;
   for (int j = j_r0[id]; j < j_r1[id]; j++)
   {
      float ci = cim + ((float)j - (float)j_rows * 0.5f) * inv;
      for (int i = 0; i < cols; i++)
      {
         float cr = cre + ((float)i - (float)cols * 0.5f) * inv;
         float zr = 0.0f, zi = 0.0f;
         int it = 0;
         while (it < 56 && zr * zr + zi * zi < 16.0f)
         {
            float t = zr * zr - zi * zi + cr;
            zi = 2.0f * zr * zi + ci;
            zr = t;
            it++;
         }
         u32 c = it >= 56 ? RGB(6, 4, 14) : s_pal[(it * 9) & 255];
         int x = i * B, y = j * B;
         for (int dy = 0; dy < B && y + dy < g_sh; dy++)
         {
            u32 *p = S_SCN.p + (y + dy) * g_sw + x;
            for (int dx = 0; dx < B && x + dx < g_sw; dx++) p[dx] = c;
         }
      }
   }
}

static int worker_main(int id, const char **argv)
{
   (void)argv;
   for (;;)
   {
      OSWaitSemaphore(&s_go[id]);
      if (s_quit) break;
      OSTime t0 = OSGetSystemTime();
      render_band(id);
      s_wtime[id] = OSGetSystemTime() - t0;
      OSSignalSemaphore(&s_done[id]);
   }
   return 0;
}

void stress_start_workers(void)
{
   if (s_started) return;
   s_started = 1;
   for (int i = 0; i < 256; i++)
   {
      float f = (float)i * 0.0245f;
      s_pal[i] = RGB(128 + (int)(120 * m_sin(f)), 100 + (int)(100 * m_sin(f * 1.3f + 1.0f)), 150 + (int)(100 * m_sin(f * 0.8f + 2.2f)));
   }
   s_threads_ok = 1;
   for (int i = 0; i < 3; i++)
   {
      OSInitSemaphore(&s_go[i], 0);
      OSInitSemaphore(&s_done[i], 0);
      if (!OSCreateThread(&s_wt[i], worker_main, i, NULL, s_wstack[i] + WSTACK, WSTACK, 16,
                          (OSThreadAttributes)(OS_THREAD_ATTRIB_AFFINITY_CPU0 << i)))
      {
         s_threads_ok = 0;
         break;
      }
      OSSetThreadName(&s_wt[i], "showcase worker");
      OSResumeThread(&s_wt[i]);
   }
}

void stress_stop_workers(void)
{
   if (!s_started) return;
   if (s_threads_ok)
   {
      s_quit = 1;
      for (int i = 0; i < 3; i++) OSSignalSemaphore(&s_go[i]);
      for (int i = 0; i < 3; i++) { int rc; OSJoinThread(&s_wt[i], &rc); }
   }
   s_started = 0;
}

static void enter(void)
{
   stress_start_workers();
   g_audio_track_override = -1;
   s_credit_y = 0.0f;
}

static void update(const Input *in, float dt, int demo)
{
   if (!demo && (in->trig & B_X)) s_cores = (s_cores == 3) ? 1 : 3;
   if (demo) s_cores = (((int)(g_time / 4.0f)) & 1) ? 1 : 3;
   if (in->touch_trig && in->tx > 600 && in->ty > 380) s_cores = (s_cores == 3) ? 1 : 3;
   s_credit_y += dt * 26.0f;
}

static void render(void)
{
   const int B = 2;
   int cols = (g_sw + B - 1) / B, rows = (g_sh + B - 1) / B;
   float ph = g_time * 0.30f;
   ph -= (float)((int)(ph / 10.5f)) * 10.5f;
   j_scale = 3.0f * m_exp2(-ph * 1.4427f);
   j_cre = -0.743643887f; j_cim = 0.131825904f;
   if (ph < 0.2f) { j_cre = -0.5f; }
   j_cols = cols; j_rows = rows; j_B = B;
   int n = s_cores;
   for (int c = 0; c < 3; c++)
   {
      j_r0[c] = (c < n) ? rows * c / n : 0;
      j_r1[c] = (c < n) ? rows * (c + 1) / n : 0;
      s_wtime[c] = 0;
   }
   OSTime t0 = OSGetSystemTime();
   if (s_threads_ok)
   {
      for (int c = 0; c < n; c++) OSSignalSemaphore(&s_go[c]);
      for (int c = 0; c < n; c++) OSWaitSemaphore(&s_done[c]);
   }
   else
   {
      for (int c = 0; c < n; c++)
      {
         OSTime a = OSGetSystemTime();
         render_band(c);
         s_wtime[c] = OSGetSystemTime() - a;
      }
   }
   s_job_ms = (float)OSTicksToMicroseconds(OSGetSystemTime() - t0) / 1000.0f;
   for (int c = 0; c < 3; c++) s_core_ms[c] = (float)OSTicksToMicroseconds(s_wtime[c]) / 1000.0f;
   float *ema = (n == 3) ? &s_ms_three : &s_ms_one;
   *ema = (*ema <= 0.0f) ? s_job_ms : *ema * 0.9f + s_job_ms * 0.1f;
}

static const char *kCredits[] = {
   "MUFFINEMU SHOWCASE", "", "A WII U HOMEBREW DEMO", "BUILT TO RUN ON MUFFINEMU", "AND ON REAL HARDWARE", "",
   "CODE, MUSIC AND GRAPHICS", "ORIGINAL WORK BY MUFFINEMU", "", "BUILT WITH DEVKITPRO", "DEVKITPPC AND WUT", "",
   "ALL SOUND IS SYNTHESISED", "IN CODE - NO SAMPLES", "", "ALL TEXT USES A FONT", "DRAWN BY THIS PROGRAM", "",
   "NO NINTENDO CODE OR ASSETS", "", "BASED ON THE CEMU LINEAGE", "MPL-2.0", "", "THANKS FOR WATCHING", "", "", "" };
#define NCRED ((int)(sizeof(kCredits) / sizeof(kCredits[0])))

static void bar(Surf *s, int x, int y, int w, int h, float frac, u32 c)
{
   s_rect(s, x, y, w, h, RGB(24, 20, 52));
   s_rect(s, x, y, (int)((float)w * m_clamp(frac, 0.0f, 1.0f)), h, c);
   s_box_outline(s, x, y, w, h, COL_DIM);
}

static void hud(void)
{
   s_panel(&S_TV, TV_W - 440, 24, 416, 330, COL_ACCENT);
   int x = TV_W - 424, y = 36;
   s_textf(&S_TV, x, y, 3, COL_WHITE, "%d FPS", (int)(g_stats.fps + 0.5f));
   s_textf(&S_TV, x + 190, y + 4, 2, COL_DIM, "%.1f MS", g_stats.frame_ms);
   s_textf(&S_TV, x, y + 36, 2, COL_CYAN, "UPDATE %.1f  RENDER %.1f", g_stats.update_ms, g_stats.render_ms);
   s_textf(&S_TV, x, y + 58, 2, COL_CYAN, "PRESENT %.1f MS", g_stats.present_ms);
   s_textf(&S_TV, x, y + 92, 2, COL_ACCENT, "JOB ON %d CORE%s  %.1f MS", s_cores, s_cores == 1 ? "" : "S", s_job_ms);
   for (int c = 0; c < 3; c++)
   {
      s_textf(&S_TV, x, y + 122 + c * 30, 2, COL_WHITE, "CPU%d", c);
      bar(&S_TV, x + 80, y + 122 + c * 30, 320, 20, s_core_ms[c] / (s_job_ms + 0.001f), kRowColor(c));
   }
   if (s_ms_one > 0.0f && s_ms_three > 0.0f)
      s_textf(&S_TV, x, y + 218, 2, COL_GREEN, "3 CORES = %.2fX FASTER", s_ms_one / s_ms_three);
   else
      s_text_sh(&S_TV, x, y + 218, 2, COL_DIM, "PRESS X TO COMPARE 1 VS 3");
   uint32_t a, sz = 0;
   OSGetMemBound(OS_MEM1, &a, &sz);
   s_textf(&S_TV, x, y + 248, 2, COL_WHITE, "MEM1 %u MB", sz >> 20);
   OSGetMemBound(OS_MEM2, &a, &sz);
   struct mallinfo mi = mallinfo();
   s_textf(&S_TV, x, y + 270, 2, COL_WHITE, "MEM2 %u MB  HEAP %d KB", sz >> 20, mi.uordblks >> 10);

   // Credits scroller inside a clipped panel.
   int px = 24, py = TV_H - 214, pw = 460, ph = 190;
   s_panel(&S_TV, px, py, pw, ph, COL_PINK);
   float total = (float)(NCRED * 24);
   for (int i = 0; i < NCRED; i++)
   {
      float yy = (float)ph + (float)(i * 24) - s_credit_y;
      yy = yy - total * (float)m_floor((yy + 24.0f) / total);
      int ty = py + (int)yy;
      if (ty < py + 6 || ty > py + ph - 20) continue;
      int k = ty - py < 30 ? (ty - py) * 8 : (py + ph - ty < 40 ? (py + ph - ty) * 6 : 255);
      if (k > 255) k = 255;
      u32 c = (i == 0) ? COL_ACCENT : COL_WHITE;
      s_text_sh(&S_TV, px + (pw - text_w(kCredits[i], 2)) / 2, ty, 2, col_scale(c, k), kCredits[i]);
   }
}

static void drc(const Input *in)
{
   (void)in;
   s_vgrad(&S_DRC, 0, 0, DRC_W, DRC_H, RGB(14, 12, 34), RGB(6, 6, 18));
   s_text_sh(&S_DRC, 16, 14, 3, COL_ACCENT, "SYSTEM MONITOR");
   s_textf(&S_DRC, 16, 52, 4, COL_WHITE, "%d FPS", (int)(g_stats.fps + 0.5f));
   s_textf(&S_DRC, 200, 62, 2, COL_DIM, "%.1f MS PER FRAME", g_stats.frame_ms);
   // Frame time graph.
   int gx = 16, gy = 110, gw = 480, gh = 130;
   s_rect(&S_DRC, gx, gy, gw, gh, RGB(10, 9, 28));
   s_box_outline(&S_DRC, gx, gy, gw, gh, COL_DIM);
   for (int i = 0; i < 120; i++)
   {
      float v = g_stats.hist[(g_stats.hist_pos + i) % 120];
      int h = (int)(v * (float)gh / 66.0f);
      if (h > gh - 2) h = gh - 2;
      u32 c = v < 17.5f ? COL_GREEN : (v < 34.0f ? COL_ACCENT : COL_RED);
      s_rect(&S_DRC, gx + 2 + i * 4, gy + gh - 1 - h, 3, h, c);
   }
   s_hline(&S_DRC, gx, gy + gh - (int)(16.7f * (float)gh / 66.0f), gw, COL_DIM);
   s_text(&S_DRC, gx + 4, gy + 4, 1, COL_DIM, "FRAME TIME  LINE = 60 FPS");
   for (int c = 0; c < 3; c++)
   {
      s_textf(&S_DRC, 16, 258 + c * 34, 2, COL_WHITE, "CPU%d", c);
      bar(&S_DRC, 90, 258 + c * 34, 330, 22, s_core_ms[c] / (s_job_ms + 0.001f), kRowColor(c));
      s_textf(&S_DRC, 430, 262 + c * 34, 2, COL_DIM, "%.1f MS", s_core_ms[c]);
   }
   int on = (s_cores == 3);
   s_rect(&S_DRC, 560, 258, 280, 100, on ? COL_ACCENT : COL_PANEL);
   s_box_outline(&S_DRC, 560, 258, 280, 100, on ? COL_WHITE : COL_DIM);
   s_text_sh(&S_DRC, 560 + (280 - text_w("3 CORES", 3)) / 2, 280, 3, on ? RGB(30, 20, 10) : COL_WHITE, "3 CORES");
   s_text_sh(&S_DRC, 560 + (280 - text_w("TAP TO SWITCH", 2)) / 2, 322, 2, on ? RGB(70, 40, 10) : COL_DIM, on ? "TAP FOR 1 CORE" : "NOW 1 CORE");
   uint32_t a, s1 = 0, s2 = 0;
   OSGetMemBound(OS_MEM1, &a, &s1);
   OSGetMemBound(OS_MEM2, &a, &s2);
   struct mallinfo mi = mallinfo();
   s_textf(&S_DRC, 16, 372, 2, COL_CYAN, "MEM1 %u MB   MEM2 %u MB", s1 >> 20, s2 >> 20);
   s_textf(&S_DRC, 16, 396, 2, COL_CYAN, "HEAP IN USE %d KB OF %d KB", mi.uordblks >> 10, mi.arena >> 10);
   bar(&S_DRC, 16, 424, 480, 14, (float)mi.uordblks / ((float)mi.arena + 1.0f), COL_PINK);
   s_text(&S_DRC, 16, 448, 2, COL_DIM, "OSTHREAD X3  OSSEMAPHORE  OSGETMEMBOUND");
}

const Scene sc_stress = {
   "STRESS AND INFO", "THREE-CORE JOB, FRAME TIMING, MEMORY AND CREDITS", 4, enter, update, render, hud, drc
};
