// Procedural chiptune, see synth.h.
//
// 16 bars of A minor at 132 BPM across four channels: a 25% pulse lead with a
// dotted-eighth echo, a 50% pulse arpeggio, a quantised triangle bass and a drum
// kit built from a pitch-swept sine (kick), noise plus a tone (snare) and
// differentiated noise (hats). Each channel is its own looping buffer so the
// player can mute them independently and meter them separately.

#include "synth.h"

#include <math.h>
#include <stdbool.h>
#include <string.h>

#define TWO_PI 6.28318530718f

static uint64_t slot_start(int slot)
{
   return (uint64_t)slot * SONG_RATE * 30u / SONG_BPM;
}

static uint64_t sixteenth_start(int k)
{
   return (uint64_t)k * SONG_RATE * 15u / SONG_BPM;
}

int synth_bar_at(uint32_t sample)
{
   uint64_t slot = (uint64_t)sample * SONG_BPM / ((uint64_t)SONG_RATE * 30u);
   int bar = (int)(slot / 8u);
   return bar >= SONG_BARS ? SONG_BARS - 1 : bar;
}

static float midi_hz(int n)
{
   return 440.0f * powf(2.0f, (float)(n - 69) / 12.0f);
}

// ---- composition ----------------------------------------------------------

enum { Am, F, Cc, G, Dm, E };

static const struct { int arpRoot, bassRoot, third; } kChord[6] = {
   {57, 45, 3}, {53, 41, 4}, {60, 48, 4}, {55, 43, 4}, {62, 38, 3}, {52, 40, 4},
};

static const unsigned char kProg[SONG_BARS] = {
   Am, F, Cc, G, Am, F, Cc, G, Am, F, Dm, E, Am, F, G, E,
};

// eighth-note slots, 255 = hold the previous note
static const unsigned char kMelody[SONG_BARS][8] = {
   {76, 255, 72, 255, 69, 255, 72, 76}, {77, 255, 72, 255, 69, 255, 72, 77},
   {76, 255, 79, 255, 76, 255, 72, 76}, {74, 255, 79, 255, 74, 255, 71, 74},
   {81, 255, 76, 255, 72, 255, 76, 81}, {81, 255, 77, 255, 72, 255, 77, 81},
   {79, 255, 76, 255, 72, 255, 76, 79}, {79, 255, 74, 255, 71, 255, 74, 79},
   {81, 255, 255, 255, 76, 255, 72, 255}, {77, 255, 255, 255, 72, 255, 69, 255},
   {74, 255, 77, 255, 81, 255, 77, 74}, {76, 255, 80, 255, 83, 255, 80, 76},
   {81, 83, 84, 255, 83, 81, 76, 255}, {77, 79, 81, 255, 79, 77, 72, 255},
   {79, 81, 83, 255, 86, 255, 83, 79}, {80, 255, 83, 255, 76, 255, 255, 255},
};

const char *synth_chord_name(int bar)
{
   static const char *names[6] = {"AM", "F", "C", "G", "DM", "E"};
   if (bar < 0) bar = 0;
   return names[kProg[bar % SONG_BARS]];
}

// ---- helpers --------------------------------------------------------------

static uint32_t sRng = 0x12345678u;
static float noise(void)
{
   sRng ^= sRng << 13;
   sRng ^= sRng >> 17;
   sRng ^= sRng << 5;
   return (float)(int32_t)sRng * (1.0f / 2147483648.0f);
}

static float pulse(float ph, float duty) { return ph < duty ? 1.0f : -1.0f; }

static float tri_q(float ph)
{
   float t = ph < 0.5f ? ph * 4.0f - 1.0f : 3.0f - ph * 4.0f;
   return floorf(t * 7.5f + 0.5f) * (1.0f / 7.5f);   // 16-level, NES-style
}

static void clear(float *buf) { memset(buf, 0, sizeof(float) * SONG_SAMPLES); }

static void lowpass(float *buf, float k)
{
   float y = 0.0f;
   for (int i = 0; i < SONG_SAMPLES; i++) {
      y += k * (buf[i] - y);
      buf[i] = y;
   }
}

static int16_t clamp16(float v)
{
   if (v > 32767.0f) return 32767;
   if (v < -32768.0f) return -32768;
   return (int16_t)(v >= 0 ? v + 0.5f : v - 0.5f);
}

