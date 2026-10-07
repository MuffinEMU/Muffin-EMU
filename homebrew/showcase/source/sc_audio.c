// Scene 5: audio. A live view of the procedural soundtrack: the waveform is read straight out of
// the PCM buffer at the AX voice's current play offset, the grid and piano roll show the sequencer
// pattern, and the GamePad picks tracks, mutes and sets the volume.
#include "showcase.h"

static float meter[6];
static int last_step = -1;
static const char *kRows[6] = { "KICK", "SNARE", "HAT", "BASS", "LEAD", "ARP" };
static const int kRowBit[6] = { EV_KICK, EV_SNARE, EV_HAT, EV_BASS, EV_LEAD, EV_ARP };
static const u32 kRowCol[6] = { RGB(255,110,80), RGB(255,200,90), RGB(190,230,120), RGB(90,210,255), RGB(255,120,200), RGB(170,150,255) };

static int view_track(void) { return audio_track(); }

static void enter(void) { g_audio_track_override = -1; }

static void update(const Input *in, float dt, int demo)
{
   int t = view_track();
   if (!demo)
   {
      if (in->trig & B_RIGHT) { t = (t + 1) % NUM_TRACKS; g_audio_track_override = t; }
      if (in->trig & B_LEFT) { t = (t + NUM_TRACKS - 1) % NUM_TRACKS; g_audio_track_override = t; }
      if (in->trig & B_A) audio_set_mute(!audio_muted());
      if (in->hold & B_UP) audio_set_volume(audio_volume() + 0.6f * dt);
      if (in->hold & B_DOWN) audio_set_volume(audio_volume() - 0.6f * dt);
      if (in->touched)
      {
         if (in->touch_trig && in->tx >= 16 && in->tx < 416 && in->ty >= 50 && in->ty < 310)
         {
            int i = (int)((in->ty - 50) / 52);
            if (i >= 0 && i < NUM_TRACKS) g_audio_track_override = i;
         }
         if (in->touch_trig && in->tx >= 440 && in->tx < 838 && in->ty >= 50 && in->ty < 100)
            audio_set_mute(!audio_muted());
         if (in->tx >= 440 && in->tx < 838 && in->ty >= 118 && in->ty < 170)
            audio_set_volume((in->tx - 450.0f) / 378.0f);
      }
   }
   else if (g_time > 0.0f)
   {
      int want = ((int)(g_time / 3.5f)) % NUM_TRACKS;
      g_audio_track_override = want;
   }
   int st = audio_step();
   if (st != last_step)
   {
      u8 ev = audio_event(view_track(), st);
      for (int i = 0; i < 6; i++) if (ev & kRowBit[i]) meter[i] = 1.0f;
      last_step = st;
   }
   for (int i = 0; i < 6; i++) { meter[i] -= dt * 3.0f; if (meter[i] < 0) meter[i] = 0; }
}

static void render(void)
{
   const int W = g_sw, H = g_sh;
   s_vgrad(&S_SCN, 0, 0, W, H, RGB(14, 8, 34), RGB(40, 14, 60));
   int len = 0;
   const s16 *pcm = audio_pcm(view_track(), &len);
   int pos = audio_pcm_pos();
   int mid = H * 2 / 5;
   int cols = W;
   for (int x = 0; x < cols; x++)
   {
      int a = 0;
      if (pcm && pos >= 0)
      {
         int base = pos + x * 24;
         for (int k = 0; k < 24; k += 3)
         {
            int s = pcm[(base + k) % len];
            if (s < 0) s = -s;
            if (s > a) a = s;
         }
      }
      else
         a = (int)(m_abs(m_sin(g_time * 3.0f + (float)x * 0.07f)) * 5000.0f);
      int h = a * (H / 3) / 24000;
      if (h > H / 3) h = H / 3;
      u32 c = hsv((float)x / (float)W * 0.8f + g_time * 0.05f, 0.65f, 1.0f);
      s_rect(&S_SCN, x, mid - h, 1, 2 * h + 1, c);
   }
   s_hline(&S_SCN, 0, mid, W, RGB(80, 70, 140));
   // Meters as a rising skyline.
   int bw = W / 6;
   for (int i = 0; i < 6; i++)
   {
      int h = (int)(meter[i] * (float)(H / 4));
      s_rect(&S_SCN, i * bw + 2, H - 1 - h, bw - 4, h, col_scale(kRowCol[i], 90 + (int)(meter[i] * 160)));
   }
}

