// vancouver.rpx - 3D flyover of Metro Vancouver, BC for Wii U homebrew.
//
// Approach: software-rasterised voxel-space terrain renderer (Comanche style) into a
// 160x90 buffer, drawn through OSScreen at 4x. No GX2 shaders. Terrain is a 128x96
// heightmap hand-shaped from a sketch (tools/gen_vancouver_height.py); no SRTM is used.
// Downtown and Metrotown towers, two bridges, fog, a sun term and a day/night switch
// are generated at runtime. GamePad shows a top-down mini-map with labels.
// Map data (c) OpenStreetMap contributors, ODbL (geography used as reference only).
// Made by MuffinEMU. Licence: same terms as the repository (MPL-2.0).

#include <coreinit/cache.h>
#include <coreinit/screen.h>
#include <coreinit/thread.h>
#include <coreinit/time.h>
#include <vpad/input.h>
#include <malloc.h>
#include <stdint.h>

#define MW 128
#define MH 96
#define VW 160
#define VH 90
#define SC 4
#define MAXD 150.0f

static const uint8_t kH[MW * MH] = {
#include "vancouver_height.h"
};

typedef struct { const char *name; float x, y; } Place;
#define G(c) ((c) * 3.2f)
static const Place kPlaces[] = {
   { "VANCOUVER", G(12), G(12.5f) }, { "BURNABY", G(22), G(12) }, { "RICHMOND", G(14), G(21.5f) },
   { "SURREY", G(31), G(22.5f) }, { "NORTH VANCOUVER", G(17), G(7.5f) }, { "WEST VANCOUVER", G(12), G(5.5f) },
   { "COQUITLAM", G(33), G(11) }, { "NEW WESTMINSTER", G(25), G(16) }, { "DELTA", G(21), G(26.5f) },
   { "STANLEY PARK", G(7), G(9.5f) },
};
#define NPLACES ((int)(sizeof(kPlaces) / sizeof(kPlaces[0])))

static uint32_t rgb(uint32_t r, uint32_t g, uint32_t b) { return (r << 24) | (g << 16) | (b << 8) | 0xFFu; }
static float clampf(float v, float a, float b) { return v < a ? a : (v > b ? b : v); }

static float fsin(float x)
{
   const float PI = 3.14159265f;
   while (x > PI) x -= 2 * PI;
   while (x < -PI) x += 2 * PI;
   float y = 1.27323954f * x - 0.405284735f * x * (x < 0 ? -x : x);
   return 0.225f * (y * (y < 0 ? -y : y) - y) + y;
}
static float fcos(float x) { return fsin(x + 1.57079633f); }

static uint32_t hash2(int x, int y)
{
   uint32_t h = (uint32_t)x * 374761393u + (uint32_t)y * 668265263u;
   h = (h ^ (h >> 13)) * 1274126177u;
   return h ^ (h >> 16);
}

static int raw(int x, int y) { return (x < 0 || y < 0 || x >= MW || y >= MH) ? 0 : kH[y * MW + x]; }
static int terr(int x, int y) { return raw(x, y) & 127; }

// Extruded box towers: downtown (Vancouver peninsula) and Metrotown (Burnaby).
static int tower(int x, int y)
{
   static const int cx[2] = { 35, 64 }, cy[2] = { 36, 42 }, rx[2] = { 7, 5 }, ry[2] = { 5, 4 };
   if (terr(x, y) == 0) return 0;
   for (int k = 0; k < 2; k++)
   {
      int dx = x - cx[k], dy = y - cy[k];
      if (dx < 0) dx = -dx;
      if (dy < 0) dy = -dy;
      if (dx > rx[k] || dy > ry[k]) continue;
      uint32_t h = hash2(x >> 1, y >> 1);
      if (h % 100 >= 55) continue;
      int t = 6 + (int)((h >> 8) % 26);
      t = t * (rx[k] + 1 - dx) / (rx[k] + 1);
      return t < 3 ? 3 : t;
   }
   return 0;
}

// Lions Gate (First Narrows) and Port Mann (Fraser River): flat decks over water.
static int bridge(int x, int y)
{
   if (terr(x, y) != 0) return 0;
   if (x >= 29 && x <= 31 && y >= 26 && y <= 34) return 14;
   if (x >= 88 && x <= 90 && y >= 60 && y <= 70) return 16;
   return 0;
}

typedef struct { float x, y, z, yaw, horizon; int night; int frame; } Cam;

static uint32_t mix(uint32_t c, uint32_t fog, float f)
{
   float r = ((c >> 24) & 255) * (1 - f) + ((fog >> 24) & 255) * f;
   float g = ((c >> 16) & 255) * (1 - f) + ((fog >> 16) & 255) * f;
   float b = ((c >> 8) & 255) * (1 - f) + ((fog >> 8) & 255) * f;
   return rgb((uint32_t)r, (uint32_t)g, (uint32_t)b);
}

