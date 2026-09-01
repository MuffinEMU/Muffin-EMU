// rainbow.rpx - a homebrew test rom that is impossible to confuse with a black screen.
//
// Why this exists. Every graphics test this port has run so far has been ambiguous.
// helloworld.rpx is the rom we designated, and it is a fine rom, but a black screen
// while running it means either "the emulator never drew" or "the rom drew nothing
// worth seeing", and the logs are byte-identical in both cases. v1.19's magenta empty
// frame settles half of it (magenta proves the Metal path is alive). This settles the
// other half: a rom whose entire job is to put a very large amount of very loud colour
// on the glass. If the screen goes red-orange-yellow-green-blue-indigo-violet and then
// spells something, the whole chain works - PPC execution, coreinit HLE, the OSScreen
// scanout path, Latte, Metal, and presentation. If it stays one colour, the failure is
// pinned to whatever the last thing to work was.
//
// Deliberately does NOT use ProcUI / WHBProc, unlike wut's helloworld sample. That is
// the point of it as a diagnostic, not laziness: WHBProcInit()/WHBProcIsRunning() sit
// on ProcUI, and if ProcUI is incompletely implemented here then WHBProcIsRunning()
// returns false on the first iteration, the sample exits before drawing anything, and
// the result is a black screen that looks exactly like a broken renderer. This rom
// touches nothing but coreinit and loops unconditionally, so it cannot fail that way.
// The cost is no HOME-menu exit - close the app to stop it.
//
// Uses OSScreen (coreinit) rather than GX2 on purpose too. OSScreen is what homebrew
// actually uses, it is scanned out by LatteThread_HandleOSScreen() on a path entirely
// independent of GX2SwapScanBuffers(), and it is the path with the least emulator
// surface underneath it - the shortest possible route from "PPC code ran" to "pixels".
//
// Licence: written for cemu-ios-muffin, same terms as the repo.

#include <coreinit/cache.h>
#include <coreinit/debug.h>
#include <coreinit/screen.h>
#include <coreinit/thread.h>
#include <coreinit/time.h>

#include <malloc.h>
#include <stdint.h>

// Hardware framebuffer dimensions. Only used to centre things; OSScreenPutPixelEx
// clips on its own, so being a few pixels off on a differently-sized DRC surface costs
// nothing worse than a slightly off-centre word.
#define TV_WIDTH   1280
#define TV_HEIGHT  720
#define DRC_WIDTH  854
#define DRC_HEIGHT 480

// OSScreen framebuffers are RGBX8888, so the byte order is R,G,B,unused. The low byte
// is padding rather than alpha; 0xFF is the conventional value and nothing reads it.
static uint32_t rgb(uint32_t r, uint32_t g, uint32_t b)
{
   return (r << 24) | (g << 16) | (b << 8) | 0xFFu;
}

// Hue around the full circle in 1536 steps - six 256-step sectors, one per edge of the
// RGB cube. Integer only: this rom may well be running on an interpreter with no
// recompiler and no FPU shortcuts worth relying on, and a colour wheel does not need
// floating point.
static uint32_t hue_colour(uint32_t hue)
{
   uint32_t t = hue % 256u;
   switch ((hue % 1536u) / 256u)
   {
   case 0:  return rgb(255,       t,         0);
   case 1:  return rgb(255 - t,   255,       0);
   case 2:  return rgb(0,         255,       t);
   case 3:  return rgb(0,         255 - t,   255);
   case 4:  return rgb(t,         0,         255);
   default: return rgb(255,       0,         255 - t);
   }
}

static uint32_t scale_colour(uint32_t colour, uint32_t numerator, uint32_t denominator)
{
   uint32_t r = ((colour >> 24) & 0xFFu) * numerator / denominator;
   uint32_t g = ((colour >> 16) & 0xFFu) * numerator / denominator;
   uint32_t b = ((colour >> 8) & 0xFFu) * numerator / denominator;
   return rgb(r, g, b);
}

// Pull a colour most of the way to white. This is what makes the letters read as neon
// tubing rather than as flat coloured blocks: a real neon letter is a white-hot core
// with the gas colour only at its edges and in the glow around it.
static uint32_t whiten(uint32_t colour)
{
   uint32_t r = (colour >> 24) & 0xFFu;
   uint32_t g = (colour >> 16) & 0xFFu;
   uint32_t b = (colour >> 8) & 0xFFu;
   return rgb(r + (255u - r) * 3u / 4u,
              g + (255u - g) * 3u / 4u,
              b + (255u - b) * 3u / 4u);
}

