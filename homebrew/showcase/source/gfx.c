// Framebuffer layer. Everything goes through OSScreen's two buffers, written directly as words.
// OSScreen is double buffered: the buffer handed to OSScreenSetBufferEx holds two frames, we draw
// into one half and OSScreenFlipBuffersEx swaps which half is shown.
#include "showcase.h"

#include <coreinit/cache.h>
#include <coreinit/screen.h>
#include <malloc.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

Surf S_TV, S_DRC, S_SCN;
int g_scale = 4, g_sw = SCN_W, g_sh = SCN_H;

static u32 g_scn[SCN_W * SCN_H];
static void *s_tv_base, *s_drc_base;
static u32 s_tv_size, s_drc_size;
static int s_tv_parity, s_drc_parity;

void gfx_set_scale(int scale)
{
   g_scale = scale == 8 ? 8 : 4;
   g_sw = TV_W / g_scale;
   g_sh = TV_H / g_scale;
   S_SCN.p = g_scn;
   S_SCN.pitch = g_sw;
   S_SCN.w = g_sw;
   S_SCN.h = g_sh;
   memset(g_scn, 0, sizeof(g_scn));
}

void gfx_init(void)
{
   OSScreenInit();
   s_tv_size = OSScreenGetBufferSizeEx(SCREEN_TV);
   s_drc_size = OSScreenGetBufferSizeEx(SCREEN_DRC);
   s_tv_base = memalign(0x100, s_tv_size);
   s_drc_base = memalign(0x100, s_drc_size);
   memset(s_tv_base, 0, s_tv_size);
   memset(s_drc_base, 0, s_drc_size);
   DCFlushRange(s_tv_base, s_tv_size);
   DCFlushRange(s_drc_base, s_drc_size);
   OSScreenSetBufferEx(SCREEN_TV, s_tv_base);
   OSScreenSetBufferEx(SCREEN_DRC, s_drc_base);
   OSScreenEnableEx(SCREEN_TV, 1);
   OSScreenEnableEx(SCREEN_DRC, 1);
   S_TV.pitch = TV_W; S_TV.w = TV_W; S_TV.h = TV_H;
   S_DRC.pitch = DRC_PITCH; S_DRC.w = DRC_W; S_DRC.h = DRC_H;
   gfx_set_scale(4);
   gfx_begin_frame();
}

void gfx_begin_frame(void)
{
   S_TV.p = (u32 *)((u8 *)s_tv_base + (s_tv_parity ? s_tv_size / 2 : 0));
   S_DRC.p = (u32 *)((u8 *)s_drc_base + (s_drc_parity ? s_drc_size / 2 : 0));
}

void gfx_present_scene(void)
{
   const int s = g_scale;
   for (int y = 0; y < g_sh; y++)
   {
      const u32 *src = S_SCN.p + y * g_sw;
      u32 *row = S_TV.p + (y * s) * TV_W;
      u32 *d = row;
      if (s == 4)
      {
         for (int x = 0; x < g_sw; x++)
         {
            u32 c = src[x];
            d[0] = c; d[1] = c; d[2] = c; d[3] = c;
            d += 4;
         }
      }
      else
      {
         for (int x = 0; x < g_sw; x++)
         {
            u32 c = src[x];
            d[0] = c; d[1] = c; d[2] = c; d[3] = c; d[4] = c; d[5] = c; d[6] = c; d[7] = c;
            d += 8;
         }
      }
      for (int k = 1; k < s; k++)
         memcpy(row + k * TV_W, row, TV_W * 4);
   }
}

void gfx_flip_tv(void)
{
   DCFlushRange(s_tv_base, s_tv_size);
   OSScreenFlipBuffersEx(SCREEN_TV);
   s_tv_parity ^= 1;
   gfx_begin_frame();
}

void gfx_flip_drc(void)
{
   DCFlushRange(s_drc_base, s_drc_size);
   OSScreenFlipBuffersEx(SCREEN_DRC);
   s_drc_parity ^= 1;
   gfx_begin_frame();
}

