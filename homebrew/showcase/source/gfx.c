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
int g_scale = 2, g_sw = SCN_W, g_sh = SCN_H;

static u32 g_scn[SCN_W * SCN_H] __attribute__((aligned(32)));
static void *s_tv_base, *s_drc_base;
static u32 s_tv_size, s_drc_size;
static int s_tv_parity, s_drc_parity;

void gfx_set_scale(int scale)
{
   g_scale = (scale == 2 || scale == 8) ? scale : 4;
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
   gfx_set_scale(2);
   gfx_begin_frame();
}

void gfx_begin_frame(void)
{
   S_TV.p = (u32 *)((u8 *)s_tv_base + (s_tv_parity ? s_tv_size / 2 : 0));
   S_DRC.p = (u32 *)((u8 *)s_drc_base + (s_drc_parity ? s_drc_size / 2 : 0));
}

// Horizontal expansion of one scene row to TV width. s = 2 or 4 interpolate between neighbouring
// source pixels (linear filtering); s = 8 is the plain pixel-replicate fallback.
static void hexp(u32 *dst, const u32 *src, int w, int s)
{
   if (s == 2)
   {
      for (int x = 0; x < w - 1; x++)
      {
         dst[0] = src[x];
         dst[1] = col_avg(src[x], src[x + 1]);
         dst += 2;
      }
      dst[0] = dst[1] = src[w - 1];
   }
   else if (s == 4)
   {
      for (int x = 0; x < w - 1; x++)
      {
         u32 a = src[x], b = src[x + 1], m = col_avg(a, b);
         dst[0] = a;
         dst[1] = col_avg(a, m);
         dst[2] = m;
         dst[3] = col_avg(m, b);
         dst += 4;
      }
      dst[0] = dst[1] = dst[2] = dst[3] = src[w - 1];
   }
   else
   {
      for (int x = 0; x < w; x++)
      {
         u32 c = src[x];
         dst[0] = c; dst[1] = c; dst[2] = c; dst[3] = c; dst[4] = c; dst[5] = c; dst[6] = c; dst[7] = c;
         dst += 8;
      }
   }
}

static void present_slice(void *ctx, int job, int njobs)
{
   (void)ctx;
   const int s = g_scale, sw = g_sw, sh = g_sh;
   int y0, y1;
   par_range(job, njobs, sh, &y0, &y1);
   if (y0 >= y1) return;
   // Each slice keeps its own two row buffers on its stack (about 10 KB).
   u32 rows[2][TV_W + 8] __attribute__((aligned(32)));
   int cur = 0;
   hexp(rows[cur], S_SCN.p + y0 * sw, sw, s);
   for (int y = y0; y < y1; y++)
   {
      u32 *out = S_TV.p + (y * s) * TV_W;
      u32 *h0 = rows[cur];
      memcpy(out, h0, TV_W * 4);
      if (s == 8 || y + 1 >= sh)
      {
         for (int k = 1; k < s; k++) memcpy(out + k * TV_W, h0, TV_W * 4);
         if (y + 1 < sh) { cur ^= 1; hexp(rows[cur], S_SCN.p + (y + 1) * sw, sw, s); }
      }
      else
      {
         u32 *h1 = rows[cur ^ 1];
         hexp(h1, S_SCN.p + (y + 1) * sw, sw, s);
         if (s == 2)
         {
            u32 *o = out + TV_W;
            for (int x = 0; x < TV_W; x++) o[x] = col_avg(h0[x], h1[x]);
         }
         else
         {
            for (int k = 1; k < 4; k++)
            {
               u32 *o = out + k * TV_W;
               if (k == 2) for (int x = 0; x < TV_W; x++) o[x] = col_avg(h0[x], h1[x]);
               else
               {
                  int t = k == 1 ? 64 : 192;
                  for (int x = 0; x < TV_W; x++) o[x] = col_lerp(h0[x], h1[x], t);
               }
            }
         }
         cur ^= 1;
      }
   }
   DCFlushRange(S_TV.p + (y0 * s) * TV_W, (uint32_t)((y1 - y0) * s) * TV_W * 4);
}

