// See audio.h.

#include "audio.h"
#include "gfx.h"

#include <coreinit/cache.h>
#include <coreinit/debug.h>
#include <coreinit/thread.h>
#include <coreinit/time.h>
#include <sndcore2/core.h>
#include <sndcore2/device.h>
#include <sndcore2/voice.h>

#include <malloc.h>
#include <math.h>
#include <string.h>

Audio g_audio;

#define SYNTH_STACK (0x20000)

static int16_t *sCh[CH_COUNT];
static int16_t *sSfx;
static float *sScratch;
static volatile int sProgress[CH_COUNT];
static volatile int sDone;           // channels finished
static volatile bool sReady;
static OSThread *sThread;
static uint8_t *sStack;

static AXVoice *sVoice[CH_COUNT];
static AXVoice *sSfxVoice;
static bool sAxInit;
static bool sStarted;
static OSTime sStartTime;
static uint32_t sLastOffset;
static int sStallFrames;
static float sSmooth[CH_COUNT];

static int synth_entry(int argc, const char **argv)
{
   (void)argc;
   (void)argv;
   for (int c = 0; c < CH_COUNT; c++) {
      synth_channel(c, sCh[c], sScratch, &sProgress[c]);
      DCFlushRange(sCh[c], sizeof(int16_t) * SONG_SAMPLES);
      sDone = c + 1;
   }
   __sync_synchronize();
   sReady = true;
   return 0;
}

static void mix_for(int ch, uint16_t *l, uint16_t *r)
{
   switch (ch) {
   case CH_LEAD:  *l = 0x7000; *r = 0x4800; break;
   case CH_ARP:   *l = 0x4800; *r = 0x7000; break;
   case CH_BASS:  *l = 0x6800; *r = 0x6800; break;
   default:       *l = 0x6000; *r = 0x6000; break;
   }
}

static void setup_voice_common(AXVoice *v, uint16_t l, uint16_t r)
{
   AXSetVoiceType(v, 0);
   AXVoiceVeData ve = {0x8000, 0};
   AXSetVoiceVe(v, &ve);

   // AX takes one mix entry per output channel; 0 and 1 are front left and right.
   AXVoiceDeviceMixData mix[6];
   memset(mix, 0, sizeof(mix));
   mix[0].bus[0].volume = l;
   mix[1].bus[0].volume = r;
   AXSetVoiceDeviceMix(v, AX_DEVICE_TYPE_DRC, 0, mix);
   AXSetVoiceDeviceMix(v, AX_DEVICE_TYPE_TV, 0, mix);

   float ratio = (float)SONG_RATE / (float)AXGetInputSamplesPerSec();
   AXVoiceSrc src;
   memset(&src, 0, sizeof(src));
   src.ratio = (uint32_t)(65536.0f * ratio);
   AXSetVoiceSrcType(v, AX_VOICE_SRC_TYPE_LINEAR);
   AXSetVoiceSrc(v, &src);
   AXSetVoiceSrcRatio(v, ratio);
}

bool audio_init(void)
{
   memset(&g_audio, 0, sizeof(g_audio));
   g_audio.master = 0.0f;

   for (int c = 0; c < CH_COUNT; c++) {
      sCh[c] = (int16_t *)memalign(64, sizeof(int16_t) * SONG_SAMPLES);
      if (!sCh[c]) return false;
      memset(sCh[c], 0, sizeof(int16_t) * SONG_SAMPLES);
   }
   sSfx = (int16_t *)memalign(64, sizeof(int16_t) * SFX_COUNT * SFX_SAMPLES);
   sScratch = (float *)memalign(64, sizeof(float) * SONG_SAMPLES);
   sStack = (uint8_t *)memalign(16, SYNTH_STACK);
   sThread = (OSThread *)memalign(16, sizeof(OSThread));
   if (!sSfx || !sScratch || !sStack || !sThread) return false;

   synth_sfx(sSfx);
   DCFlushRange(sSfx, sizeof(int16_t) * SFX_COUNT * SFX_SAMPLES);

   // the long synthesis runs on core 2 so the first frames are not held up
   if (!OSCreateThread(sThread, synth_entry, 0, NULL, sStack + SYNTH_STACK, SYNTH_STACK, 20,
                       OS_THREAD_ATTRIB_AFFINITY_CPU2)) {
      OSReport("showcase: synth thread create failed\n");
      return false;
   }
   OSSetThreadName(sThread, "showcase synth");
   OSResumeThread(sThread);

   AXInit();
   sAxInit = AXIsInit() != 0;
   if (sAxInit) {
      sSfxVoice = AXAcquireVoice(24, NULL, NULL);
      if (sSfxVoice) {
         AXVoiceBegin(sSfxVoice);
         setup_voice_common(sSfxVoice, 0x6000, 0x6000);
         AXVoiceOffsets o;
         memset(&o, 0, sizeof(o));
         o.dataType = AX_VOICE_FORMAT_LPCM16;
         o.loopingEnabled = AX_VOICE_LOOP_DISABLED;
         o.endOffset = SFX_SAMPLES - 1;
         o.currentOffset = SFX_SAMPLES - 1;
         o.data = sSfx;
         AXSetVoiceOffsets(sSfxVoice, &o);
         AXSetVoiceState(sSfxVoice, AX_VOICE_STATE_STOPPED);
         AXVoiceEnd(sSfxVoice);
      }
   }
   OSReport("showcase: audio init (ax=%d sfxVoice=%d)\n", (int)sAxInit, sSfxVoice != NULL);
   return true;
}