// ------------------------------------------------------------------ primitives

void s_fill(Surf *s, u32 c) { s_rect(s, 0, 0, s->w, s->h, c); }

void s_rect(Surf *s, int x, int y, int w, int h, u32 c)
{
   if (x < 0) { w += x; x = 0; }
   if (y < 0) { h += y; y = 0; }
   if (x + w > s->w) w = s->w - x;
   if (y + h > s->h) h = s->h - y;
   if (w <= 0 || h <= 0) return;
   for (int j = 0; j < h; j++)
   {
      u32 *p = s->p + (y + j) * s->pitch + x;
      for (int i = 0; i < w; i++) p[i] = c;
   }
}

void s_rect_a(Surf *s, int x, int y, int w, int h, u32 c, int a)
{
   if (x < 0) { w += x; x = 0; }
   if (y < 0) { h += y; y = 0; }
   if (x + w > s->w) w = s->w - x;
   if (y + h > s->h) h = s->h - y;
   if (w <= 0 || h <= 0) return;
   int ia = 256 - a;
   u32 sr = CR(c) * (u32)a, sg = CG(c) * (u32)a, sb = CB(c) * (u32)a;
   for (int j = 0; j < h; j++)
   {
      u32 *p = s->p + (y + j) * s->pitch + x;
      for (int i = 0; i < w; i++)
      {
         u32 d = p[i];
         p[i] = RGB((sr + CR(d) * (u32)ia) >> 8, (sg + CG(d) * (u32)ia) >> 8, (sb + CB(d) * (u32)ia) >> 8);
      }
   }
}

void s_vgrad(Surf *s, int x, int y, int w, int h, u32 c0, u32 c1)
{
   for (int j = 0; j < h; j++)
      s_rect(s, x, y + j, w, 1, col_mix(c0, c1, h > 1 ? j * 255 / (h - 1) : 0));
}

void s_hline(Surf *s, int x, int y, int w, u32 c) { s_rect(s, x, y, w, 1, c); }
void s_vline(Surf *s, int x, int y, int h, u32 c) { s_rect(s, x, y, 1, h, c); }

void s_box_outline(Surf *s, int x, int y, int w, int h, u32 c)
{
   s_hline(s, x, y, w, c);
   s_hline(s, x, y + h - 1, w, c);
   s_vline(s, x, y, h, c);
   s_vline(s, x + w - 1, y, h, c);
}

void s_panel(Surf *s, int x, int y, int w, int h, u32 border)
{
   s_rect_a(s, x, y, w, h, COL_PANEL, 205);
   s_box_outline(s, x, y, w, h, border);
}

static void put(Surf *s, int x, int y, u32 c)
{
   if ((unsigned)x < (unsigned)s->w && (unsigned)y < (unsigned)s->h) s->p[y * s->pitch + x] = c;
}

void s_add_pixel(Surf *s, int x, int y, u32 c)
{
   if ((unsigned)x < (unsigned)s->w && (unsigned)y < (unsigned)s->h)
   {
      u32 *p = &s->p[y * s->pitch + x];
      *p = col_add(*p, c);
   }
}

void s_line(Surf *s, int x0, int y0, int x1, int y1, u32 c)
{
   int dx = x1 > x0 ? x1 - x0 : x0 - x1, sx = x0 < x1 ? 1 : -1;
   int dy = y1 > y0 ? y0 - y1 : y1 - y0, sy = y0 < y1 ? 1 : -1;
   int err = dx + dy;
   for (int n = 0; n < 4000; n++)
   {
      put(s, x0, y0, c);
      if (x0 == x1 && y0 == y1) break;
      int e2 = 2 * err;
      if (e2 >= dy) { err += dy; x0 += sx; }
      if (e2 <= dx) { err += dx; y0 += sy; }
   }
}

