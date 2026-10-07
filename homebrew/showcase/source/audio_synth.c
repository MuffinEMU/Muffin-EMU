// Showcase soundtrack synth core (see audio_synth.h). Pure C, no platform calls.
#include "audio_synth.h"

#include <malloc.h>
#include <stdlib.h>
#include <string.h>


static const u8 SC_MAJOR[7] = { 0, 2, 4, 5, 7, 9, 11 };
static const u8 SC_MINOR[7] = { 0, 2, 3, 5, 7, 8, 10 };
static const u8 SC_DORIAN[7] = { 0, 2, 3, 5, 7, 9, 10 };
static const u8 SC_MIXO[7] = { 0, 2, 4, 5, 7, 9, 10 };

static const s8 LEAD0[64] = {
   4, R_, 2, R_, 4, R_, 7, R_, 9, R_, 7, R_, 4, R_, R_, R_,
   8, R_, 6, R_, 8, R_, 6, R_, 4, R_, 6, R_, 8, R_, R_, R_,
   9, R_, 7, R_, 5, R_, 7, 9, 10, R_, 9, R_, 7, R_, R_, R_,
   7, R_, 5, R_, 3, R_, 5, R_, 7, R_, 9, R_, 10, R_, 9, R_ };
static const s8 LEAD1[64] = {
   7, R_, R_, 4, R_, R_, 2, R_, 4, R_, R_, R_, 0, R_, R_, R_,
   5, R_, R_, 7, R_, R_, 9, R_, 7, R_, R_, R_, 5, R_, 4, R_,
   9, R_, R_, 11, R_, R_, 13, R_, 11, R_, R_, R_, 9, R_, R_, R_,
   8, R_, R_, 6, R_, R_, 4, R_, 6, R_, R_, R_, 8, R_, 7, R_ };
static const s8 LEAD2[64] = {
   9, R_, R_, R_, R_, R_, 7, R_, R_, R_, 9, R_, R_, R_, R_, R_,
   10, R_, R_, R_, R_, R_, 12, R_, R_, R_, 10, R_, R_, R_, 9, R_,
   11, R_, R_, R_, 13, R_, R_, R_, 11, R_, R_, R_, R_, R_, R_, R_,
   14, R_, R_, R_, R_, R_, 13, R_, 11, R_, R_, R_, 9, R_, R_, R_ };
static const s8 LEAD3[64] = {
   7, 9, 11, 9, 7, R_, 9, R_, 11, R_, 14, R_, 11, 9, 7, R_,
   10, R_, 12, 10, R_, 8, R_, 10, 12, R_, 14, R_, 12, R_, 10, R_,
   14, R_, 11, R_, 9, R_, 11, 14, R_, 16, 14, R_, 11, R_, 9, R_,
   13, R_, 15, R_, 13, R_, 10, R_, 13, R_, R_, 15, 17, R_, 15, R_ };
static const s8 LEAD4[64] = {
   R_, 7, R_, 9, R_, 11, R_, 9, 7, R_, R_, 9, 11, R_, R_, R_,
   R_, 6, R_, 8, R_, 10, R_, 8, 6, R_, R_, 8, 10, R_, R_, R_,
   R_, 10, R_, 12, R_, 14, R_, 12, 10, R_, R_, 12, 14, R_, R_, R_,
   R_, 7, R_, 9, R_, 11, R_, 14, 13, R_, 11, R_, 9, R_, 7, R_ };

