// Procedural soundtrack. A small step sequencer (drums, bass, arpeggio, lead) drives a software
// synthesiser that renders each 64-step loop into a PCM16 buffer on a background thread (core 2).
// The finished loop is handed to an sndcore2 (AX) voice as a looping LPCM16 source, so the audio
// path exercised is AXInit, AXAcquireVoice, AXSetVoiceOffsets/Src/Ve/DeviceMix and the AX mixer.
// No samples, no external data: every sound is computed here.
#include "showcase.h"

#include <coreinit/thread.h>
#include <malloc.h>
#include <sndcore2/core.h>
#include <sndcore2/device.h>
#include <sndcore2/voice.h>
#include <stdlib.h>
#include <string.h>

#define RATE 24000
#define STEPS 64
#define R_ 99
#define NV 14

typedef struct
{
   const char *name;
   int bpm;
   int root;                 // MIDI note of scale degree 0 for bass/arp (lead is one octave above)
   const u8 *scale;
   u8 chords[4];             // chord root as a scale degree, per bar
   u16 kick[4], snare[4], hat[4], bass[4], arp[4];
   s8 arpseq[4];
   const s8 *lead;           // 64 scale degrees, R_ = rest
   float lead_duty, arp_duty;
} TrackDef;

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

static const TrackDef kTracks[NUM_TRACKS] = {
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

typedef struct
{
   s16 *pcm;
   int len, step_len;
   volatile int ready;
   u8 ev[STEPS];
   s8 lead_semi[STEPS];     // -128 = rest
} Rendered;

static Rendered s_tr[NUM_TRACKS];
static volatile int s_progress;
static AXVoice *s_voice;
static int s_cur = -1, s_want = 0, s_muted, s_vol_i = -1;
static float s_volume = 0.8f, s_vol = 0.0f;
static OSThread s_thread __attribute__((aligned(16)));
static u8 s_stack[0x20000] __attribute__((aligned(16)));
static volatile int s_quit;

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

static void render_track(int ti)
{
   const TrackDef *td = &kTracks[ti];
   Rendered *rt = &s_tr[ti];
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

static int render_main(int argc, const char **argv)
{
   (void)argc; (void)argv;
   for (int i = 0; i < NUM_TRACKS && !s_quit; i++)
   {
      render_track(i);
      s_progress = (i + 1) * 100 / NUM_TRACKS;
   }
   return 0;
}

void audio_init(void)
{
   AXInit();
   s_voice = AXAcquireVoice(25, NULL, NULL);
   if (s_voice)
   {
      AXVoiceBegin(s_voice);
      AXSetVoiceType(s_voice, 0);
      AXSetVoiceSrcType(s_voice, AX_VOICE_SRC_TYPE_LINEAR);
      AXSetVoiceSrcRatio(s_voice, (float)RATE / 48000.0f);
      AXVoiceVeData ve;
      ve.volume = 0; ve.delta = 0;
      AXSetVoiceVe(s_voice, &ve);
      AXVoiceDeviceMixData mix[6];
      memset(mix, 0, sizeof(mix));
      mix[0].bus[0].volume = 0x8000;
      mix[1].bus[0].volume = 0x8000;
      AXSetVoiceDeviceMix(s_voice, AX_DEVICE_TYPE_TV, 0, mix);
      AXSetVoiceDeviceMix(s_voice, AX_DEVICE_TYPE_DRC, 0, mix);
      AXVoiceEnd(s_voice);
      s_vol_i = 0;
   }
   OSCreateThread(&s_thread, render_main, 0, NULL, s_stack + sizeof(s_stack), sizeof(s_stack), 18,
                  OS_THREAD_ATTRIB_AFFINITY_CPU2);
   OSSetThreadName(&s_thread, "showcase audio render");
   OSResumeThread(&s_thread);
}

void audio_shutdown(void)
{
   s_quit = 1;
   int rc;
   OSJoinThread(&s_thread, &rc);
   if (s_voice)
   {
      AXVoiceBegin(s_voice);
      AXSetVoiceState(s_voice, AX_VOICE_STATE_STOPPED);
      AXVoiceEnd(s_voice);
      AXFreeVoice(s_voice);
      s_voice = NULL;
   }
   AXQuit();
}

void audio_update(float dt)
{
   if (!s_voice) return;
   int want = s_want;
   int swap = (want != s_cur && s_tr[want].ready);
   float target = (s_muted || swap) ? 0.0f : s_volume;
   float k = dt * 9.0f;
   if (k > 1.0f) k = 1.0f;
   s_vol += (target - s_vol) * k;

   if (swap && s_vol < 0.04f)
   {
      Rendered *r = &s_tr[want];
      AXVoiceBegin(s_voice);
      AXSetVoiceState(s_voice, AX_VOICE_STATE_STOPPED);
      AXVoiceOffsets off;
      memset(&off, 0, sizeof(off));
      off.dataType = AX_VOICE_FORMAT_LPCM16;
      off.loopingEnabled = AX_VOICE_LOOP_ENABLED;
      off.loopOffset = 0;
      off.endOffset = (u32)(r->len - 1);
      off.currentOffset = 0;
      off.data = r->pcm;
      AXSetVoiceOffsets(s_voice, &off);
      AXSetVoiceState(s_voice, AX_VOICE_STATE_PLAYING);
      AXVoiceEnd(s_voice);
      s_cur = want;
   }

   int vi = (int)(s_vol * 0x7000);
   if (vi != s_vol_i)
   {
      AXVoiceVeData ve;
      ve.volume = (u16)vi; ve.delta = 0;
      AXVoiceBegin(s_voice);
      AXSetVoiceVe(s_voice, &ve);
      AXVoiceEnd(s_voice);
      s_vol_i = vi;
   }
}

void audio_set_track(int t) { if (t >= 0 && t < NUM_TRACKS) s_want = t; }
int audio_track(void) { return s_want; }
int audio_ready(int t) { return s_tr[t].ready; }
int audio_progress(void) { return s_progress; }
void audio_set_mute(int m) { s_muted = m; }
int audio_muted(void) { return s_muted; }
void audio_set_volume(float v) { s_volume = m_clamp(v, 0.0f, 1.0f); }
float audio_volume(void) { return s_volume; }
const char *audio_track_name(int t) { return kTracks[t].name; }
int audio_track_bpm(int t) { return kTracks[t].bpm; }
u8 audio_event(int t, int step) { return s_tr[t].ready ? s_tr[t].ev[step & 63] : 0; }
int audio_lead_note(int t, int step)
{
   if (!s_tr[t].ready) return -1;
   int n = s_tr[t].lead_semi[step & 63];
   return n == -128 ? -1 : n;
}
const s16 *audio_pcm(int t, int *len)
{
   if (!s_tr[t].ready) return NULL;
   if (len) *len = s_tr[t].len;
   return s_tr[t].pcm;
}

int audio_pcm_pos(void)
{
   if (!s_voice || s_cur < 0) return -1;
   AXVoiceOffsets off;
   AXGetVoiceOffsets(s_voice, &off);
   if ((int)off.currentOffset < 0 || (int)off.currentOffset >= s_tr[s_cur].len) return -1;
   return (int)off.currentOffset;
}

static float step_pos(void)
{
   int p = audio_pcm_pos();
   if (p >= 0 && s_cur >= 0) return (float)p / (float)s_tr[s_cur].step_len;
   // No device or still rendering: run the playhead from the clock so the UI keeps moving.
   float beats = g_time * (float)kTracks[s_want].bpm / 60.0f * 4.0f;
   return beats - (float)((int)(beats / 64.0f) * 64);
}
int audio_step(void) { return ((int)step_pos()) & 63; }
float audio_step_frac(void) { float p = step_pos(); return p - (float)(int)p; }