void s_disc(Surf *s, int cx, int cy, int r, u32 c)
{
   for (int j = -r; j <= r; j++)
   {
      int w = (int)m_sqrt((float)(r * r - j * j) + 0.5f);
      s_rect(s, cx - w, cy + j, 2 * w + 1, 1, c);
   }
}

void s_ring(Surf *s, int cx, int cy, int r, u32 c)
{
   int steps = r * 6 + 12;
   for (int i = 0; i < steps; i++)
   {
      float a = TAU_F * (float)i / (float)steps;
      put(s, cx + (int)(m_cos(a) * (float)r + 0.5f), cy + (int)(m_sin(a) * (float)r + 0.5f), c);
   }
}

void s_tri(Surf *s, int x0, int y0, int x1, int y1, int x2, int y2, u32 c)
{
   int minx = x0 < x1 ? (x0 < x2 ? x0 : x2) : (x1 < x2 ? x1 : x2);
   int maxx = x0 > x1 ? (x0 > x2 ? x0 : x2) : (x1 > x2 ? x1 : x2);
   int miny = y0 < y1 ? (y0 < y2 ? y0 : y2) : (y1 < y2 ? y1 : y2);
   int maxy = y0 > y1 ? (y0 > y2 ? y0 : y2) : (y1 > y2 ? y1 : y2);
   if (minx < 0) minx = 0;
   if (miny < 0) miny = 0;
   if (maxx >= s->w) maxx = s->w - 1;
   if (maxy >= s->h) maxy = s->h - 1;
   int area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0);
   if (area == 0) return;
   for (int y = miny; y <= maxy; y++)
   {
      u32 *row = s->p + y * s->pitch;
      for (int x = minx; x <= maxx; x++)
      {
         int w0 = (x1 - x0) * (y - y0) - (x - x0) * (y1 - y0);   // edge 0-1
         int w1 = (x2 - x1) * (y - y1) - (x - x1) * (y2 - y1);   // edge 1-2
         int w2 = (x0 - x2) * (y - y2) - (x - x2) * (y0 - y2);   // edge 2-0
         if (area > 0 ? (w0 >= 0 && w1 >= 0 && w2 >= 0) : (w0 <= 0 && w1 <= 0 && w2 <= 0))
            row[x] = c;
      }
   }
}

void s_fade(Surf *s, int k)
{
   for (int y = 0; y < s->h; y++)
   {
      u32 *p = s->p + y * s->pitch;
      for (int x = 0; x < s->w; x++)
      {
         u32 c = p[x];
         p[x] = RGB((CR(c) * (u32)k) >> 8, (CG(c) * (u32)k) >> 8, (CB(c) * (u32)k) >> 8);
      }
   }
}