static void push_volumes(void)
{
   for (int c = 0; c < CH_COUNT; c++) {
      if (!sVoice[c]) continue;
      AXVoiceVeData ve = {(uint16_t)((g_audio.muted || g_audio.chMute[c]) ? 0 : 0x8000), 0};
      AXVoiceBegin(sVoice[c]);
      AXSetVoiceVe(sVoice[c], &ve);
      AXVoiceEnd(sVoice[c]);
   }
}

static void start_music(void)
{
   sStarted = true;
   g_audio.playing = true;
   sStartTime = OSGetTime();
   if (!sAxInit) {
      g_audio.clockFallback = true;
      return;
   }
   for (int c = 0; c < CH_COUNT; c++) {
      sVoice[c] = AXAcquireVoice(25, NULL, NULL);
      if (!sVoice[c]) {
         OSReport("showcase: AXAcquireVoice failed for channel %d\n", c);
      }
   }
   // configure all, then start together so the four loops stay in phase
   for (int c = 0; c < CH_COUNT; c++) {
      if (!sVoice[c]) continue;
      uint16_t l, r;
      mix_for(c, &l, &r);
      AXVoiceBegin(sVoice[c]);
      setup_voice_common(sVoice[c], l, r);
      AXVoiceOffsets o;
      memset(&o, 0, sizeof(o));
      o.dataType = AX_VOICE_FORMAT_LPCM16;
      o.loopingEnabled = AX_VOICE_LOOP_ENABLED;
      o.loopOffset = 0;
      o.endOffset = SONG_SAMPLES - 1;
      o.currentOffset = 0;
      o.data = sCh[c];
      AXSetVoiceOffsets(sVoice[c], &o);
      AXVoiceEnd(sVoice[c]);
   }
   for (int c = 0; c < CH_COUNT; c++) {
      if (!sVoice[c]) continue;
      AXVoiceBegin(sVoice[c]);
      AXSetVoiceState(sVoice[c], AX_VOICE_STATE_PLAYING);
      AXVoiceEnd(sVoice[c]);
   }
   g_audio.axOk = sVoice[0] != NULL;
   if (!g_audio.axOk) g_audio.clockFallback = true;
   push_volumes();
   OSReport("showcase: music started (axOk=%d)\n", (int)g_audio.axOk);
}

uint32_t audio_sample_index(void)
{
   if (!g_audio.playing) return 0;
   if (!g_audio.clockFallback && sVoice[0]) {
      AXVoiceOffsets o;
      AXGetVoiceOffsets(sVoice[0], &o);
      return o.currentOffset % SONG_SAMPLES;
   }
   double sec = (double)(OSGetTime() - sStartTime) / (double)OSTimerClockSpeed;
   uint64_t idx = (uint64_t)(sec * SONG_RATE);
   return (uint32_t)(idx % SONG_SAMPLES);
}

static float window_level(const int16_t *buf, uint32_t idx, int n)
{
   float sum = 0.0f;
   for (int i = 0; i < n; i++) {
      int p = (int)idx - i;
      if (p < 0) p += SONG_SAMPLES;
      int v = buf[p];
      sum += (float)(v < 0 ? -v : v);
   }
   return sum / (float)n;
}

