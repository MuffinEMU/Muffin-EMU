// Scene 3: fragment-shader showpiece. GX2 shaders need a shader compiler that is not part of this
// build, so these "shaders" run on the PPC cores: each effect is a per-pixel function evaluated at
// reduced resolution and block-replicated. Domain-warped plasma fractal, a polar-coordinate tunnel,
// metaballs, and a real sphere-tracing raymarcher over an infinite lattice.
#include "showcase.h"

#define IMG_X 107
#define IMG_Y 14

static u32 pal[3][256];
static int pal_ready;
static int mode, pal_sel;
static float mode_t;
static const char *kNames[4] = { "PLASMA FRACTAL", "TUNNEL", "METABALLS", "RAYMARCHER" };

static float tun_ang[160 * 90], tun_dep[160 * 90];
static int tun_cols, tun_rows;

static void make_pal(void)
{
   for (int i = 0; i < 256; i++)
   {
      float f = (float)i / 256.0f;
      pal[0][i] = RGB(128 + (int)(127 * m_sin(TAU_F * f)), 128 + (int)(127 * m_sin(TAU_F * (f + 0.33f))),
                      128 + (int)(127 * m_sin(TAU_F * (f + 0.67f))));
      float fr = f * 3.0f;
      int r = (int)(m_clamp(fr, 0, 1) * 255), g = (int)(m_clamp(fr - 1.0f, 0, 1) * 255),
          b = (int)(m_clamp(fr - 2.0f, 0, 1) * 255);
      pal[1][i] = RGB(r, g, b);
      pal[2][i] = RGB((int)(m_clamp(90.0f + 100.0f * m_sin(TAU_F * (f * 2.0f + 0.1f)), 0, 255)),
                      (int)(m_clamp(70.0f + 70.0f * m_sin(TAU_F * (f * 2.0f + 0.45f)), 0, 255)),
                      (int)(m_clamp(150.0f + 105.0f * m_sin(TAU_F * (f * 1.0f + 0.2f)), 0, 255)));
   }
   pal_ready = 1;
}

static void enter(void)
{
   if (!pal_ready) make_pal();
   mode_t = 0;
   g_audio_track_override = -1;
}

static void update(const Input *in, float dt, int demo)
{
   mode_t += dt;
   if (in->trig & B_X) mode = (mode + 1) & 3;
   if (in->trig & B_A) pal_sel = (pal_sel + 1) % 3;
   if (demo) mode = ((int)(mode_t / 3.4f)) & 3;
   if (in->touch_trig && in->ty > 390.0f && in->ty < 450.0f)
   {
      int b = (int)((in->tx - 107.0f) / 160.0f);
      if (b >= 0 && b < 4) mode = b;
   }
}

static inline void block(int x, int y, int b, u32 c)
{
   int w = g_sw, h = g_sh;
   for (int j = 0; j < b; j++)
   {
      if (y + j >= h) break;
      u32 *p = S_SCN.p + (y + j) * w + x;
      for (int i = 0; i < b && x + i < w; i++) p[i] = c;
   }
}

static void fx_plasma(int B, int cols, int rows)
{
   const u32 *pl = pal[pal_sel];
   float t = g_time;
   for (int j = 0; j < rows; j++)
      for (int i = 0; i < cols; i++)
      {
         float u = ((float)i / (float)cols - 0.5f) * 7.0f, v = ((float)j / (float)rows - 0.5f) * 4.0f;
         float wx = u + 1.2f * m_sin(v * 1.3f + t * 0.9f), wy = v + 1.2f * m_cos(u * 1.1f - t * 0.7f);
         float w2x = wx + 0.8f * m_sin(wy * 2.1f + t * 1.3f), w2y = wy + 0.8f * m_sin(wx * 1.7f - t * 1.1f);
         float val = m_sin(w2x * 1.5f + t) + m_sin(w2y * 1.9f - t * 0.8f) +
                     m_sin(m_sqrt(w2x * w2x + w2y * w2y) * 2.3f - t * 1.5f);
         int idx = ((int)((val * 0.16f + 0.5f) * 255.0f) + (int)(t * 18.0f)) & 255;
         block(i * B, j * B, B, pl[idx]);
      }
}

