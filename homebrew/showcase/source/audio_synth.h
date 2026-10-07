// Showcase soundtrack synth core: the sequencer data and the software synthesiser, with no wut/AX
// dependency. Shared by audio.c (the RPX) and tools/render_showcase_music.c (offline file render),
// so the exported music is the same code and data the RPX plays.
#ifndef SC_AUDIO_SYNTH_H
#define SC_AUDIO_SYNTH_H
#include "showcase.h"

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

typedef struct
{
   s16 *pcm;
   int len, step_len;
   volatile int ready;
   u8 ev[STEPS];
   s8 lead_semi[STEPS];     // -128 = rest
} Rendered;

extern const TrackDef kTracks[NUM_TRACKS];

// Renders one 64-step loop into rt (mono PCM16 at RATE, memalign'd; caller owns rt->pcm).
// rt->ready is set last. On allocation failure rt is left untouched.
void synth_render_track(int ti, Rendered *rt);

#endif