const TrackDef kTracks[NUM_TRACKS] = {
   { "MUFFIN THEME", 118, 48, SC_MAJOR, { 0, 4, 5, 3 },
     { 0x8888, 0x8888, 0x8888, 0x8A88 }, { 0x0808, 0x0808, 0x0808, 0x0A0A }, { 0xAAAA, 0xAAAA, 0xAAAA, 0xAEAE },
     { 0xA8A8, 0xA8A8, 0xA8A8, 0xA9A9 }, { 0xAAAA, 0xAAAA, 0xAAAA, 0xAAAA }, { 0, 2, 4, 2 }, LEAD0, 0.25f, 0.125f },
   { "HORIZON DRIVE", 96, 45, SC_MINOR, { 0, 5, 2, 6 },
     { 0x8010, 0x8210, 0x8010, 0x8290 }, { 0x0808, 0x0808, 0x0808, 0x0808 }, { 0xAAAA, 0xAAAA, 0xAAAA, 0xAAAB },
     { 0x9292, 0x9292, 0x9292, 0x9296 }, { 0x5555, 0x5555, 0x5555, 0x5557 }, { 0, 4, 7, 4 }, LEAD1, 0.5f, 0.25f },
   { "STARFALL", 132, 50, SC_MAJOR, { 0, 3, 4, 0 },
     { 0x8888, 0x8888, 0x8888, 0x888A }, { 0x0808, 0x0808, 0x0808, 0x080B }, { 0xAAAA, 0xAAAA, 0xAAAA, 0xAAAA },
     { 0x8888, 0x8888, 0x8888, 0x888C }, { 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF }, { 0, 2, 4, 7 }, LEAD2, 0.25f, 0.125f },
   { "PHASE SHIFT", 140, 52, SC_DORIAN, { 0, 3, 0, 6 },
     { 0x9494, 0x9494, 0x9494, 0x94D4 }, { 0x0808, 0x0808, 0x0808, 0x0A0B }, { 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF },
     { 0xB6B6, 0xB6B6, 0xB6B6, 0xB6B7 }, { 0xEEEE, 0xEEEE, 0xEEEE, 0xEEEE }, { 0, 4, 2, 7 }, LEAD3, 0.125f, 0.25f },
   { "LAB RATS", 108, 43, SC_MIXO, { 0, 6, 3, 0 },
     { 0x8420, 0x8420, 0x8420, 0x8424 }, { 0x0808, 0x0808, 0x0808, 0x0A0A }, { 0xAAAA, 0xAAAA, 0xAAAA, 0xAAAA },
     { 0xA4A4, 0xA4A4, 0xA4A4, 0xA4A5 }, { 0x4242, 0x4242, 0x4242, 0x4244 }, { 0, 2, 4, 2 }, LEAD4, 0.5f, 0.25f },
};


static int deg_semi(const u8 *sc, int d)
{
   int oct = d >= 0 ? d / 7 : -((-d + 6) / 7);
   int idx = d - oct * 7;
   return sc[idx] + 12 * oct;
}

static float midi_freq(int m) { return 440.0f * m_exp2((float)(m - 69) / 12.0f); }

typedef struct
{
   int type, active, life, age, ch;
   float ph, freq, env, dec, vol, duty, prev;
} V;
enum { VT_PULSE, VT_TRI, VT_KICK, VT_SNARE, VT_HAT };

static void voice_on(V *vs, int type, float freq, float vol, float dec, int life, float duty, int ch)
{
   int pick = 0;
   float low = 1e9f;
   for (int i = 0; i < NV; i++)
   {
      if (!vs[i].active) { pick = i; break; }
      if (vs[i].env < low) { low = vs[i].env; pick = i; }
   }
   V *v = &vs[pick];
   v->type = type; v->active = 1; v->life = life; v->age = 0; v->ch = ch;
   v->ph = 0.0f; v->freq = freq; v->env = 1.0f; v->dec = dec; v->vol = vol; v->duty = duty; v->prev = 0.0f;
}