static void fx_tunnel(int B, int cols, int rows)
{
   if (cols != tun_cols || rows != tun_rows)
   {
      tun_cols = cols; tun_rows = rows;
      for (int j = 0; j < rows; j++)
         for (int i = 0; i < cols; i++)
         {
            float xx = ((float)i + 0.5f - (float)cols * 0.5f) / ((float)rows * 0.5f);
            float yy = ((float)j + 0.5f - (float)rows * 0.5f) / ((float)rows * 0.5f);
            float r = m_sqrt(xx * xx + yy * yy) + 0.001f;
            tun_ang[j * cols + i] = m_atan2(yy, xx) * (1.0f / TAU_F);
            tun_dep[j * cols + i] = 0.35f / r;
         }
   }
   const u32 *pl = pal[pal_sel];
   float t = g_time;
   for (int j = 0; j < rows; j++)
      for (int i = 0; i < cols; i++)
      {
         float a = tun_ang[j * cols + i], d = tun_dep[j * cols + i];
         int iu = (int)((a + d * 0.12f + t * 0.06f + 4.0f) * 48.0f);
         int iv = (int)((d + t * 0.8f) * 40.0f);
         int idx = ((iu * 5) ^ iv) & 255;
         int fade = (int)(m_clamp(1.0f / (d + 0.15f) * 0.9f, 0.0f, 1.0f) * 256.0f);
         u32 c = col_scale(pl[(idx + (int)(t * 40.0f)) & 255], fade);
         block(i * B, j * B, B, c);
      }
}

static void fx_meta(int B, int cols, int rows)
{
   const u32 *pl = pal[pal_sel];
   float t = g_time;
   float bx[6], by[6], br[6];
   for (int k = 0; k < 6; k++)
   {
      float fk = (float)k;
      bx[k] = m_sin(t * (0.6f + fk * 0.17f) + fk * 2.1f) * 0.95f * ((float)cols / (float)rows) * 0.8f;
      by[k] = m_cos(t * (0.5f + fk * 0.13f) + fk * 1.3f) * 0.7f;
      br[k] = 0.045f + 0.012f * fk;
   }
   for (int j = 0; j < rows; j++)
      for (int i = 0; i < cols; i++)
      {
         float x = ((float)i - (float)cols * 0.5f) / ((float)rows * 0.5f);
         float y = ((float)j - (float)rows * 0.5f) / ((float)rows * 0.5f);
         float f = 0.0f;
         for (int k = 0; k < 6; k++)
         {
            float dx = x - bx[k], dy = y - by[k];
            f += br[k] / (dx * dx + dy * dy + 0.0008f);
         }
         int idx;
         if (f < 1.0f) idx = (int)(f * f * 90.0f);
         else idx = 110 + (int)m_clamp((f - 1.0f) * 55.0f, 0.0f, 145.0f);
         block(i * B, j * B, B, pl[(idx + (int)(t * 10.0f)) & 255]);
      }
}

static float lattice(float v) { return v - 4.0f * (float)m_floor(v * 0.25f + 0.5f); }

