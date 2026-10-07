// Music and blips: synthesizes the song on a worker thread at boot, then plays each
// channel on its own AX voice (looping 16-bit PCM). Visuals read g_audio, which is
// derived from the playback position, so every scene can react to the music.
#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "synth.h"

#define SPECTRUM_BANDS 24

typedef struct
{
   bool ready;          // all four channels are synthesized
   bool playing;        // AX voices are running
   bool axOk;           // AX initialised and voices acquired
   bool clockFallback;  // position comes from the wall clock, not the voices
   int synthPct;        // 0..100 across the whole song
   bool muted;          // master mute
   bool chMute[CH_COUNT];
   float pos;           // seconds into the loop
   float beat;          // 1.0 on the beat, decaying
   float beatPhase;     // 0..1 within the beat
   int bar;             // 0..SONG_BARS-1
   float level[CH_COUNT];
   float master;        // loudest channel level
} Audio;

extern Audio g_audio;

bool audio_init(void);
void audio_update(float dt);
void audio_shutdown(void);
void audio_sfx(int id);                 // 0 tick, 1 select, 2 back
void audio_set_muted(bool muted);
void audio_toggle_channel(int ch);
const int16_t *audio_samples(int ch);   // NULL until ready
uint32_t audio_sample_index(void);
void audio_spectrum(float *bands, int n);