static uint32_t scale(uint32_t c, float s)
{
   float r = clampf(((c >> 24) & 255) * s, 0, 255), g = clampf(((c >> 16) & 255) * s, 0, 255), b = clampf(((c >> 8) & 255) * s, 0, 255);
   return rgb((uint32_t)r, (uint32_t)g, (uint32_t)b);
}

static uint32_t g_fb[VW * VH];

static void render(const Cam *c)
{
   uint32_t fog = c->night ? rgb(14, 18, 40) : rgb(175, 200, 225);
   float hor = c->horizon;
   for (int y = 0; y < VH; y++)
   {
      float t = clampf((hor - y) / 60.0f, 0, 1);
      uint32_t top = c->night ? rgb(4, 6, 20) : rgb(70, 130, 215);
      uint32_t s = mix(fog, top, t);
      for (int x = 0; x < VW; x++) g_fb[y * VW + x] = s;
   }
   float tt = c->frame * 0.05f;
   for (int i = 0; i < VW; i++)
   {
      float a = c->yaw + ((float)i / VW - 0.5f) * 1.2f;
      float dx = fcos(a), dy = fsin(a);
      int ybuf = VH;
      float z = 1, dz = 1;
      while (z < MAXD && ybuf > 0)
      {
         int ix = (int)(c->x + dx * z), iy = (int)(c->y + dy * z);
         if (c->x + dx * z < 0) ix = -1;
         if (c->y + dy * z < 0) iy = -1;
         int raw0 = raw(ix, iy);
         int h = raw0 & 127;
         int tw = tower(ix, iy), br = bridge(ix, iy);
         float top = (float)(h + tw + br);
         int hy = (int)((c->z - top) * 95.0f / z + hor);
         if (hy < 0) hy = 0;
         if (hy < ybuf)
         {
            uint32_t col;
            if (h == 0 && !br)
               col = rgb(30, (uint32_t)(88 + 12 * fsin(tt + ix * 0.7f + iy * 0.5f)), (uint32_t)(160 + 14 * fsin(tt * 1.3f + ix * 0.4f)));
            else if (br)
               col = rgb(150, 150, 160);
            else if (tw)
               col = rgb(110, 120, 140);
            else if (h >= 88)
               col = rgb(240, 242, 248);
            else if (raw0 & 128)
               col = rgb(30, 120, 50);
            else if (h > 40)
               col = rgb(75, 100, 70);
            else if (h > 14)
               col = rgb(95, 140, 80);
            else
               col = rgb(130, 170, 100);
            float shade = 0.95f + (h - terr(ix + 1, iy + 1)) * 0.05f;
            if (!tw && !br && h) col = scale(col, clampf(shade, 0.55f, 1.3f));
            if (c->night) col = scale(col, 0.3f);
            float f = z / MAXD; f = f * f;
            for (int y = hy; y < ybuf; y++)
            {
               uint32_t pc = col;
               if (tw)
               {
                  int lit = ((y * 7 + ix * 13 + iy * 5) % 5) < 2;
                  if (c->night) pc = lit ? rgb(255, 215, 110) : rgb(25, 28, 40);
                  else if (lit) pc = rgb(150, 190, 220);
               }
               else if (br && c->night && (ix + iy) % 2) pc = rgb(255, 240, 180);
               g_fb[y * VW + i] = mix(pc, fog, f);
            }
            ybuf = hy;
         }
         z += dz;
         dz += 0.025f;
      }
   }
}

static void fill(OSScreenID s, int x, int y, int w, int h, uint32_t c)
{
   for (int j = 0; j < h; j++)
      for (int i = 0; i < w; i++)
         OSScreenPutPixelEx(s, x + i, y + j, c);
}

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

static void label(OSScreenID s, const char *t, int x, int y, int sc)
{
   int n = 0; for (const char *p = t; *p; p++) n++;
   x -= n * 6 * sc / 2;
   text(s, t, x + 1, y + 1, sc, rgb(0, 0, 0));
   text(s, t, x, y, sc, rgb(255, 255, 255));
}

static uint32_t mini_colour(int x, int y)
{
   int r = raw(x, y), h = r & 127;
   if (!h) return rgb(40, 100, 170);
   if (r & 128) return rgb(30, 120, 50);
   if (h >= 88) return rgb(240, 242, 248);
   if (h > 40) return rgb(75, 100, 70);
   if (h > 14) return rgb(95, 140, 80);
   return rgb(130, 170, 100);
}