static void fx_march(int B, int cols, int rows)
{
   float t = g_time;
   float ox = 1.2f * m_sin(t * 0.37f), oy = 1.5f + 0.5f * m_sin(t * 0.5f), oz = t * 2.6f;
   float yaw = 0.35f * m_sin(t * 0.23f);
   float cyw = m_cos(yaw), syw = m_sin(yaw);
   const float lx = 0.53f, ly = 0.78f, lz = -0.33f;
   for (int j = 0; j < rows; j++)
      for (int i = 0; i < cols; i++)
      {
         float u = ((float)i - (float)cols * 0.5f) / ((float)rows * 0.5f);
         float v = -((float)j - (float)rows * 0.5f) / ((float)rows * 0.5f);
         float il = 1.0f / m_sqrt(u * u + v * v + 1.69f);
         float dx = u * il, dy = v * il, dz = 1.3f * il;
         float rx = dx * cyw + dz * syw, rz = -dx * syw + dz * cyw;
         float tt = 0.2f;
         int hit = 0;
         float px = 0, py = 0, pz = 0, qx = 0, qz = 0, sd = 0;
         for (int s = 0; s < 26; s++)
         {
            px = ox + rx * tt; py = oy + dy * tt; pz = oz + rz * tt;
            qx = lattice(px); qz = lattice(pz);
            float ey = py - 1.5f;
            float sl = m_sqrt(qx * qx + ey * ey + qz * qz);
            sd = sl - 1.0f;
            float d = py < sd ? py : sd;
            if (d < 0.03f) { hit = (py <= sd) ? 1 : 2; break; }
            tt += d;
            if (tt > 40.0f) break;
         }
         u32 c;
         if (!hit)
         {
            int h = (int)(m_clamp(0.5f + dy * 1.2f, 0.0f, 1.0f) * 255.0f);
            c = col_mix(RGB(240, 140, 90), RGB(30, 40, 120), h);
         }
         else
         {
            float nx, ny, nz;
            u32 base;
            if (hit == 1)
            {
               nx = 0; ny = 1; nz = 0;
               int chk = (m_floor(px) + m_floor(pz)) & 1;
               base = chk ? RGB(70, 60, 120) : RGB(30, 28, 70);
            }
            else
            {
               float ey = py - 1.5f;
               float il2 = 1.0f / (m_sqrt(qx * qx + ey * ey + qz * qz) + 0.0001f);
               nx = qx * il2; ny = ey * il2; nz = qz * il2;
               int cell = hash2(m_floor(px * 0.25f + 0.5f), m_floor(pz * 0.25f + 0.5f)) & 255;
               base = pal[pal_sel][cell];
            }
            float diff = nx * lx + ny * ly + nz * lz;
            if (diff < 0.0f) diff = 0.0f;
            int k = (int)((0.25f + 0.85f * diff) * 256.0f);
            c = col_scale(base, k > 300 ? 300 : k);
            float fog = m_clamp(tt * (1.0f / 38.0f), 0.0f, 1.0f);
            c = col_mix(c, RGB(200, 120, 90), (int)(fog * fog * 256.0f));
         }
         block(i * B, j * B, B, c);
      }
}

static void render(void)
{
   int B = (mode == 3) ? 3 : 2;
   int cols = (g_sw + B - 1) / B, rows = (g_sh + B - 1) / B;
   switch (mode)
   {
   case 0: fx_plasma(B, cols, rows); break;
   case 1: fx_tunnel(B, cols, rows); break;
   case 2: fx_meta(B, cols, rows); break;
   default: fx_march(B, cols, rows); break;
   }
}

static void hud(void)
{
   int B = (mode == 3) ? 3 : 2;
   s_panel(&S_TV, 24, TV_H - 84, 470, 60, COL_CYAN);
   s_textf(&S_TV, 38, TV_H - 74, 2, COL_WHITE, "%s", kNames[mode]);
   s_textf(&S_TV, 38, TV_H - 52, 2, COL_ACCENT, "%dX%d PIXELS  X MODE  A PALETTE", (g_sw + B - 1) / B, (g_sh + B - 1) / B);
}

static void drc(const Input *in)
{
   (void)in;
   s_vgrad(&S_DRC, 0, 0, DRC_W, DRC_H, RGB(14, 12, 34), RGB(6, 6, 18));
   gfx_blit_scene_drc(IMG_X, IMG_Y);
   s_box_outline(&S_DRC, IMG_X - 1, IMG_Y - 1, 642, 362, COL_CYAN);
   for (int b = 0; b < 4; b++)
   {
      int x = 107 + b * 160;
      int on = (b == mode);
      s_rect(&S_DRC, x, 392, 152, 38, on ? COL_ACCENT : COL_PANEL);
      s_box_outline(&S_DRC, x, 392, 152, 38, on ? COL_WHITE : COL_DIM);
      static const char *shortn[4] = { "PLASMA", "TUNNEL", "BLOBS", "MARCH" };
      s_text_sh(&S_DRC, x + (152 - text_w(shortn[b], 2)) / 2, 403, 2, on ? RGB(30, 20, 10) : COL_WHITE, shortn[b]);
   }
   static const char *src[4] = {
      "v = sin(w.x+t) + sin(w.y*1.9-t) + sin(|w|*2.3-t)",
      "c = xor(atan(p)*48, 0.35/|p| + t) * fade",
      "f = sum r_i / (|p - c_i|^2 + e)",
      "d = min(p.y, |lattice(p) - c| - 1)" };
   s_text(&S_DRC, 107, 444, 2, COL_GREEN, src[mode]);
}

const Scene sc_shader = {
   "SHADER LAB", "FRAGMENT-SHADER STYLE EFFECTS: PLASMA, TUNNEL, METABALLS, RAYMARCHER", 3, enter, update, render, hud, drc
};
