// Sound Room: the four music channels, live. Every sample was synthesized at boot on
// core 2 and plays on its own AX voice, so each channel can be muted separately.
// The spectrum is a 24-band Goertzel filter bank run over the mix, and the scope is
// the raw waveform at the playback position.

#include "app.h"
#include "audio.h"
#include "gfx.h"
#include "ui.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static const char *kChName[CH_COUNT] = {"LEAD", "ARPEGGIO", "BASS", "DRUMS"};
static const char *kChWave[CH_COUNT] = {"25% PULSE + ECHO", "50% PULSE + ECHO", "4-BIT TRIANGLE", "KICK SNARE HATS"};
static const uint32_t kChBtn[CH_COUNT] = {VPAD_BUTTON_A, VPAD_BUTTON_X, VPAD_BUTTON_Y, VPAD_BUTTON_ZR};
static const char *kChKey[CH_COUNT] = {"A", "X", "Y", "ZR"};

static float sBands[SPECTRUM_BANDS], sPeak[SPECTRUM_BANDS], sPeakHold[SPECTRUM_BANDS];
static float sScope[128];
static float sUiM[16];
static Batch *sTv, *sDrc;
static float sPulse;

static Col ch_col(int c)
{
   static const Col cols[CH_COUNT] = {{1.0f, 0.55f, 0.75f, 1}, {0.55f, 0.85f, 1.0f, 1}, {1.0f, 0.85f, 0.35f, 1}, {0.65f, 1.0f, 0.55f, 1}};
   return cols[c];
}

static void snd_enter(void) {}
static void snd_leave(void) {}

static void toggle(int c)
{
   audio_toggle_channel(c);
   audio_sfx(g_audio.chMute[c] ? 2 : 1);
}