// ------------------------------------------------------------------ bitmap font
// 5x7 glyphs, one byte per row, bit 4 is the leftmost pixel. Drawn by this program; no system
// font is used. Lowercase letters render as capitals.
typedef struct { char c; u8 r[7]; } Glyph;
static const Glyph kGlyphs[] = {
   {'A',{0x0E,0x11,0x11,0x1F,0x11,0x11,0x11}}, {'B',{0x1E,0x11,0x11,0x1E,0x11,0x11,0x1E}},
   {'C',{0x0E,0x11,0x10,0x10,0x10,0x11,0x0E}}, {'D',{0x1E,0x11,0x11,0x11,0x11,0x11,0x1E}},
   {'E',{0x1F,0x10,0x10,0x1E,0x10,0x10,0x1F}}, {'F',{0x1F,0x10,0x10,0x1E,0x10,0x10,0x10}},
   {'G',{0x0E,0x11,0x10,0x17,0x11,0x11,0x0F}}, {'H',{0x11,0x11,0x11,0x1F,0x11,0x11,0x11}},
   {'I',{0x0E,0x04,0x04,0x04,0x04,0x04,0x0E}}, {'J',{0x07,0x02,0x02,0x02,0x02,0x12,0x0C}},
   {'K',{0x11,0x12,0x14,0x18,0x14,0x12,0x11}}, {'L',{0x10,0x10,0x10,0x10,0x10,0x10,0x1F}},
   {'M',{0x11,0x1B,0x15,0x15,0x11,0x11,0x11}}, {'N',{0x11,0x11,0x19,0x15,0x13,0x11,0x11}},
   {'O',{0x0E,0x11,0x11,0x11,0x11,0x11,0x0E}}, {'P',{0x1E,0x11,0x11,0x1E,0x10,0x10,0x10}},
   {'Q',{0x0E,0x11,0x11,0x11,0x15,0x12,0x0D}}, {'R',{0x1E,0x11,0x11,0x1E,0x14,0x12,0x11}},
   {'S',{0x0F,0x10,0x10,0x0E,0x01,0x01,0x1E}}, {'T',{0x1F,0x04,0x04,0x04,0x04,0x04,0x04}},
   {'U',{0x11,0x11,0x11,0x11,0x11,0x11,0x0E}}, {'V',{0x11,0x11,0x11,0x11,0x11,0x0A,0x04}},
   {'W',{0x11,0x11,0x11,0x15,0x15,0x15,0x0A}}, {'X',{0x11,0x11,0x0A,0x04,0x0A,0x11,0x11}},
   {'Y',{0x11,0x11,0x0A,0x04,0x04,0x04,0x04}}, {'Z',{0x1F,0x01,0x02,0x04,0x08,0x10,0x1F}},
   {'0',{0x0E,0x11,0x13,0x15,0x19,0x11,0x0E}}, {'1',{0x04,0x0C,0x04,0x04,0x04,0x04,0x0E}},
   {'2',{0x0E,0x11,0x01,0x02,0x04,0x08,0x1F}}, {'3',{0x1F,0x02,0x04,0x02,0x01,0x11,0x0E}},
   {'4',{0x02,0x06,0x0A,0x12,0x1F,0x02,0x02}}, {'5',{0x1F,0x10,0x1E,0x01,0x01,0x11,0x0E}},
   {'6',{0x06,0x08,0x10,0x1E,0x11,0x11,0x0E}}, {'7',{0x1F,0x01,0x02,0x04,0x08,0x08,0x08}},
   {'8',{0x0E,0x11,0x11,0x0E,0x11,0x11,0x0E}}, {'9',{0x0E,0x11,0x11,0x0F,0x01,0x02,0x0C}},
   {'.',{0x00,0x00,0x00,0x00,0x00,0x0C,0x0C}}, {',',{0x00,0x00,0x00,0x00,0x0C,0x04,0x08}},
   {':',{0x00,0x0C,0x0C,0x00,0x0C,0x0C,0x00}}, {';',{0x00,0x0C,0x0C,0x00,0x0C,0x04,0x08}},
   {'!',{0x04,0x04,0x04,0x04,0x04,0x00,0x04}}, {'?',{0x0E,0x11,0x01,0x02,0x04,0x00,0x04}},
   {'-',{0x00,0x00,0x00,0x1F,0x00,0x00,0x00}}, {'+',{0x00,0x04,0x04,0x1F,0x04,0x04,0x00}},
   {'*',{0x00,0x11,0x0A,0x1F,0x0A,0x11,0x00}}, {'/',{0x01,0x01,0x02,0x04,0x08,0x10,0x10}},
   {'%',{0x18,0x19,0x02,0x04,0x08,0x13,0x03}}, {'(',{0x02,0x04,0x08,0x08,0x08,0x04,0x02}},
   {')',{0x08,0x04,0x02,0x02,0x02,0x04,0x08}}, {'[',{0x0E,0x08,0x08,0x08,0x08,0x08,0x0E}},
   {']',{0x0E,0x02,0x02,0x02,0x02,0x02,0x0E}}, {'<',{0x02,0x04,0x08,0x10,0x08,0x04,0x02}},
   {'>',{0x08,0x04,0x02,0x01,0x02,0x04,0x08}}, {'=',{0x00,0x00,0x1F,0x00,0x1F,0x00,0x00}},
   {'_',{0x00,0x00,0x00,0x00,0x00,0x00,0x1F}}, {'\'',{0x04,0x04,0x08,0x00,0x00,0x00,0x00}},
   {'"',{0x0A,0x0A,0x0A,0x00,0x00,0x00,0x00}}, {'#',{0x0A,0x0A,0x1F,0x0A,0x1F,0x0A,0x0A}},
   {'|',{0x04,0x04,0x04,0x04,0x04,0x04,0x04}}, {'~',{0x00,0x00,0x08,0x15,0x02,0x00,0x00}},
   {'^',{0x04,0x0A,0x11,0x00,0x00,0x00,0x00}}, {'@',{0x0E,0x11,0x17,0x15,0x17,0x10,0x0E}},
   {'&',{0x0C,0x12,0x14,0x08,0x15,0x12,0x0D}}, {'$',{0x04,0x0F,0x14,0x0E,0x05,0x1E,0x04}},
};
static const u8 *s_glyph_lut[128];
static int s_font_ready;

