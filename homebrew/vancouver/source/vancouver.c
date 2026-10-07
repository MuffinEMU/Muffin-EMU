// vancouver.rpx - a very coarse, hand-made flyover map of Metro Vancouver, BC.
// A 40x30 cell grid encoded below (W water, L land, M mountain, P park), drawn flat with
// OSScreen. Loosely sketched after the real geography; not survey data.
// Map data (c) OpenStreetMap contributors, ODbL (geography used as reference only).
// Made by MuffinEMU. Licence: same terms as the repository (MPL-2.0).

#include <coreinit/cache.h>
#include <coreinit/screen.h>
#include <vpad/input.h>
#include <coreinit/thread.h>
#include <coreinit/time.h>
#include <malloc.h>
#include <stdint.h>

#define GW 40
#define GH 30

static const char kMap[GH][GW + 1] = {
   "WWWWWWWWWWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM",
   "WWWWWWWWWWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM",
   "WWWWWWWWWWWMMMMMMMMMMMMMMMMMMMMMMMMMMMMM",
   "WWWWWWWWWWWMMMMMMMMMMMMMMMMMMMMMMMMMMMMM",
   "WWWWWWWWWWWWMMMMMMMMMMMMMMMMMMMMMMMMMMMM",
   "WWWWWWWWWWWWLLMMMMMMMMMMMMMMMMMMMMMMMMMM",
   "WWWWWWWWWWWWLLLLMMMMMMMMMMMMMMMMMMMMMMMM",
   "WWWWWWWWWWWWLLLLLLLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWWWWWLLLLLLLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWLLLLL",
   "WWWWWWWWPPLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWLLLLWWLLLLLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWLLLLLWLLLLLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWWLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWWWWWLLLLLLLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWWWWWWWWWWWWWWWWWLLLLLLLLLLLLLLLL",
   "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWLLLLLLLL",
   "WWWWWWWWWWWWLLLLLLLLLLLLLLWWWWWWWWWWWWWW",
   "WWWWWWWWWWWWLLLLLLLLLLLLLLLLLWWWWWWWWWWW",
   "WWWWWWWWWWWWLLLLLLLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWWWWWWWLLLLLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWWWWWWWWLLLLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWWWWWWWWWWLLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWWWWWWWWWWWLLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWWWWWWWWWWWWLLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWWWWWWWWWWWWWLLLLLLLLLLLLLLLLLLLL",
   "WWWWWWWWWWWWWWWWWWWWWLLLLLLLLLLLLLLLLLLL",
};

typedef struct { const char *name; int cx, cy; } Place;
static const Place kPlaces[] = {
   { "VANCOUVER", 12, 12 }, { "BURNABY", 22, 12 }, { "RICHMOND", 14, 21 },
   { "SURREY", 31, 22 }, { "NORTH VANCOUVER", 17, 7 }, { "WEST VANCOUVER", 12, 5 },
   { "COQUITLAM", 33, 11 }, { "NEW WESTMINSTER", 25, 16 }, { "DELTA", 21, 26 },
   { "STANLEY PARK", 6, 9 },
};
#define NPLACES ((int)(sizeof(kPlaces) / sizeof(kPlaces[0])))

static uint32_t rgb(uint32_t r, uint32_t g, uint32_t b) { return (r << 24) | (g << 16) | (b << 8) | 0xFFu; }