static void grid(Surf *s, int x0, int y0, int cw, int ch, int t, int labels)
{
   int st = audio_step();
   for (int r = 0; r < 6; r++)
   {
      if (labels) s_text(s, x0 - 66, y0 + r * ch + (ch - 14) / 2, 2, kRowCol[r], kRows[r]);
      for (int c = 0; c < 64; c++)
      {
         int on = (audio_event(t, c) & kRowBit[r]) != 0;
         u32 col = on ? kRowCol[r] : RGB(30, 26, 58);
         if (c == st) col = on ? COL_WHITE : RGB(70, 64, 120);
         else if ((c & 15) == 0 && !on) col = RGB(44, 38, 80);
         s_rect(s, x0 + c * cw, y0 + r * ch, cw - 1, ch - 2, col);
      }
   }
}

static void hud(void)
{
   int t = view_track();
   s_panel(&S_TV, 24, 24, 640, 92, COL_PINK);
   s_text_sh(&S_TV, 40, 36, 3, COL_ACCENT, audio_track_name(t));
   s_textf(&S_TV, 40, 76, 2, COL_WHITE, "%d BPM   %s   VOL %d%%", audio_track_bpm(t), audio_muted() ? "MUTED" : "PLAYING", (int)(audio_volume() * 100.0f));
   if (!audio_ready(t)) s_text_sh(&S_TV, 700, 50, 3, COL_RED, "RENDERING...");
   s_panel(&S_TV, 20, 520, 1240, 170, COL_CYAN);
   grid(&S_TV, 98, 534, 18, 22, t, 1);
   s_text(&S_TV, 98, 672, 2, COL_DIM, "SEQUENCER  64 STEPS  4 BARS");
}

static void drc(const Input *in)
{
   (void)in;
   int t = view_track();
   s_vgrad(&S_DRC, 0, 0, DRC_W, DRC_H, RGB(14, 12, 34), RGB(6, 6, 18));
   s_text_sh(&S_DRC, 16, 14, 3, COL_ACCENT, "SOUNDTRACK");
   for (int i = 0; i < NUM_TRACKS; i++)
   {
      int y = 50 + i * 52, on = (i == t), rdy = audio_ready(i);
      s_rect(&S_DRC, 16, y, 400, 46, on ? COL_ACCENT : COL_PANEL);
      s_box_outline(&S_DRC, 16, y, 400, 46, on ? COL_WHITE : COL_DIM);
      s_textf(&S_DRC, 28, y + 6, 2, on ? RGB(30, 20, 10) : COL_WHITE, "%d %s", i + 1, audio_track_name(i));
      s_textf(&S_DRC, 28, y + 26, 2, on ? RGB(70, 40, 10) : COL_DIM, rdy ? "%d BPM" : "RENDERING", audio_track_bpm(i));
   }
   int mu = audio_muted();
   s_rect(&S_DRC, 440, 50, 398, 50, mu ? COL_RED : COL_PANEL);
   s_box_outline(&S_DRC, 440, 50, 398, 50, mu ? COL_WHITE : COL_GREEN);
   s_text_sh(&S_DRC, 440 + (398 - text_w(mu ? "MUTED  TAP TO UNMUTE" : "SOUND ON  TAP TO MUTE", 2)) / 2, 68, 2, COL_WHITE, mu ? "MUTED  TAP TO UNMUTE" : "SOUND ON  TAP TO MUTE");
   s_text(&S_DRC, 440, 108, 2, COL_DIM, "VOLUME");
   s_rect(&S_DRC, 450, 132, 378, 14, COL_PANEL);
   s_rect(&S_DRC, 450, 132, (int)(378.0f * audio_volume()), 14, COL_CYAN);
   s_disc(&S_DRC, 450 + (int)(378.0f * audio_volume()), 139, 10, COL_WHITE);
   s_textf(&S_DRC, 440, 172, 2, COL_DIM, "AX VOICE  %s", audio_pcm_pos() >= 0 ? "PLAYING" : "NO OUTPUT");
   if (audio_progress() < 100) s_textf(&S_DRC, 440, 196, 2, COL_ACCENT, "RENDERING TRACKS %d%%", audio_progress());
   // Piano roll of the lead melody with playhead.
   int px = 16, py = 330, pw = 822, ph = 110;
   s_rect(&S_DRC, px, py, pw, ph, RGB(10, 9, 28));
   s_box_outline(&S_DRC, px, py, pw, ph, COL_DIM);
   for (int c = 0; c < 64; c++)
   {
      int n = audio_lead_note(t, c);
      if (n >= 0)
      {
         int y = py + ph - 8 - n * (ph - 16) / 36;
         s_rect(&S_DRC, px + c * pw / 64 + 1, y, pw / 64 - 1, 5, kRowCol[4]);
      }
   }
   int st = audio_step();
   s_vline(&S_DRC, px + st * pw / 64, py, ph, COL_WHITE);
   s_text(&S_DRC, px, py - 18, 2, COL_DIM, "LEAD LINE");
}

const Scene sc_audio = {
   "AUDIO", "PROCEDURAL CHIPTUNE THROUGH THE AX MIXER, SEQUENCER VIEW", 0, enter, update, render, hud, drc
};