// Mix `buf` (with optional wrapped echoes) into out, then scale to a target peak.
static void finish(const float *buf, int16_t *out, int delay, float e1, float e2, float target)
{
   for (int i = 0; i < SONG_SAMPLES; i++) {
      float v = buf[i];
      if (delay > 0) {
         v += e1 * buf[(i - delay + SONG_SAMPLES) % SONG_SAMPLES];
         v += e2 * buf[(i - 2 * delay + 2 * SONG_SAMPLES) % SONG_SAMPLES];
      }
      out[i] = clamp16(v * 10000.0f);
   }
   // a 25% pulse is far from zero-mean: take the DC out before scaling to the target peak
   double mean = 0.0;
   for (int i = 0; i < SONG_SAMPLES; i++) mean += out[i];
   mean /= SONG_SAMPLES;
   for (int i = 0; i < SONG_SAMPLES; i++) out[i] = clamp16((float)((double)out[i] - mean));
   int peak = 1;
   for (int i = 0; i < SONG_SAMPLES; i++) {
      int a = out[i] < 0 ? -out[i] : out[i];
      if (a > peak) peak = a;
   }
   float scale = target / (float)peak;
   for (int i = 0; i < SONG_SAMPLES; i++) out[i] = clamp16((float)out[i] * scale);
}

#define ADD(i, v) do { int ii_ = (i); if (ii_ >= 0 && ii_ < SONG_SAMPLES) buf[ii_] += (v); } while (0)

// ---- channels -------------------------------------------------------------

static void render_lead(float *buf, volatile int *progress)
{
   clear(buf);
   int s = 0;
   while (s < SONG_SLOTS) {
      int bar = s / 8, j = s % 8;
      int note = kMelody[bar][j];
      if (note == 255) { s++; continue; }
      int e = s + 1;
      while (e < SONG_SLOTS && kMelody[e / 8][e % 8] == 255) e++;
      int start = (int)slot_start(s);
      int len = (int)slot_start(e) - start;
      float hz = midi_hz(note);
      float ph = 0.0f;
      for (int t = 0; t < len; t++) {
         float sec = (float)t / SONG_RATE;
         float vib = sec > 0.18f ? 1.0f + 0.005f * sinf(TWO_PI * 5.5f * (sec - 0.18f)) : 1.0f;
         ph += hz * vib / SONG_RATE;
         ph -= floorf(ph);
         float env = (t < 48 ? (float)t / 48.0f : 1.0f) * (0.62f + 0.38f * expf(-sec * 5.0f));
         int rel = len - t;
         if (rel < 160) env *= (float)rel / 160.0f;
         ADD(start + t, pulse(ph, 0.25f) * env * 0.5f);
      }
      s = e;
   }
   lowpass(buf, 0.55f);
   if (progress) *progress = 100;
}

static void render_arp(float *buf, volatile int *progress)
{
   clear(buf);
   static const int seq[8] = {0, 1, 2, 3, 2, 1, 2, 1};
   for (int k = 0; k < SONG_SLOTS * 2; k++) {
      int bar = k / 16, pos = k % 16;
      int c = kProg[bar];
      int tones[4] = {kChord[c].arpRoot, kChord[c].arpRoot + kChord[c].third,
                      kChord[c].arpRoot + 7, kChord[c].arpRoot + 12};
      float hz = midi_hz(tones[seq[pos % 8]]);
      int start = (int)sixteenth_start(k);
      int len = (int)sixteenth_start(k + 1) - start;
      int gate = (len * 85) / 100;
      float ph = 0.0f;
      for (int t = 0; t < gate; t++) {
         float sec = (float)t / SONG_RATE;
         ph += hz / SONG_RATE;
         ph -= floorf(ph);
         float env = (t < 24 ? (float)t / 24.0f : 1.0f) * (0.25f + 0.75f * expf(-sec * 12.0f));
         int rel = gate - t;
         if (rel < 80) env *= (float)rel / 80.0f;
         ADD(start + t, pulse(ph, 0.5f) * env * 0.5f);
      }
      if (progress) *progress = k * 100 / (SONG_SLOTS * 2);
   }
   lowpass(buf, 0.5f);
   if (progress) *progress = 100;
}

static void render_bass(float *buf, volatile int *progress)
{
   clear(buf);
   static const int off[8] = {0, 0, 12, 0, 0, 12, 0, 7};
   for (int s = 0; s < SONG_SLOTS; s++) {
      int bar = s / 8, j = s % 8;
      int root = kChord[kProg[bar]].bassRoot;
      float hz = midi_hz(root + off[j]);
      int start = (int)slot_start(s);
      int len = (int)slot_start(s + 1) - start;
      int gate = (len * 92) / 100;
      float ph = 0.0f;
      for (int t = 0; t < gate; t++) {
         float sec = (float)t / SONG_RATE;
         ph += hz / SONG_RATE;
         ph -= floorf(ph);
         float env = (t < 40 ? (float)t / 40.0f : 1.0f) * (0.7f + 0.3f * expf(-sec * 6.0f));
         int rel = gate - t;
         if (rel < 100) env *= (float)rel / 100.0f;
         ADD(start + t, tri_q(ph) * env);
      }
      if (progress) *progress = s * 100 / SONG_SLOTS;
   }
   lowpass(buf, 0.8f);
   if (progress) *progress = 100;
}