void gfx_present_scene(void)
{
   par_publish(S_SCN.p, (size_t)g_sw * (size_t)g_sh * 4);
   par_run(present_slice, 0);
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

// Gouraud triangle: barycentric colour interpolation in 8.8 fixed point.
void s_tri_g(Surf *s, int x0, int y0, u32 c0, int x1, int y1, u32 c1, int x2, int y2, u32 c2)
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
   float inv = 256.0f / (float)area;
   for (int y = miny; y <= maxy; y++)
   {
      u32 *row = s->p + y * s->pitch;
      for (int x = minx; x <= maxx; x++)
      {
         int w0 = (x1 - x0) * (y - y0) - (x - x0) * (y1 - y0);   // edge 0-1: weight of vertex 2
         int w1 = (x2 - x1) * (y - y1) - (x - x1) * (y2 - y1);   // edge 1-2: weight of vertex 0
         int w2 = (x0 - x2) * (y - y2) - (x - x2) * (y0 - y2);   // edge 2-0: weight of vertex 1
         if (area > 0 ? (w0 >= 0 && w1 >= 0 && w2 >= 0) : (w0 <= 0 && w1 <= 0 && w2 <= 0))
         {
            int a = (int)((float)w1 * inv), b = (int)((float)w2 * inv), c = 256 - a - b;
            int r = ((int)CR(c0) * a + (int)CR(c1) * b + (int)CR(c2) * c) >> 8;
            int g = ((int)CG(c0) * a + (int)CG(c1) * b + (int)CG(c2) * c) >> 8;
            int bl = ((int)CB(c0) * a + (int)CB(c1) * b + (int)CB(c2) * c) >> 8;
            row[x] = RGB(r < 0 ? 0 : (r > 255 ? 255 : r), g < 0 ? 0 : (g > 255 ? 255 : g), bl < 0 ? 0 : (bl > 255 ? 255 : bl));
         }
      }
   }
}

typedef struct { Surf *s; int k; } FadeCtx;

static void fade_rows(Surf *s, int y0, int y1, int k)
{
   for (int y = y0; y < y1; y++)
   {
      u32 *p = s->p + y * s->pitch;
      for (int x = 0; x < s->w; x++)
      {
         u32 c = p[x];
         u32 rb = ((((c >> 8) & 0x00FF00FFu) * (u32)k) >> 8) & 0x00FF00FFu;
         u32 g = ((((c) & 0x00FF00FFu) * (u32)k) >> 8) & 0x00FF00FFu;
         p[x] = (rb << 8) | g | 0xFFu;
      }
   }
}

static void fade_slice(void *vc, int job, int njobs)
{
   FadeCtx *c = vc;
   int y0, y1;
   par_range(job, njobs, c->s->h, &y0, &y1);
   fade_rows(c->s, y0, y1, c->k);
   par_flush(c->s->p + y0 * c->s->pitch, (size_t)(y1 - y0) * (size_t)c->s->pitch * 4);
}

void s_fade(Surf *s, int k)
{
   if (s == &S_SCN)
   {
      FadeCtx c = { s, k };
      par_publish(s->p, (size_t)s->h * (size_t)s->pitch * 4);
      par_run(fade_slice, &c);
      par_consume(s->p, (size_t)s->h * (size_t)s->pitch * 4);
   }
   else fade_rows(s, 0, s->h, k);
}

// ------------------------------------------------------------------ smooth primitives

void s_blend_pixel(Surf *s, int x, int y, u32 c, int a)
{
   if ((unsigned)x < (unsigned)s->w && (unsigned)y < (unsigned)s->h && a > 0)
   {
      u32 *p = &s->p[y * s->pitch + x];
      *p = a >= 256 ? c : col_lerp(*p, c, a);
   }
}