int main(void)
{
   VPADInit();
   OSScreenInit();
   uint32_t tvSize = OSScreenGetBufferSizeEx(SCREEN_TV), drcSize = OSScreenGetBufferSizeEx(SCREEN_DRC);
   void *tv = memalign(0x100, tvSize), *drc = memalign(0x100, drcSize);
   OSScreenSetBufferEx(SCREEN_TV, tv);
   OSScreenSetBufferEx(SCREEN_DRC, drc);
   OSScreenEnableEx(SCREEN_TV, 1);
   OSScreenEnableEx(SCREEN_DRC, 1);

   Cam cam = { 38, 22, 70, 1.57f, 40, 0, 0 };

   for (;;)
   {
      VPADStatus st; VPADReadError err;
      if (VPADRead(VPAD_CHAN_0, &st, 1, &err) > 0 && err == VPAD_READ_SUCCESS)
      {
         float lx = st.leftStick.x, ly = st.leftStick.y, rx = st.rightStick.x, ry = st.rightStick.y;
         if (lx > -0.12f && lx < 0.12f) lx = 0;
         if (ly > -0.12f && ly < 0.12f) ly = 0;
         if (rx > -0.12f && rx < 0.12f) rx = 0;
         if (ry > -0.12f && ry < 0.12f) ry = 0;
         cam.yaw += rx * 0.04f;
         cam.horizon = clampf(cam.horizon + ry * 1.5f, 5, 85);
         float fx = fcos(cam.yaw), fy = fsin(cam.yaw);
         cam.x += (fx * ly - fy * lx) * 0.9f;
         cam.y += (fy * ly + fx * lx) * 0.9f;
         if (st.hold & VPAD_BUTTON_L) cam.z += 1.2f;
         if (st.hold & VPAD_BUTTON_ZL) cam.z -= 1.2f;
         cam.x = clampf(cam.x, 0, MW - 1); cam.y = clampf(cam.y, 0, MH - 1);
         float floor = (float)(terr((int)cam.x, (int)cam.y) + tower((int)cam.x, (int)cam.y)) + 4;
         cam.z = clampf(cam.z, floor, 220);
         if (st.trigger & VPAD_BUTTON_A) cam.night = !cam.night;
         if (st.trigger & VPAD_BUTTON_B) { cam.x = 38; cam.y = 22; cam.z = 70; cam.yaw = 1.57f; cam.horizon = 40; }
      }
      cam.frame++;
      render(&cam);

      // TV: 3D view at 4x in the centre, credits in the margins.
      OSScreenClearBufferEx(SCREEN_TV, rgb(8, 10, 18));
      for (int y = 0; y < VH; y++)
         for (int x = 0; x < VW; x++)
            fill(SCREEN_TV, 320 + x * SC, 180 + y * SC, SC, SC, g_fb[y * VW + x]);
      label(SCREEN_TV, "METRO VANCOUVER BC 3D  -  MUFFINEMU", 640, 120, 2);
      label(SCREEN_TV, "LEFT STICK MOVE  RIGHT STICK LOOK  L UP  ZL DOWN  A DAY NIGHT  B RESET", 640, 560, 1);
      label(SCREEN_TV, "MAP DATA (C) OPENSTREETMAP CONTRIBUTORS, ODBL", 640, 590, 1);

      // GamePad: top-down mini-map, 3x, with position and heading.
      OSScreenClearBufferEx(SCREEN_DRC, rgb(10, 20, 40));
      const int ox = 235, oy = 70;
      for (int y = 0; y < MH; y++)
         for (int x = 0; x < MW; x++)
            fill(SCREEN_DRC, ox + x * 3, oy + y * 3, 3, 3, mini_colour(x, y));
      for (int i = 0; i < NPLACES; i++)
         label(SCREEN_DRC, kPlaces[i].name, ox + (int)(kPlaces[i].x * 3), oy + (int)(kPlaces[i].y * 3), 1);
      int px = ox + (int)(cam.x * 3), py = oy + (int)(cam.y * 3);
      fill(SCREEN_DRC, px - 2, py - 2, 5, 5, rgb(255, 40, 40));
      for (int k = 3; k < 12; k++)
         fill(SCREEN_DRC, px + (int)(fcos(cam.yaw) * k), py + (int)(fsin(cam.yaw) * k), 2, 2, rgb(255, 255, 0));
      label(SCREEN_DRC, "MUFFINEMU  MAP DATA (C) OPENSTREETMAP CONTRIBUTORS, ODBL", 427, 450, 1);

      DCFlushRange(tv, tvSize);
      DCFlushRange(drc, drcSize);
      OSScreenFlipBuffersEx(SCREEN_TV);
      OSScreenFlipBuffersEx(SCREEN_DRC);
   }
   return 0;
}