void synth_render_track(int ti, Rendered *rt)
{
   const TrackDef *td = &kTracks[ti];
   int step_len = (int)((float)RATE * 60.0f / (float)td->bpm / 4.0f);
   int total = step_len * STEPS;
   float *dry = (float *)calloc((size_t)total, sizeof(float));
   float *wet = (float *)calloc((size_t)total, sizeof(float));
   s16 *pcm = (s16 *)memalign(32, (size_t)total * 2);
   if (!dry || !wet || !pcm) { free(dry); free(wet); free(pcm); return; }

   V vs[NV];
   memset(vs, 0, sizeof(vs));
   u32 nz = 0x9E3779B9u + (u32)ti * 77u;
   int pos = 0;

   for (int step = 0; step < STEPS; step++)
   {
      int bar = step >> 4, s = step & 15;
      u16 bit = (u16)(0x8000u >> s);
      int chord = td->chords[bar];
      u8 ev = 0;
      if (td->kick[bar] & bit) { voice_on(vs, VT_KICK, 0, 0.95f, 0.99930f, 0, 0, 0); ev |= EV_KICK; }
      if (td->snare[bar] & bit) { voice_on(vs, VT_SNARE, 0, 0.55f, 0.99950f, 0, 0, 0); ev |= EV_SNARE; }
      if (td->hat[bar] & bit)
      {
         voice_on(vs, VT_HAT, 0, (s & 3) == 2 ? 0.30f : 0.18f, 0.99800f, 0, 0, 0);
         ev |= EV_HAT;
      }
      if (td->bass[bar] & bit)
      {
         int semi = deg_semi(td->scale, chord) + ((s & 7) == 6 ? 12 : 0);
         voice_on(vs, VT_TRI, midi_freq(td->root + semi), 0.50f, 0.99985f, step_len * 2, 0.5f, 0);
         ev |= EV_BASS;
      }
      if (td->arp[bar] & bit)
      {
         int d = chord + td->arpseq[(step >> 0) & 3];
         voice_on(vs, VT_PULSE, midi_freq(td->root + 24 + deg_semi(td->scale, d)), 0.13f, 0.99950f,
                  step_len * 3 / 4, td->arp_duty, 2);
         ev |= EV_ARP;
      }
      rt->lead_semi[step] = -128;
      if (td->lead[step] != R_)
      {
         int run = 1;
         while (run < 4 && step + run < STEPS && td->lead[step + run] == R_) run++;
         int semi = deg_semi(td->scale, td->lead[step]);
         voice_on(vs, VT_PULSE, midi_freq(td->root + 12 + semi), 0.20f, 0.99997f, run * step_len * 9 / 10,
                  td->lead_duty, 1);
         rt->lead_semi[step] = (s8)(12 + semi);
         ev |= EV_LEAD;
      }
      rt->ev[step] = ev;

      for (int n = 0; n < step_len; n++)
      {
         float d = 0.0f, w = 0.0f;
         for (int i = 0; i < NV; i++)
         {
            V *v = &vs[i];
            if (!v->active) continue;
            float o;
            switch (v->type)
            {
            case VT_PULSE:
            {
               float f = v->freq;
               if (v->ch == 1 && v->age > 2400) f *= 1.0f + 0.004f * m_sin((float)v->age * 0.0009f);
               v->ph += f * (1.0f / (float)RATE);
               if (v->ph >= 1.0f) v->ph -= 1.0f;
               o = (v->ph < v->duty ? 1.0f : -1.0f);
               break;
            }
            case VT_TRI:
            {
               v->ph += v->freq * (1.0f / (float)RATE);
               if (v->ph >= 1.0f) v->ph -= 1.0f;
               o = (v->ph < 0.5f ? 4.0f * v->ph - 1.0f : 3.0f - 4.0f * v->ph);
               o += (v->ph < 0.5f ? 0.18f : -0.18f);
               break;
            }
            case VT_KICK:
               v->ph += (42.0f + 140.0f * v->env * v->env) * (1.0f / (float)RATE);
               o = m_sin(v->ph * TAU_F) * 1.1f;
               break;
            case VT_SNARE:
            {
               float nzv = (float)(rnd_r(&nz) >> 9) * (1.0f / 4194304.0f) - 1.0f;
               v->ph += 190.0f * (1.0f / (float)RATE);
               if (v->ph >= 1.0f) v->ph -= 1.0f;
               float tri = (v->ph < 0.5f ? 4.0f * v->ph - 1.0f : 3.0f - 4.0f * v->ph);
               o = nzv * 0.8f + tri * v->env * 0.5f;
               break;
            }
            default:
            {
               float nzv = (float)(rnd_r(&nz) >> 9) * (1.0f / 4194304.0f) - 1.0f;
               o = nzv - v->prev;
               v->prev = nzv;
               break;
            }
            }
            o *= v->env * v->vol;
            if (v->life > 0) v->life--; else v->env *= 0.985f;
            v->env *= v->dec;
            v->age++;
            if (v->env < 0.003f) v->active = 0;
            if (v->ch) w += o;
            d += o;
         }
         dry[pos] = d;
         wet[pos] = w;
         pos++;
      }
   }

   // Dotted-eighth echo on lead and arp, wrapped so the loop stays seamless.
   int d1 = step_len * 3;
   for (int i = 0; i < total; i++)
   {
      float x = dry[i] + 0.30f * wet[(i + total - d1) % total] + 0.14f * wet[(i + total - 2 * d1) % total];
      x *= 1.5f;
      x = x / (1.0f + m_abs(x));
      pcm[i] = (s16)(x * 31000.0f);
   }
   free(dry);
   free(wet);

   rt->len = total;
   rt->step_len = step_len;
   rt->pcm = pcm;
   __sync_synchronize();
   rt->ready = 1;
}

