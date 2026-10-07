// Procedural soundtrack. A small step sequencer (drums, bass, arpeggio, lead) drives a software
// synthesiser that renders each 64-step loop into a PCM16 buffer on a background thread (core 2).
// The finished loop is handed to an sndcore2 (AX) voice as a looping LPCM16 source, so the audio
// path exercised is AXInit, AXAcquireVoice, AXSetVoiceOffsets/Src/Ve/DeviceMix and the AX mixer.
// No samples, no external data: every sound is computed here.
#include "showcase.h"

#include <coreinit/thread.h>
#include <sndcore2/core.h>
#include <sndcore2/device.h>
#include <sndcore2/voice.h>
#include <stdlib.h>
#include <string.h>

#include "audio_synth.h"

static Rendered s_tr[NUM_TRACKS];
static volatile int s_progress;
static AXVoice *s_voice;
static int s_cur = -1, s_want = 0, s_muted, s_vol_i = -1;
static float s_volume = 0.8f, s_vol = 0.0f;
static OSThread s_thread __attribute__((aligned(16)));
static u8 s_stack[0x20000] __attribute__((aligned(16)));
static volatile int s_quit;

static int render_main(int argc, const char **argv)
{
   (void)argc; (void)argv;
   for (int i = 0; i < NUM_TRACKS && !s_quit; i++)
   {
      synth_render_track(i, &s_tr[i]);
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