static float fpart(float v) { return v - (float)m_floor(v); }

// Xiaolin Wu line.
void s_line_aa(Surf *s, float x0, float y0, float x1, float y1, u32 c)
{
   int steep = m_abs(y1 - y0) > m_abs(x1 - x0);
   float t;
   if (steep) { t = x0; x0 = y0; y0 = t; t = x1; x1 = y1; y1 = t; }
   if (x0 > x1) { t = x0; x0 = x1; x1 = t; t = y0; y0 = y1; y1 = t; }
   float dx = x1 - x0, dy = y1 - y0;
   float grad = dx < 0.0001f ? 1.0f : dy / dx;
   float y = y0 + grad * ((float)m_floor(x0 + 0.5f) - x0);
   int xa = m_floor(x0 + 0.5f), xb = m_floor(x1 + 0.5f);
   if (xb - xa > 4000) return;
   for (int x = xa; x <= xb; x++)
   {
      int yi = m_floor(y);
      int f = (int)(fpart(y) * 256.0f);
      if (steep)
      {
         s_blend_pixel(s, yi, x, c, 256 - f);
         s_blend_pixel(s, yi + 1, x, c, f);
      }
      else
      {
         s_blend_pixel(s, x, yi, c, 256 - f);
         s_blend_pixel(s, x, yi + 1, c, f);
      }
      y += grad;
   }
}

void s_disc_aa(Surf *s, float cx, float cy, float r, u32 c)
{
   int y0 = m_floor(cy - r - 1.0f), y1 = m_floor(cy + r + 1.0f);
   float ro = r + 1.0f, ri = r > 1.0f ? r - 1.0f : 0.0f;
   for (int y = y0; y <= y1; y++)
   {
      float dy = (float)y + 0.5f - cy;
      float oo = ro * ro - dy * dy;
      if (oo <= 0.0f) continue;
      float xo = m_sqrt(oo);
      float ii = ri * ri - dy * dy;
      float xi = ii > 0.0f ? m_sqrt(ii) : 0.0f;
      int xa = m_floor(cx - xo), xb = m_floor(cx + xo);
      int ia = (int)(cx - xi) + 1, ib = (int)(cx + xi);
      if (xi <= 0.0f) { ia = xb + 1; ib = xa; }
      for (int x = xa; x <= xb; x++)
      {
         if (x >= ia && x <= ib) { s_rect(s, x, y, ib - x + 1, 1, c); x = ib; continue; }
         float dx = (float)x + 0.5f - cx;
         float d = m_sqrt(dx * dx + dy * dy);
         float cov = r + 0.5f - d;
         if (cov > 0.0f) s_blend_pixel(s, x, y, c, cov >= 1.0f ? 256 : (int)(cov * 256.0f));
      }
   }
}

// Additive radial glow with a quadratic falloff; k scales the centre brightness (256 = full colour).
void s_glow(Surf *s, int cx, int cy, int r, u32 c, int k)
{
   if (r < 1) return;
   const int r2 = r * r;
   const int inv = (256 * 65536) / r2;
   for (int j = -r; j <= r; j++)
   {
      int y = cy + j;
      if ((unsigned)y >= (unsigned)s->h) continue;
      int hw = (int)m_sqrt((float)(r2 - j * j));
      for (int i = -hw; i <= hw; i++)
      {
         int x = cx + i;
         if ((unsigned)x >= (unsigned)s->w) continue;
         int d2 = i * i + j * j;
         int t = 256 - (int)(((u32)d2 * (u32)inv) >> 16);
         if (t <= 0) continue;
         t = (t * t) >> 8;
         t = (t * k) >> 8;
         u32 *p = &s->p[y * s->pitch + x];
         *p = col_add(*p, col_scale(c, t));
      }
   }
}