static void snd_update(float dt)
{
   m4_ortho_ui(sUiM);

   for (int c = 0; c < CH_COUNT; c++) if (PRESSED(kChBtn[c])) toggle(c);
   if (g_in.touchStart) {
      for (int c = 0; c < CH_COUNT; c++) {
         float x = 90.0f + (float)(c % 2) * 560.0f, y = 100.0f + (float)(c / 2) * 235.0f;
         if (ui_hit(g_in.tx, g_in.ty, x, y, 540.0f, 220.0f)) toggle(c);
      }
   }

   // spectrum with smoothing and peak hold
   audio_spectrum(sBands, SPECTRUM_BANDS);
   for (int i = 0; i < SPECTRUM_BANDS; i++) {
      if (sBands[i] > sPeak[i]) sPeak[i] = sBands[i];
      else sPeak[i] -= dt * 2.2f;
      if (sPeak[i] < 0.0f) sPeak[i] = 0.0f;
      if (sBands[i] > sPeakHold[i]) sPeakHold[i] = sBands[i];
      else sPeakHold[i] -= dt * 0.5f;
      if (sPeakHold[i] < 0.0f) sPeakHold[i] = 0.0f;
   }
   sPulse = g_audio.beat;

   // scope: 1024 samples of the unmuted mix, every 8th
   memset(sScope, 0, sizeof(sScope));
   if (g_audio.ready && g_audio.playing) {
      uint32_t idx = audio_sample_index();
      for (int i = 0; i < 128; i++) {
         int p = (int)idx - (127 - i) * 8;
         while (p < 0) p += SONG_SAMPLES;
         float v = 0.0f;
         for (int c = 0; c < CH_COUNT; c++) {
            if (!g_audio.chMute[c] && !g_audio.muted) v += (float)audio_samples(c)[p];
         }
         sScope[i] = v / 18000.0f;
      }
   }

   sTv = gfx_batch();
   sDrc = gfx_batch();
   char buf[96];

   // ---- TV ----
   Batch *b = sTv;
   if (!g_audio.ready) {
      snprintf(buf, sizeof(buf), "SYNTHESIZING  %d%%", g_audio.synthPct);
      b_text_center(b, VW * 0.5f, 300.0f, 5.0f, C(1.0f, 0.9f, 0.6f, 1), buf);
      ui_bar(b, 340.0f, 380.0f, 600.0f, 22.0f, (float)g_audio.synthPct / 100.0f, C(1.0f, 0.65f, 0.3f, 1));
      b_text_center(b, VW * 0.5f, 430.0f, 2.0f, C(1, 1, 1, 0.8f), "700,000 SAMPLES PER CHANNEL, COMPUTED ON CORE 2");
   } else {
      // big chord and bar
      b_text_shadow(b, 60.0f, 96.0f, 9.0f, hsv(0.08f + 0.05f * sPulse, 0.6f, 1.0f, 1), synth_chord_name(g_audio.bar));
      snprintf(buf, sizeof(buf), "BAR %d OF %d", g_audio.bar + 1, SONG_BARS);
      b_text_shadow(b, 300.0f, 104.0f, 3.0f, C(1, 1, 1, 0.95f), buf);
      snprintf(buf, sizeof(buf), "%d BPM  A MINOR  %s", SONG_BPM, g_audio.muted ? "MUTED" : "PLAYING");
      b_text_shadow(b, 300.0f, 140.0f, 2.2f, C(0.85f, 0.8f, 1.0f, 0.95f), buf);

      // spectrum
      float x0 = 80.0f, w = 1120.0f / (float)SPECTRUM_BANDS, base = 470.0f, maxh = 280.0f;
      for (int i = 0; i < SPECTRUM_BANDS; i++) {
         float h = sPeak[i] * maxh;
         Col c = hsv(0.95f - (float)i / (float)SPECTRUM_BANDS * 0.7f, 0.65f, 1.0f, 1.0f);
         b_rect_grad(b, x0 + (float)i * w + 3.0f, base - h, w - 6.0f, h, c, CMUL(c, 0.35f));
         b_rect(b, x0 + (float)i * w + 3.0f, base - sPeakHold[i] * maxh - 5.0f, w - 6.0f, 4.0f, C(1, 1, 1, 0.9f));
         b_rect(b, x0 + (float)i * w + 3.0f, base + 4.0f, w - 6.0f, h * 0.18f, CA(c, 0.18f));   // faint reflection
      }

      // scope
      b_rect(b, 80.0f, 520.0f, 1120.0f, 90.0f, C(0, 0, 0, 0.35f));
      for (int i = 0; i < 127; i++) {
         float xa = 80.0f + (float)i * (1120.0f / 127.0f), xb = 80.0f + (float)(i + 1) * (1120.0f / 127.0f);
         float ya = 565.0f - sScope[i] * 40.0f, yb = 565.0f - sScope[i + 1] * 40.0f;
         b_line(b, xa, ya, xb, yb, 3.0f, C(0.6f, 1.0f, 0.8f, 0.9f));
      }
   }
   // channel strips
   for (int c = 0; c < CH_COUNT; c++) {
      float x = 80.0f + (float)c * 285.0f;
      bool off = g_audio.chMute[c] || g_audio.muted;
      b_rect(b, x, 622.0f, 270.0f, 46.0f, C(0, 0, 0, 0.55f));
      snprintf(buf, sizeof(buf), "%s %s", kChKey[c], kChName[c]);
      b_text_shadow(b, x + 10.0f, 628.0f, 2.0f, off ? C(1, 1, 1, 0.35f) : ch_col(c), buf);
      ui_bar(b, x + 10.0f, 652.0f, 250.0f, 10.0f, g_audio.level[c], ch_col(c));
   }
   snprintf(buf, sizeof(buf), "%s", g_audio.clockFallback ? "VISUALS SYNCED TO CLOCK, NO AUDIO OUT" : "AX VOICES ACTIVE");
   ui_header(b, "SOUND ROOM", buf);
   ui_footer(b, "A X Y ZR: MUTE LEAD ARP BASS DRUMS   -: MUTE ALL   B: MENU");

   // ---- GamePad ----
   b = sDrc;
   ui_header(b, "MIXER", "TAP A PAD TO MUTE A CHANNEL");
   for (int c = 0; c < CH_COUNT; c++) {
      float x = 90.0f + (float)(c % 2) * 560.0f, y = 100.0f + (float)(c / 2) * 235.0f;
      bool off = g_audio.chMute[c] || g_audio.muted;
      Col col = ch_col(c);
      b_rect(b, x - 3.0f, y - 3.0f, 546.0f, 226.0f, C(0, 0, 0, 0.7f));
      b_rect_grad(b, x, y, 540.0f, 220.0f, off ? C(0.12f, 0.12f, 0.16f, 1) : CMUL(col, 0.30f), off ? C(0.07f, 0.07f, 0.10f, 1) : CMUL(col, 0.14f));
      // level fill from the bottom
      float lv = g_audio.level[c];
      b_rect_grad(b, x, y + 220.0f * (1.0f - lv), 540.0f, 220.0f * lv, CA(col, off ? 0.0f : 0.65f), CA(col, off ? 0.0f : 0.25f));
      b_text_shadow(b, x + 20.0f, y + 18.0f, 4.0f, off ? C(1, 1, 1, 0.4f) : C(1, 1, 1, 1), kChName[c]);
      b_text_shadow(b, x + 22.0f, y + 62.0f, 2.0f, C(1, 1, 1, off ? 0.35f : 0.8f), kChWave[c]);
      b_text_shadow(b, x + 22.0f, y + 176.0f, 3.2f, off ? C(1.0f, 0.5f, 0.5f, 1) : C(0.7f, 1.0f, 0.7f, 1), off ? "MUTED" : "ON");
      snprintf(buf, sizeof(buf), "BUTTON %s", kChKey[c]);
      b_text_shadow(b, x + 330.0f, y + 186.0f, 2.0f, C(1, 1, 1, 0.6f), buf);
   }
   b_rect(b, 90.0f, 572.0f, 1010.0f, 80.0f, C(0, 0, 0, 0.5f));
   for (int i = 0; i < 127; i++) {
      float xa = 90.0f + (float)i * (1010.0f / 127.0f), xb = 90.0f + (float)(i + 1) * (1010.0f / 127.0f);
      b_line(b, xa, 612.0f - sScope[i] * 34.0f, xb, 612.0f - sScope[i + 1] * 34.0f, 2.5f, C(0.6f, 1.0f, 0.8f, 0.9f));
   }
   ui_footer(b, "TAP A PAD   -: MUTE ALL");
}

static void snd_draw(Target tg)
{
   Batch *bg = gfx_batch();
   b_rect_grad(bg, 0, 0, VW, VH, C(0.04f + 0.05f * sPulse, 0.02f, 0.12f + 0.06f * sPulse, 1), C(0.02f, 0.01f, 0.06f, 1));
   gfx_draw_batch(bg, sUiM, BLEND_OPAQUE, DEPTH_OFF, NULL);
   gfx_draw_batch(tg == TARGET_TV ? sTv : sDrc, sUiM, BLEND_ALPHA, DEPTH_OFF, NULL);
}

const Scene scene_sound = {
   "SOUND ROOM", "4 CHANNEL CHIPTUNE MADE FROM NOTHING, LIVE MIX", snd_enter, snd_leave, snd_update, NULL, snd_draw, 20.0f,
};