void audio_update(float dt)
{
   g_audio.synthPct = sReady ? 100 : (sDone * 100 + (sDone < CH_COUNT ? sProgress[sDone] : 0)) / CH_COUNT;
   if (!g_audio.ready && sReady) {
      __sync_synchronize();
      g_audio.ready = true;
      start_music();
   }
   if (!g_audio.playing) return;

   uint32_t idx = audio_sample_index();

   // if the voice position stops advancing the visuals fall back to the wall clock
   if (!g_audio.clockFallback) {
      if (idx == sLastOffset) {
         if (++sStallFrames > 45) {
            g_audio.clockFallback = true;
            OSReport("showcase: AX position stalled, using the wall clock for visuals\n");
         }
      } else {
         sStallFrames = 0;
      }
      sLastOffset = idx;
   }

   g_audio.pos = (float)idx / (float)SONG_RATE;
   float beats = g_audio.pos * (float)SONG_BPM / 60.0f;
   g_audio.beatPhase = beats - floorf(beats);
   g_audio.beat = expf(-g_audio.beatPhase * 4.5f);
   g_audio.bar = synth_bar_at(idx);

   static const float kRef[CH_COUNT] = {2600.0f, 1700.0f, 4200.0f, 800.0f};
   float top = 0.0f;
   for (int c = 0; c < CH_COUNT; c++) {
      float lv = window_level(sCh[c], idx, 300) / kRef[c];
      if (lv > 1.0f) lv = 1.0f;
      if (g_audio.chMute[c] || g_audio.muted) lv *= 0.0f;
      sSmooth[c] = lv > sSmooth[c] ? lv : sSmooth[c] - dt * 3.2f;
      if (sSmooth[c] < 0.0f) sSmooth[c] = 0.0f;
      g_audio.level[c] = sSmooth[c];
      if (sSmooth[c] > top) top = sSmooth[c];
   }
   g_audio.master = top;
}

void audio_sfx(int id)
{
   if (!sSfxVoice || id < 0 || id >= SFX_COUNT || g_audio.muted) return;
   AXVoiceBegin(sSfxVoice);
   AXSetVoiceState(sSfxVoice, AX_VOICE_STATE_STOPPED);
   AXVoiceOffsets o;
   memset(&o, 0, sizeof(o));
   o.dataType = AX_VOICE_FORMAT_LPCM16;
   o.loopingEnabled = AX_VOICE_LOOP_DISABLED;
   o.loopOffset = (uint32_t)id * SFX_SAMPLES;
   o.endOffset = (uint32_t)(id + 1) * SFX_SAMPLES - 1;
   o.currentOffset = (uint32_t)id * SFX_SAMPLES;
   o.data = sSfx;
   AXSetVoiceOffsets(sSfxVoice, &o);
   AXSetVoiceState(sSfxVoice, AX_VOICE_STATE_PLAYING);
   AXVoiceEnd(sSfxVoice);
}

void audio_set_muted(bool muted)
{
   g_audio.muted = muted;
   push_volumes();
}

void audio_toggle_channel(int ch)
{
   if (ch < 0 || ch >= CH_COUNT) return;
   g_audio.chMute[ch] = !g_audio.chMute[ch];
   push_volumes();
}

const int16_t *audio_samples(int ch)
{
   return (g_audio.ready && ch >= 0 && ch < CH_COUNT) ? sCh[ch] : NULL;
}

// Goertzel filter bank over the last 600 samples of the (unmuted) mix.
void audio_spectrum(float *bands, int n)
{
   enum { WIN = 600 };
   static float w[WIN];
   if (!g_audio.ready || !g_audio.playing || g_audio.muted) {
      for (int i = 0; i < n; i++) bands[i] = 0.0f;
      return;
   }
   uint32_t idx = audio_sample_index();
   for (int i = 0; i < WIN; i++) {
      int p = (int)idx - (WIN - 1 - i);
      if (p < 0) p += SONG_SAMPLES;
      float v = 0.0f;
      for (int c = 0; c < CH_COUNT; c++) {
         if (!g_audio.chMute[c]) v += (float)sCh[c][p];
      }
      float hann = 0.5f - 0.5f * fcos(6.28318f * (float)i / (float)(WIN - 1));
      w[i] = v * (1.0f / 32768.0f) * hann;
   }
   for (int k = 0; k < n; k++) {
      float f = 70.0f * powf(9000.0f / 70.0f, (float)k / (float)(n - 1));
      float coeff = 2.0f * fcos(6.28318f * f / (float)SONG_RATE);
      float s1 = 0.0f, s2 = 0.0f;
      for (int i = 0; i < WIN; i++) {
         float s0 = w[i] + coeff * s1 - s2;
         s2 = s1;
         s1 = s0;
      }
      float power = s1 * s1 + s2 * s2 - coeff * s1 * s2;
      float mag = sqrtf(power > 0.0f ? power : 0.0f) * (2.0f / (float)WIN);
      float lvl = sqrtf(mag) * 1.6f;   // compress: bass would dominate a linear scale
      bands[k] = lvl > 1.0f ? 1.0f : lvl;
   }
}

void audio_shutdown(void)
{
   for (int c = 0; c < CH_COUNT; c++) {
      if (sVoice[c]) {
         AXVoiceBegin(sVoice[c]);
         AXSetVoiceState(sVoice[c], AX_VOICE_STATE_STOPPED);
         AXVoiceEnd(sVoice[c]);
         AXFreeVoice(sVoice[c]);
         sVoice[c] = NULL;
      }
   }
   if (sSfxVoice) {
      AXFreeVoice(sSfxVoice);
      sSfxVoice = NULL;
   }
   if (sThread) {
      int result;
      OSJoinThread(sThread, &result);
   }
   if (sAxInit) AXQuit();
}