// Soft elliptical alpha blob: alpha a at the centre, falling smoothly to 0 at the rim.
void s_blob(Surf *s, int cx, int cy, int rx, int ry, u32 c, int a)
{
   if (rx < 1 || ry < 1) return;
   const int ix = 65536 / (rx * rx + 1) + 1, iy = 65536 / (ry * ry + 1) + 1;
   for (int j = -ry; j <= ry; j++)
   {
      int y = cy + j;
      if ((unsigned)y >= (unsigned)s->h) continue;
      int ty = j * j * iy;
      if (ty >= 65536) continue;
      for (int i = -rx; i <= rx; i++)
      {
         int x = cx + i;
         if ((unsigned)x >= (unsigned)s->w) continue;
         int d = i * i * ix + ty;
         if (d >= 65536) continue;
         int t = (65536 - d) >> 8;
         t = (t * t) >> 8;
         int al = (t * a) >> 8;
         if (al <= 0) continue;
         u32 *p = &s->p[y * s->pitch + x];
         *p = col_lerp(*p, c, al);
      }
   }
}

static int luma(u32 c) { return (int)((CR(c) * 77u + CG(c) * 150u + CB(c) * 29u) >> 8); }

// Cheap morphological edge smoothing: pixels that sit on a strong luminance edge are blurred with
// their four neighbours. Reads from a copy of the previous row so the pass is order independent.
void s_edge_aa(Surf *s, int y0, int y1)
{
   if (y0 < 1) y0 = 1;
   if (y1 > s->h - 1) y1 = s->h - 1;
   u32 prev[SCN_W];
   const int w = s->w;
   if (y0 >= y1 || w > SCN_W) return;
   memcpy(prev, s->p + (y0 - 1) * s->pitch, (size_t)w * 4);
   for (int y = y0; y < y1; y++)
   {
      u32 *row = s->p + y * s->pitch, *dn = row + s->pitch;
      u32 left = row[0];
      for (int x = 1; x < w - 1; x++)
      {
         u32 c = row[x], r = row[x + 1], u = prev[x], d = dn[x];
         int lc = luma(c);
         int e = lc - luma(left); if (e < 0) e = -e;
         int e2 = lc - luma(r); if (e2 < 0) e2 = -e2; if (e2 > e) e = e2;
         e2 = lc - luma(u); if (e2 < 0) e2 = -e2; if (e2 > e) e = e2;
         e2 = lc - luma(d); if (e2 < 0) e2 = -e2; if (e2 > e) e = e2;
         prev[x - 1] = left;
         left = c;
         if (e > 26)
         {
            u32 h = col_avg(col_avg(left, r), col_avg(u, d));
            row[x] = col_lerp(c, h, e > 90 ? 168 : 110);
         }
      }
      prev[w - 2] = left;
      prev[w - 1] = row[w - 1];
   }
}

// Expand a low-resolution grid (lw x lh cells, each bx x by output pixels) to the scene buffer
// with bilinear filtering. Cell centres sit at the middle of each block.
typedef struct { const u32 *lo; int lw, lh, bx, by; } UpCtx;

static void upsample_slice(void *vc, int job, int njobs)
{
   const UpCtx *c = vc;
   int y0, y1;
   par_range(job, njobs, g_sh, &y0, &y1);
   if (y0 >= y1) return;
   const int W = g_sw;
   int fx0[SCN_W], fw[SCN_W];
   for (int x = 0; x < W; x++)
   {
      int p = (2 * x + 1 - c->bx) * 128 / c->bx;   // (x + 0.5)/bx - 0.5 in 1/256 units
      int i = p >> 8;
      fw[x] = p & 255;
      fx0[x] = i;
   }
   for (int y = y0; y < y1; y++)
   {
      int p = (2 * y + 1 - c->by) * 128 / c->by;
      int j = p >> 8, wy = p & 255;
      int ja = j < 0 ? 0 : (j >= c->lh ? c->lh - 1 : j);
      int jb = j + 1 < 0 ? 0 : (j + 1 >= c->lh ? c->lh - 1 : j + 1);
      const u32 *ra = c->lo + ja * c->lw, *rb = c->lo + jb * c->lw;
      u32 *out = S_SCN.p + y * W;
      for (int x = 0; x < W; x++)
      {
         int i = fx0[x];
         int ia = i < 0 ? 0 : (i >= c->lw ? c->lw - 1 : i);
         int ib = i + 1 < 0 ? 0 : (i + 1 >= c->lw ? c->lw - 1 : i + 1);
         u32 t0 = col_lerp(ra[ia], ra[ib], fw[x]);
         u32 t1 = col_lerp(rb[ia], rb[ib], fw[x]);
         out[x] = col_lerp(t0, t1, wy);
      }
   }
   DCFlushRange(S_SCN.p + y0 * W, (uint32_t)(y1 - y0) * (uint32_t)W * 4);
}