// Uppercase 5x7 font, A-Z at 0..25; extras below.
static const unsigned char kFont[26][7] = {
   {0x0E,0x11,0x11,0x1F,0x11,0x11,0x11},{0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E},{0x0E,0x11,0x10,0x10,0x10,0x11,0x0E},
   {0x1E,0x11,0x11,0x11,0x11,0x11,0x1E},{0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F},{0x1F,0x10,0x10,0x1E,0x10,0x10,0x10},
   {0x0E,0x11,0x10,0x17,0x11,0x11,0x0F},{0x11,0x11,0x11,0x1F,0x11,0x11,0x11},{0x0E,0x04,0x04,0x04,0x04,0x04,0x0E},
   {0x07,0x02,0x02,0x02,0x02,0x12,0x0C},{0x11,0x12,0x14,0x18,0x14,0x12,0x11},{0x10,0x10,0x10,0x10,0x10,0x10,0x1F},
   {0x11,0x1B,0x15,0x15,0x11,0x11,0x11},{0x11,0x19,0x15,0x13,0x11,0x11,0x11},{0x0E,0x11,0x11,0x11,0x11,0x11,0x0E},
   {0x1E,0x11,0x11,0x1E,0x10,0x10,0x10},{0x0E,0x11,0x11,0x11,0x15,0x12,0x0D},{0x1E,0x11,0x11,0x1E,0x14,0x12,0x11},
   {0x0F,0x10,0x10,0x0E,0x01,0x01,0x1E},{0x1F,0x04,0x04,0x04,0x04,0x04,0x04},{0x11,0x11,0x11,0x11,0x11,0x11,0x0E},
   {0x11,0x11,0x11,0x11,0x11,0x0A,0x04},{0x11,0x11,0x11,0x15,0x15,0x15,0x0A},{0x11,0x11,0x0A,0x04,0x0A,0x11,0x11},
   {0x11,0x11,0x0A,0x04,0x04,0x04,0x04},{0x1F,0x01,0x02,0x04,0x08,0x10,0x1F},
};
static const unsigned char kLParen[7] = {0x02,0x04,0x08,0x08,0x08,0x04,0x02};
static const unsigned char kRParen[7] = {0x08,0x04,0x02,0x02,0x02,0x04,0x08};
static const unsigned char kComma[7]  = {0,0,0,0,0x06,0x04,0x08};
static const unsigned char kBlank[7]  = {0,0,0,0,0,0,0};

static const unsigned char *glyph(char c)
{
   if (c >= 'A' && c <= 'Z') return kFont[c - 'A'];
   if (c == '(') return kLParen;
   if (c == ')') return kRParen;
   if (c == ',') return kComma;
   return kBlank;
}

static void fill(OSScreenID s, int x, int y, int w, int h, uint32_t c)
{
   for (int j = 0; j < h; j++)
      for (int i = 0; i < w; i++)
         OSScreenPutPixelEx(s, x + i, y + j, c);
}

static void text(OSScreenID s, const char *t, int x, int y, int sc, uint32_t c)
{
   for (; *t; t++, x += 6 * sc)
   {
      const unsigned char *g = glyph(*t);
      for (int r = 0; r < 7; r++)
         for (int b = 0; b < 5; b++)
            if ((g[r] >> (4 - b)) & 1)
               fill(s, x + b * sc, y + r * sc, sc, sc, c);
   }
}

static int text_w(const char *t, int sc) { int n = 0; while (*t++) n++; return n * 6 * sc; }

static void label(OSScreenID s, const char *t, int x, int y, int sc)
{
   x -= text_w(t, sc) / 2;
   text(s, t, x + 1, y + 1, sc, rgb(0, 0, 0));
   text(s, t, x, y, sc, rgb(255, 255, 255));
}

static uint32_t cell_colour(int cx, int cy)
{
   if (cx < 0 || cy < 0 || cx >= GW || cy >= GH) return rgb(24, 70, 130);
   switch (kMap[cy][cx])
   {
   case 'W': return rgb(40, 100, 170);
   case 'M': return ((cx + cy) % 3 == 0) ? rgb(235, 238, 242) : ((cx + cy) % 3 == 1 ? rgb(120, 130, 120) : rgb(90, 110, 90));
   case 'P': return rgb(40, 140, 60);
   default:  return rgb(170, 200, 120);
   }
}

// z = pixels per cell; camera centre in cell units.
static void draw_map(OSScreenID s, int w, int h, float camx, float camy, float z, int step)
{
   for (int y = 0; y < h; y += step)
      for (int x = 0; x < w; x += step)
      {
         float fx = camx + (x + step / 2 - w / 2) / z, fy = camy + (y + step / 2 - h / 2) / z;
         int cx = (int)(fx < 0 ? fx - 1 : fx), cy = (int)(fy < 0 ? fy - 1 : fy);
         fill(s, x, y, step, step, cell_colour(cx, cy));
      }
}