static void kick(float *buf, int start, float vol)
{
   int len = SONG_RATE * 16 / 100;
   float ph = 0.0f;
   for (int t = 0; t < len; t++) {
      float sec = (float)t / SONG_RATE;
      float hz = 45.0f + 125.0f * expf(-sec * 38.0f);
      ph += hz / SONG_RATE;
      ph -= floorf(ph);
      ADD(start + t, sinf(TWO_PI * ph) * expf(-sec * 17.0f) * vol * 1.2f);
   }
}

static void snare(float *buf, int start, float vol)
{
   int len = SONG_RATE * 19 / 100;
   for (int t = 0; t < len; t++) {
      float sec = (float)t / SONG_RATE;
      float n = noise() * expf(-sec * 21.0f) * 0.75f;
      float tone = sinf(TWO_PI * 190.0f * sec) * expf(-sec * 32.0f) * 0.5f;
      ADD(start + t, (n + tone) * vol);
   }
}

static void hat(float *buf, int start, float vol, float decay, int lenSamples)
{
   float prev = 0.0f;
   for (int t = 0; t < lenSamples; t++) {
      float sec = (float)t / SONG_RATE;
      float n = noise();
      ADD(start + t, (n - prev) * 0.5f * expf(-sec * decay) * vol);
      prev = n;
   }
}

static void render_drums(float *buf, volatile int *progress)
{
   clear(buf);
   sRng = 0x9E3779B9u;
   for (int bar = 0; bar < SONG_BARS; bar++) {
      bool fill = (bar % 4) == 3;
      for (int j = 0; j < 8; j++) {
         int s = bar * 8 + j;
         int t0 = (int)slot_start(s);
         int t1 = (int)slot_start(s) + (int)(slot_start(s + 1) - slot_start(s)) / 2;

         bool k = (j == 0 || j == 3 || j == 4) || (fill && j == 7);
         if (k) kick(buf, t0, j == 0 ? 1.0f : 0.8f);
         if (j == 2 || j == 6) snare(buf, t0, 0.8f);
         if (fill && j == 7) {
            snare(buf, t0, 0.7f);
            snare(buf, t1, 0.8f);
         }
         if (j == 7 && (bar % 2) == 1) {
            hat(buf, t0, 0.9f, 22.0f, SONG_RATE * 15 / 100);
         } else {
            hat(buf, t0, (j % 2) ? 0.55f : 0.8f, 95.0f, SONG_RATE * 4 / 100);
         }
         hat(buf, t1, 0.3f, 110.0f, SONG_RATE * 3 / 100);
      }
      if (progress) *progress = bar * 100 / SONG_BARS;
   }
   if (progress) *progress = 100;
}

void synth_channel(int ch, int16_t *out, float *scratch, volatile int *progress)
{
   int delay = (int)sixteenth_start(3);   // dotted eighth
   switch (ch) {
   case CH_LEAD:
      render_lead(scratch, progress);
      finish(scratch, out, delay, 0.34f, 0.17f, 6800.0f);
      break;
   case CH_ARP:
      render_arp(scratch, progress);
      finish(scratch, out, delay, 0.22f, 0.10f, 4400.0f);
      break;
   case CH_BASS:
      render_bass(scratch, progress);
      finish(scratch, out, 0, 0, 0, 8800.0f);
      break;
   default:
      render_drums(scratch, progress);
      finish(scratch, out, 0, 0, 0, 9000.0f);
      break;
   }
}

void synth_sfx(int16_t *out)
{
   memset(out, 0, sizeof(int16_t) * SFX_COUNT * SFX_SAMPLES);

   // 0: tick, rising square sweep
   {
      float ph = 0.0f;
      int len = SONG_RATE * 7 / 100;
      for (int t = 0; t < len; t++) {
         float f = (float)t / (float)len;
         ph += (900.0f + 500.0f * f) / SONG_RATE;
         ph -= floorf(ph);
         out[t] = clamp16(pulse(ph, 0.5f) * (1.0f - f) * 6500.0f);
      }
   }
   // 1: select, quick major arpeggio
   {
      static const int n[4] = {72, 76, 79, 84};
      int seg = SONG_RATE * 5 / 100;
      float ph = 0.0f;
      for (int q = 0; q < 4; q++) {
         float hz = midi_hz(n[q]);
         for (int t = 0; t < seg; t++) {
            ph += hz / SONG_RATE;
            ph -= floorf(ph);
            float env = expf(-(float)t / SONG_RATE * 18.0f);
            int i = q * seg + t;
            if (i < SFX_SAMPLES) out[SFX_SAMPLES + i] = clamp16(pulse(ph, 0.25f) * env * 6500.0f);
         }
      }
   }
   // 2: back, falling sweep
   {
      float ph = 0.0f;
      int len = SONG_RATE * 12 / 100;
      for (int t = 0; t < len; t++) {
         float f = (float)t / (float)len;
         ph += (700.0f - 400.0f * f) / SONG_RATE;
         ph -= floorf(ph);
         out[2 * SFX_SAMPLES + t] = clamp16(pulse(ph, 0.5f) * (1.0f - f) * 6500.0f);
      }
   }
}
