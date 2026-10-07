// Offline renderer for the showcase soundtrack. MPL-2.0, original code.
//
// Links the same synth core the RPX uses (source/audio_synth.c: sequencer tables + software
// synthesiser, plus source/util.c for the shared math), so the files match what the RPX plays.
// Each track is the RPX's 64-step loop, played twice, resampled from the synth's 24 kHz mono to
// 44.1 kHz stereo (Catmull-Rom over the wrapped loop) and written as 16-bit WAV. The CI job
// encodes the WAVs to MP3 and M4A.
//
//   cc -O2 -I source tools/render_showcase_music.c source/audio_synth.c source/util.c -o render
//   ./render OUTDIR      writes OUTDIR/muffinemu-showcase-NN-slug.wav and OUTDIR/tracks.tsv
#include "audio_synth.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define OUT_RATE 44100
#define REPEATS 2

static void put16(FILE *f, unsigned v) { fputc(v & 255, f); fputc((v >> 8) & 255, f); }
static void put32(FILE *f, unsigned v) { put16(f, v & 0xFFFF); put16(f, v >> 16); }

static float tap(const s16 *p, int len, int i)
{
   i %= len;
   if (i < 0) i += len;
   return (float)p[i] * (1.0f / 32768.0f);
}

static void slugify(const char *name, char *out, size_t n)
{
   size_t o = 0;
   for (const char *c = name; *c && o + 1 < n; c++)
   {
      char ch = *c;
      if (ch >= 'A' && ch <= 'Z') ch = (char)(ch - 'A' + 'a');
      if ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9')) out[o++] = ch;
      else if (o && out[o - 1] != '-') out[o++] = '-';
   }
   while (o && out[o - 1] == '-') o--;
   out[o] = 0;
}

int main(int argc, char **argv)
{
   if (argc < 2) { fprintf(stderr, "usage: %s OUTDIR\n", argv[0]); return 2; }
   util_init();
   char path[1024], slug[64], tsv[1024];
   snprintf(tsv, sizeof(tsv), "%s/tracks.tsv", argv[1]);
   FILE *tf = fopen(tsv, "w");
   if (!tf) { perror(tsv); return 1; }

   for (int t = 0; t < NUM_TRACKS; t++)
   {
      Rendered r;
      memset(&r, 0, sizeof(r));
      synth_render_track(t, &r);
      if (!r.ready || !r.pcm) { fprintf(stderr, "track %d failed to render\n", t); return 1; }

      slugify(kTracks[t].name, slug, sizeof(slug));
      snprintf(path, sizeof(path), "%s/muffinemu-showcase-%02d-%s.wav", argv[1], t + 1, slug);
      FILE *f = fopen(path, "wb");
      if (!f) { perror(path); return 1; }

      long frames = (long)((double)r.len * REPEATS * OUT_RATE / RATE);
      unsigned data = (unsigned)(frames * 4);
      fwrite("RIFF", 1, 4, f); put32(f, 36 + data); fwrite("WAVEfmt ", 1, 8, f);
      put32(f, 16); put16(f, 1); put16(f, 2); put32(f, OUT_RATE); put32(f, OUT_RATE * 4); put16(f, 4); put16(f, 16);
      fwrite("data", 1, 4, f); put32(f, data);

      int fade = OUT_RATE / 20;
      for (long k = 0; k < frames; k++)
      {
         double pos = (double)k * RATE / OUT_RATE;
         int i = (int)pos;
         float u = (float)(pos - i);
         float p0 = tap(r.pcm, r.len, i - 1), p1 = tap(r.pcm, r.len, i);
         float p2 = tap(r.pcm, r.len, i + 1), p3 = tap(r.pcm, r.len, i + 2);
         float v = p1 + 0.5f * u * (p2 - p0 + u * (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3 + u * (3.0f * (p1 - p2) + p3 - p0)));
         if (k >= frames - fade) v *= (float)(frames - k) / (float)fade;
         if (v > 1.0f) v = 1.0f;
         if (v < -1.0f) v = -1.0f;
         int s = (int)(v * 32767.0f);
         put16(f, (unsigned)s & 0xFFFF);
         put16(f, (unsigned)s & 0xFFFF);
      }
      fclose(f);
      fprintf(tf, "%d\t%s\t%s\t%d\n", t + 1, slug, kTracks[t].name, kTracks[t].bpm);
      printf("rendered %s (%ld frames)\n", path, frames);
      free(r.pcm);
   }
   fclose(tf);
   return 0;
}