int main(void)
{
   VPADInit();
   OSScreenInit();
   void *tv = memalign(0x100, OSScreenGetBufferSizeEx(SCREEN_TV));
   void *drc = memalign(0x100, OSScreenGetBufferSizeEx(SCREEN_DRC));
   OSScreenSetBufferEx(SCREEN_TV, tv);
   OSScreenSetBufferEx(SCREEN_DRC, drc);
   OSScreenEnableEx(SCREEN_TV, 1);
   OSScreenEnableEx(SCREEN_DRC, 1);

   float camx = 20, camy = 15, zoom = 18;
   int dirty = 2;

   for (;;)
   {
      VPADStatus st; VPADReadError err;
      if (VPADRead(VPAD_CHAN_0, &st, 1, &err) > 0 && err == VPAD_READ_SUCCESS)
      {
         float lx = st.leftStick.x, ly = st.leftStick.y, ry = st.rightStick.y;
         if (lx > 0.15f || lx < -0.15f || ly > 0.15f || ly < -0.15f || ry > 0.15f || ry < -0.15f)
         {
            camx += lx * 18.0f / zoom; camy -= ly * 18.0f / zoom;
            zoom += ry * 0.6f * zoom / 18.0f;
            if (st.hold & VPAD_BUTTON_ZR) zoom *= 1.03f;
            if (zoom < 8) zoom = 8;
            if (zoom > 60) zoom = 60;
            if (camx < 0) camx = 0; if (camx > GW) camx = GW;
            if (camy < 0) camy = 0; if (camy > GH) camy = GH;
            dirty = 2;
         }
         if (st.trigger & VPAD_BUTTON_A) { camx = 20; camy = 15; zoom = 18; dirty = 2; }
      }

      if (dirty > 0)
      {
         dirty--;
         draw_map(SCREEN_TV, 1280, 720, camx, camy, zoom, 4);
         for (int i = 0; i < NPLACES; i++)
         {
            int px = 640 + (int)((kPlaces[i].cx + 0.5f - camx) * zoom);
            int py = 360 + (int)((kPlaces[i].cy + 0.5f - camy) * zoom);
            if (px > -200 && px < 1480 && py > -20 && py < 740)
               label(SCREEN_TV, kPlaces[i].name, px, py, 2);
         }
         label(SCREEN_TV, "METRO VANCOUVER BC  -  MUFFINEMU", 640, 8, 2);
         label(SCREEN_TV, "MAP DATA (C) OPENSTREETMAP CONTRIBUTORS, ODBL", 640, 700, 1);

         // GamePad: whole-map minimap with a view box.
         OSScreenClearBufferEx(SCREEN_DRC, rgb(10, 20, 40));
         draw_map(SCREEN_DRC, 854, 480, 20, 15, 12, 4);
         for (int i = 0; i < NPLACES; i++)
            label(SCREEN_DRC, kPlaces[i].name, 427 + (int)((kPlaces[i].cx + 0.5f - 20) * 12),
                  240 + (int)((kPlaces[i].cy + 0.5f - 15) * 12), 1);
         float vw = 1280 / zoom * 12, vh = 720 / zoom * 12;
         int bx = 427 + (int)((camx - 20) * 12 - vw / 2), by = 240 + (int)((camy - 15) * 12 - vh / 2);
         uint32_t red = rgb(255, 40, 40);
         fill(SCREEN_DRC, bx, by, (int)vw, 2, red); fill(SCREEN_DRC, bx, by + (int)vh, (int)vw, 2, red);
         fill(SCREEN_DRC, bx, by, 2, (int)vh, red); fill(SCREEN_DRC, bx + (int)vw, by, 2, (int)vh, red);
         label(SCREEN_DRC, "MUFFINEMU  MAP DATA (C) OPENSTREETMAP CONTRIBUTORS, ODBL", 427, 468, 1);

         DCFlushRange(tv, OSScreenGetBufferSizeEx(SCREEN_TV));
         DCFlushRange(drc, OSScreenGetBufferSizeEx(SCREEN_DRC));
         OSScreenFlipBuffersEx(SCREEN_TV);
         OSScreenFlipBuffersEx(SCREEN_DRC);
      }
      else
         OSSleepTicks(OSMillisecondsToTicks(16));
   }
   return 0;
}