// 5x7 font, one byte per row, bit 4 leftmost. Only the nine glyphs "hello world!"
// needs. OSScreenPutFontEx has a built-in font and would have been less work, but it
// draws in a fixed colour with no way to ask for another one, which rules it out for
// the one thing this rom is for.
#define GLYPH_W 5
#define GLYPH_H 7

static const unsigned char kGlyphSpace[GLYPH_H] = { 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
static const unsigned char kGlyphH[GLYPH_H]     = { 0x10, 0x10, 0x16, 0x19, 0x11, 0x11, 0x11 };
static const unsigned char kGlyphE[GLYPH_H]     = { 0x00, 0x00, 0x0E, 0x11, 0x1F, 0x10, 0x0E };
static const unsigned char kGlyphL[GLYPH_H]     = { 0x18, 0x08, 0x08, 0x08, 0x08, 0x09, 0x06 };
static const unsigned char kGlyphO[GLYPH_H]     = { 0x00, 0x00, 0x0E, 0x11, 0x11, 0x11, 0x0E };
static const unsigned char kGlyphW[GLYPH_H]     = { 0x00, 0x00, 0x11, 0x11, 0x15, 0x15, 0x0A };
static const unsigned char kGlyphR[GLYPH_H]     = { 0x00, 0x00, 0x16, 0x19, 0x10, 0x10, 0x10 };
static const unsigned char kGlyphD[GLYPH_H]     = { 0x01, 0x01, 0x0D, 0x13, 0x11, 0x11, 0x0F };
static const unsigned char kGlyphBang[GLYPH_H]  = { 0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04 };

static const unsigned char *glyph_for(char c)
{
   switch (c)
   {
   case 'h': return kGlyphH;
   case 'e': return kGlyphE;
   case 'l': return kGlyphL;
   case 'o': return kGlyphO;
   case 'w': return kGlyphW;
   case 'r': return kGlyphR;
   case 'd': return kGlyphD;
   case '!': return kGlyphBang;
   default:  return kGlyphSpace;
   }
}

static int cell_lit(const unsigned char *glyph, int x, int y)
{
   if (x < 0 || x >= GLYPH_W || y < 0 || y >= GLYPH_H)
      return 0;
   return (glyph[y] >> (GLYPH_W - 1 - x)) & 1;
}

// Draws one glyph as neon: every lit cell becomes a scale x scale block with a
// whitened core and a coloured rim, and every unlit cell that touches a lit one becomes
// a dim block of the same colour - the glow.
//
// Every pixel is written exactly once. That matters more than it looks: each
// OSScreenPutPixelEx is a PPC->host HLE call, this build has no working recompiler yet,
// and a naive "draw it, then draw a glow over it" would double an already large per-
// frame call count for no visual gain.
static void draw_glyph(OSScreenID screen, const unsigned char *glyph,
                       int originX, int originY, int scale, uint32_t colour)
{
   uint32_t core = whiten(colour);
   uint32_t glow = scale_colour(colour, 22, 100);
   int coreInset = scale / 4;

   for (int cy = 0; cy < GLYPH_H; cy++)
   {
      for (int cx = 0; cx < GLYPH_W; cx++)
      {
         int lit = cell_lit(glyph, cx, cy);
         if (!lit)
         {
            // Glow only where the cell actually borders the letter, so the halo hugs
            // the strokes instead of filling in the counters of an 'o' or an 'e'.
            int touching = cell_lit(glyph, cx - 1, cy) || cell_lit(glyph, cx + 1, cy)
                        || cell_lit(glyph, cx, cy - 1) || cell_lit(glyph, cx, cy + 1)
                        || cell_lit(glyph, cx - 1, cy - 1) || cell_lit(glyph, cx + 1, cy - 1)
                        || cell_lit(glyph, cx - 1, cy + 1) || cell_lit(glyph, cx + 1, cy + 1);
            if (!touching)
               continue;
         }

         int baseX = originX + cx * scale;
         int baseY = originY + cy * scale;
         for (int dy = 0; dy < scale; dy++)
         {
            for (int dx = 0; dx < scale; dx++)
            {
               uint32_t pixel;
               if (!lit)
               {
                  pixel = glow;
               }
               else
               {
                  int inset = dx;
                  if (dy < inset) inset = dy;
                  if (scale - 1 - dx < inset) inset = scale - 1 - dx;
                  if (scale - 1 - dy < inset) inset = scale - 1 - dy;
                  pixel = (inset >= coreInset) ? core : colour;
               }
               OSScreenPutPixelEx(screen, baseX + dx, baseY + dy, pixel);
            }
         }
      }
   }
}

static const char *kMessage = "hello world!";
#define MESSAGE_LENGTH 12

static void draw_message(OSScreenID screen, int screenWidth, int screenHeight,
                         int scale, uint32_t baseHue)
{
   int advance = GLYPH_W * scale + scale; // one blank cell of tracking between letters
   int originX = (screenWidth - advance * MESSAGE_LENGTH) / 2;
   int originY = (screenHeight - GLYPH_H * scale) / 2;

   for (int i = 0; i < MESSAGE_LENGTH; i++)
   {
      // 128 steps of a 1536-step wheel per letter: the word spans two thirds of the
      // spectrum, so every letter is visibly a different colour rather than twelve
      // shades of the same one.
      uint32_t colour = hue_colour(baseHue + (uint32_t)i * 128u);
      draw_glyph(screen, glyph_for(kMessage[i]), originX + i * advance, originY, scale, colour);
   }
}

int main(int argc, char **argv)
{
   OSReport("rainbow.rpx: starting\n");

   OSScreenInit();

   uint32_t tvSize = OSScreenGetBufferSizeEx(SCREEN_TV);
   uint32_t drcSize = OSScreenGetBufferSizeEx(SCREEN_DRC);
   void *tvBuffer = memalign(0x100, tvSize);
   void *drcBuffer = memalign(0x100, drcSize);
   if (!tvBuffer || !drcBuffer)
   {
      OSReport("rainbow.rpx: could not allocate framebuffers (tv %u, drc %u)\n", tvSize, drcSize);
      return 1;
   }

   OSScreenSetBufferEx(SCREEN_TV, tvBuffer);
   OSScreenSetBufferEx(SCREEN_DRC, drcBuffer);
   OSScreenEnableEx(SCREEN_TV, 1);
   OSScreenEnableEx(SCREEN_DRC, 1);
   OSReport("rainbow.rpx: OSScreen up, entering flash phase\n");

   // Phase one: flash each colour of the rainbow, full screen, both displays.
   //
   // This is the cheap half and the half that should be impossible to miss. It is a
   // host-side memset per frame rather than per-pixel HLE calls, so it runs at full
   // speed even under the interpreter. If ONLY this phase works and the letters never
   // arrive, that is itself the answer: clears and presentation are fine and
   // OSScreenPutPixelEx is where it breaks.
   static const uint32_t kRainbow[] = {
      0xFF0000FFu, // red
      0xFF7F00FFu, // orange
      0xFFFF00FFu, // yellow
      0x00FF00FFu, // green
      0x0080FFFFu, // blue
      0x4B00FFFFu, // indigo
      0x9400D3FFu, // violet
   };
   const int kRainbowCount = (int)(sizeof(kRainbow) / sizeof(kRainbow[0]));

   for (int pass = 0; pass < 2; pass++)
   {
      for (int i = 0; i < kRainbowCount; i++)
      {
         // Twice per colour, because OSScreen is double buffered: one clear and flip
         // only fills the buffer being shown next, and the other one still holds the
         // previous colour. Without this the flash phase strobes between two colours
         // instead of showing one.
         for (int repeat = 0; repeat < 2; repeat++)
         {
            OSScreenClearBufferEx(SCREEN_TV, kRainbow[i]);
            OSScreenClearBufferEx(SCREEN_DRC, kRainbow[i]);
            DCFlushRange(tvBuffer, tvSize);
            DCFlushRange(drcBuffer, drcSize);
            OSScreenFlipBuffersEx(SCREEN_TV);
            OSScreenFlipBuffersEx(SCREEN_DRC);
            OSSleepTicks(OSMillisecondsToTicks(220));
         }
      }
   }

   OSReport("rainbow.rpx: flash phase done, entering neon phase\n");

   // Phase two: "hello world!" in neon, hue drifting, forever.
   //
   // No sleep in this loop on purpose. Per-pixel drawing through HLE calls is the
   // bottleneck by a wide margin on an interpreter, so the frame rate is whatever the
   // emulator can manage and adding a delay would only make a slow demo slower. A low
   // frame rate here is expected and is not a bug - it is the missing recompiler.
   uint32_t baseHue = 0;
   for (;;)
   {
      OSScreenClearBufferEx(SCREEN_TV, 0x0A0A14FFu);
      OSScreenClearBufferEx(SCREEN_DRC, 0x0A0A14FFu);

      draw_message(SCREEN_TV, TV_WIDTH, TV_HEIGHT, 8, baseHue);
      draw_message(SCREEN_DRC, DRC_WIDTH, DRC_HEIGHT, 5, baseHue);

      DCFlushRange(tvBuffer, tvSize);
      DCFlushRange(drcBuffer, drcSize);
      OSScreenFlipBuffersEx(SCREEN_TV);
      OSScreenFlipBuffersEx(SCREEN_DRC);

      baseHue = (baseHue + 24u) % 1536u;
   }

   return 0;
}