static void font_init(void)
{
   for (unsigned i = 0; i < sizeof(kGlyphs) / sizeof(kGlyphs[0]); i++)
   {
      s_glyph_lut[(int)kGlyphs[i].c] = kGlyphs[i].r;
      if (kGlyphs[i].c >= 'A' && kGlyphs[i].c <= 'Z') s_glyph_lut[kGlyphs[i].c + 32] = kGlyphs[i].r;
   }
   s_font_ready = 1;
}

int text_w(const char *str, int scale)
{
   int n = (int)strlen(str);
   return n > 0 ? n * 6 * scale - scale : 0;
}

void s_text(Surf *s, int x, int y, int scale, u32 c, const char *str)
{
   if (!s_font_ready) font_init();
   if (y + 7 * scale < 0 || y >= s->h) return;
   for (; *str; str++)
   {
      unsigned ch = (unsigned char)*str;
      const u8 *g = ch < 128 ? s_glyph_lut[ch] : 0;
      if (g)
      {
         for (int r = 0; r < 7; r++)
         {
            u8 bits = g[r];
            for (int cc = 0; cc < 5; cc++)
               if (bits & (0x10 >> cc))
                  s_rect(s, x + cc * scale, y + r * scale, scale, scale, c);
         }
      }
      x += 6 * scale;
   }
}

void s_text_sh(Surf *s, int x, int y, int scale, u32 c, const char *str)
{
   s_text(s, x + scale, y + scale, scale, RGB(0, 0, 0), str);
   s_text(s, x, y, scale, c, str);
}

void s_textf(Surf *s, int x, int y, int scale, u32 c, const char *fmt, ...)
{
   char buf[160];
   va_list ap;
   va_start(ap, fmt);
   vsnprintf(buf, sizeof(buf), fmt, ap);
   va_end(ap);
   s_text_sh(s, x, y, scale, c, buf);
}

// Copies the internal scene buffer to the GamePad, pixel-doubled (or quadrupled) so the GamePad
// can show a second view of the same frame.
void gfx_blit_scene_drc(int x0, int y0)
{
   int f = DRC_W > 0 ? 640 / g_sw : 2;
   for (int y = 0; y < g_sh; y++)
   {
      const u32 *src = S_SCN.p + y * g_sw;
      int dy = y0 + y * f;
      if (dy + f > DRC_H) break;
      u32 *row = S_DRC.p + dy * S_DRC.pitch + x0;
      u32 *d = row;
      for (int x = 0; x < g_sw; x++)
      {
         u32 c = src[x];
         for (int k = 0; k < f; k++) d[k] = c;
         d += f;
      }
      for (int k = 1; k < f; k++)
         memcpy(row + k * S_DRC.pitch, row, (size_t)(g_sw * f) * 4);
   }
}
