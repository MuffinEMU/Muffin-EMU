// Procedural chiptune: four looping channels and three UI blips, synthesized from
// code. Pure C with no console APIs, so the same file also builds on a PC for testing.
#pragma once

#include <stdint.h>

#define SONG_RATE     24000
#define SONG_BPM      132
#define SONG_BARS     16
#define SONG_SLOTS    (SONG_BARS * 8)   // eighth notes
// exactly SONG_SLOTS eighth notes at SONG_BPM, rounded up
#define SONG_SAMPLES  ((SONG_SLOTS * SONG_RATE * 30 + SONG_BPM - 1) / SONG_BPM)

#define CH_LEAD  0
#define CH_ARP   1
#define CH_BASS  2
#define CH_DRUMS 3
#define CH_COUNT 4

#define SFX_COUNT   3
#define SFX_SAMPLES 4800   // 0.2 s each

// Render one channel into out[SONG_SAMPLES]. `scratch` is SONG_SAMPLES floats of
// working space. progress, if not NULL, is updated 0..100 as it goes.
void synth_channel(int ch, int16_t *out, float *scratch, volatile int *progress);

// Render the UI blips back to back into out[SFX_COUNT * SFX_SAMPLES].
void synth_sfx(int16_t *out);

// Which chord/bar is playing at a sample index (for visuals).
int synth_bar_at(uint32_t sample);

// Chord name for a bar (upper case, for the UI).
const char *synth_chord_name(int bar);