void gfx_upsample(const u32 *lo, int lw, int lh, int bx, int by)
{
   UpCtx c = { lo, lw, lh, bx, by };
   par_run(upsample_slice, &c);
   par_consume(S_SCN.p, (size_t)g_sw * (size_t)g_sh * 4);
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

// Text at scale 1 is drawn pixel-exact. From scale 2 up each glyph is smoothed: the 5x7 bitmap is
// sampled bilinearly and the result is pushed through a steep ramp, which rounds corners and
// anti-aliases diagonals without ever leaving the glyph's own footprint.
static void glyph_smooth(Surf *s, int x, int y, int sc, u32 c, const u8 *g)
{
   int bit[9][7];   // [row+1][col+1], padded with an empty border
   for (int r = 0; r < 9; r++)
      for (int cc = 0; cc < 7; cc++)
         bit[r][cc] = (r >= 1 && r <= 7 && cc >= 1 && cc <= 5 && (g[r - 1] & (0x10 >> (cc - 1)))) ? 256 : 0;
   int wt[16], base[16];
   for (int p = 0; p < sc && p < 16; p++)
   {
      int t = ((2 * p + 1) * 256) / (2 * sc);   // sample position inside the source pixel, 0..255
      if (t >= 128) { base[p] = 0; wt[p] = t - 128; }
      else { base[p] = -1; wt[p] = t + 128; }
   }
   if (sc > 16) sc = 16;
   for (int j = 0; j < 7; j++)
      for (int py = 0; py < sc; py++)
      {
         int oy = y + j * sc + py;
         if ((unsigned)oy >= (unsigned)s->h) continue;
         int ry = j + 1 + base[py], wy = wt[py];
         u32 *row = s->p + oy * s->pitch;
         for (int i = 0; i < 5; i++)
            for (int px = 0; px < sc; px++)
            {
               int ox = x + i * sc + px;
               if ((unsigned)ox >= (unsigned)s->w) continue;
               int cx = i + 1 + base[px], wx = wt[px];
               int top = (bit[ry][cx] * (256 - wx) + bit[ry][cx + 1] * wx) >> 8;
               int bot = (bit[ry + 1][cx] * (256 - wx) + bit[ry + 1][cx + 1] * wx) >> 8;
               int v = (top * (256 - wy) + bot * wy) >> 8;
               int a = 128 + (v - 128) * 3;
               if (a <= 8) continue;
               if (a >= 248) row[ox] = c;
               else row[ox] = col_lerp(row[ox], c, a);
            }
      }
}

void s_text(Surf *s, int x, int y, int scale, u32 c, const char *str)
{
   if (!s_font_ready) font_init();
   if (y + 7 * scale < 0 || y >= s->h) return;
   for (; *str; str++)
   {
      unsigned ch = (unsigned char)*str;
      const u8 *g = ch < 128 ? s_glyph_lut[ch] : 0;
      if (g && x + 6 * scale > 0 && x < s->w)
      {
         if (scale >= 2)
            glyph_smooth(s, x, y, scale, c, g);
         else
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
