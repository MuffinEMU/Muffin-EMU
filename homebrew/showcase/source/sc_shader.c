// Scene 3: fragment-shader showpiece. GX2 shaders need a shader compiler that is not part of this
// build, so these "shaders" run on the PPC cores: each effect is a per-pixel function evaluated on
// a grid (320x180, or 213x120 for the raymarcher, at full quality) by all three cores, then
// expanded to the 640x360 scene buffer with bilinear filtering. Domain-warped plasma fractal, a
// polar-coordinate tunnel, lit 3D metaballs, and a sphere-tracing raymarcher over an infinite
// lattice with soft shadows, ambient occlusion, specular highlights, sky reflection and fog.
#include "showcase.h"

#define IMG_X 107
#define IMG_Y 14

static u32 pal[3][256];
static int pal_ready;
static int mode, pal_sel;
static float mode_t;
static const char *kNames[4] = { "PLASMA FRACTAL", "TUNNEL", "LIT METABALLS", "RAYMARCHER" };

static u32 lo[(SCN_W / 2) * (SCN_H / 2)] __attribute__((aligned(32)));
static float tun_ang[(SCN_W / 2) * (SCN_H / 2)], tun_dep[(SCN_W / 2) * (SCN_H / 2)];
static int tun_cols, tun_rows;

typedef struct { int cols, rows, pal_sel; float t; } FxCtx;

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

static int grid_b(void)
{
   if (mode == 3) return g_sw >= 320 ? 3 : 2;
   return g_sw >= 320 ? 2 : 1;
}

static inline float rsqf(float x)
{
   u32 i;
   float y;
   __builtin_memcpy(&i, &x, 4);
   i = 0x5f3759dfu - (i >> 1);
   __builtin_memcpy(&y, &i, 4);
   y = y * (1.5f - 0.5f * x * y * y);
   return y * (1.5f - 0.5f * x * y * y);
}

// ------------------------------------------------------------------ effects (each handles rows)

static void fx_plasma(const FxCtx *c, int r0, int r1)
{
   const u32 *pl = pal[c->pal_sel];
   const int cols = c->cols, rows = c->rows;
   const float t = c->t;
   for (int j = r0; j < r1; j++)
      for (int i = 0; i < cols; i++)
      {
         float u = (((float)i + 0.5f) / (float)cols - 0.5f) * 7.0f, v = (((float)j + 0.5f) / (float)rows - 0.5f) * 4.0f;
         float wx = u + 1.2f * m_sin(v * 1.3f + t * 0.9f), wy = v + 1.2f * m_cos(u * 1.1f - t * 0.7f);
         float w2x = wx + 0.8f * m_sin(wy * 2.1f + t * 1.3f), w2y = wy + 0.8f * m_sin(wx * 1.7f - t * 1.1f);
         float w3x = w2x + 0.5f * m_sin(w2y * 3.1f - t * 0.6f), w3y = w2y + 0.5f * m_cos(w2x * 2.7f + t * 0.8f);
         float val = m_sin(w3x * 1.5f + t) + m_sin(w3y * 1.9f - t * 0.8f) +
                     m_sin(m_sqrt(w3x * w3x + w3y * w3y) * 2.3f - t * 1.5f);
         float f = (val * 0.16f + 0.5f) * 255.0f + t * 18.0f;
         int i0 = (int)f;
         u32 a = pl[i0 & 255], b = pl[(i0 + 1) & 255];
         u32 col = col_lerp(a, b, (int)((f - (float)i0) * 256.0f));
         // Soft vignette-like depth: darker where the warp is steep.
         lo[j * cols + i] = col;
      }
}

static void fx_tunnel(const FxCtx *c, int r0, int r1)
{
   const u32 *pl = pal[c->pal_sel];
   const int cols = c->cols;
   const float t = c->t;
   for (int j = r0; j < r1; j++)
      for (int i = 0; i < cols; i++)
      {
         float a = tun_ang[j * cols + i], d = tun_dep[j * cols + i];
         int iu = (int)((a + d * 0.12f + t * 0.06f + 4.0f) * 48.0f);
         int iv = (int)((d + t * 0.8f) * 40.0f);
         int idx = ((iu * 5) ^ iv) & 255;
         int fade = (int)(m_clamp(1.0f / (d + 0.15f) * 0.9f, 0.0f, 1.0f) * 256.0f);
         lo[j * cols + i] = col_scale(pl[(idx + (int)(t * 40.0f)) & 255], fade);
      }
}

static void fx_meta(const FxCtx *c, int r0, int r1)
{
   const u32 *pl = pal[c->pal_sel];
   const int cols = c->cols, rows = c->rows;
   const float t = c->t;
   float bx[6], by[6], br[6];
   for (int k = 0; k < 6; k++)
   {
      float fk = (float)k;
      bx[k] = m_sin(t * (0.6f + fk * 0.17f) + fk * 2.1f) * 0.95f * ((float)cols / (float)rows) * 0.8f;
      by[k] = m_cos(t * (0.5f + fk * 0.13f) + fk * 1.3f) * 0.7f;
      br[k] = 0.045f + 0.012f * fk;
   }
   const float lx = -0.45f, ly = -0.55f, lz = 0.70f;   // light direction (towards the light)
   for (int j = r0; j < r1; j++)
      for (int i = 0; i < cols; i++)
      {
         float x = (((float)i + 0.5f) - (float)cols * 0.5f) / ((float)rows * 0.5f);
         float y = (((float)j + 0.5f) - (float)rows * 0.5f) / ((float)rows * 0.5f);
         float f = 0.0f, gx = 0.0f, gy = 0.0f;
         for (int k = 0; k < 6; k++)
         {
            float dx = x - bx[k], dy = y - by[k];
            float q = 1.0f / (dx * dx + dy * dy + 0.0008f);
            float w = br[k] * q;
            f += w;
            gx += w * q * dx;
            gy += w * q * dy;
         }
         u32 col;
         if (f < 1.0f)
         {
            int idx = (int)(f * f * 90.0f);
            col = pl[(idx + (int)(t * 10.0f)) & 255];
            // Faint aura outside the surface.
            col = col_scale(col, 120 + (int)(f * 120.0f));
         }
         else
         {
            // Inside the iso-surface the blob is a dome: height from the field value, tilt away
            // from the blob centres.
            float gl = rsqf(gx * gx + gy * gy + 1e-12f);
            float inv_sf = rsqf(f);                       // 1/sqrt(f)
            float Nz = m_sqrt(1.0f - inv_sf * inv_sf);
            float Nx = gx * gl * inv_sf, Ny = gy * gl * inv_sf;   // gx, gy accumulate +dx, so they point outward
            float d = Nx * lx + Ny * ly + Nz * lz;
            if (d < 0.0f) d = 0.0f;
            float h = lx, hy = ly, hz = lz + 1.0f;
            float hl = rsqf(h * h + hy * hy + hz * hz);
            float nh = (Nx * h + Ny * hy + Nz * hz) * hl;
            if (nh < 0.0f) nh = 0.0f;
            float sp = nh * nh; sp *= sp; sp *= sp; sp *= sp; sp *= sp;
            int idx = 110 + (int)m_clamp((f - 1.0f) * 55.0f, 0.0f, 145.0f);
            col = pl[(idx + (int)(t * 10.0f)) & 255];
            col = col_scale(col, (int)((0.30f + 0.85f * d) * 256.0f));
            int spv = (int)(sp * 230.0f);
            col = col_add(col, RGB(spv, spv, spv));
            float rim = 1.0f - Nz;
            int rv = (int)(rim * rim * 120.0f);
            col = col_add(col, RGB(rv / 2, rv / 2, rv));
         }
         lo[j * cols + i] = col;
      }
}

static float lattice(float v) { return v - 4.0f * (float)m_floor(v * 0.25f + 0.5f); }

static inline float sdf(float px, float py, float pz)
{
   float qx = lattice(px), qz = lattice(pz), ey = py - 1.5f;
   float sd = m_sqrt(qx * qx + ey * ey + qz * qz) - 1.0f;
   return py < sd ? py : sd;
}

static void fx_march(const FxCtx *c, int r0, int r1)
{
   const int cols = c->cols, rows = c->rows;
   const float t = c->t;
   float ox = 1.2f * m_sin(t * 0.37f), oy = 1.5f + 0.5f * m_sin(t * 0.5f), oz = t * 2.6f;
   float yaw = 0.35f * m_sin(t * 0.23f);
   float cyw = m_cos(yaw), syw = m_sin(yaw);
   const float lx = 0.53f, ly = 0.78f, lz = -0.33f;
   const u32 *pl = pal[c->pal_sel];
   for (int j = r0; j < r1; j++)
      for (int i = 0; i < cols; i++)
      {
         float u = (((float)i + 0.5f) - (float)cols * 0.5f) / ((float)rows * 0.5f);
         float v = -(((float)j + 0.5f) - (float)rows * 0.5f) / ((float)rows * 0.5f);
         float il = rsqf(u * u + v * v + 1.69f);
         float dx = u * il, dy = v * il, dz = 1.3f * il;
         float rx = dx * cyw + dz * syw, rz = -dx * syw + dz * cyw;
         float tt = 0.2f;
         int hit = 0;
         float px = 0, py = 0, pz = 0, qx = 0, qz = 0, sd = 0;
         for (int s = 0; s < 30; s++)
         {
            px = ox + rx * tt; py = oy + dy * tt; pz = oz + rz * tt;
            qx = lattice(px); qz = lattice(pz);
            float ey = py - 1.5f;
            float sl = m_sqrt(qx * qx + ey * ey + qz * qz);
            sd = sl - 1.0f;
            float d = py < sd ? py : sd;
            if (d < 0.02f) { hit = (py <= sd) ? 1 : 2; break; }
            tt += d;
            if (tt > 40.0f) break;
         }
         int sky_t = (int)(m_clamp(0.5f + dy * 1.2f, 0.0f, 1.0f) * 255.0f);
         u32 skyc = col_mix(RGB(240, 140, 90), RGB(30, 40, 120), sky_t);
         u32 col;
         if (!hit) col = skyc;
         else
         {
            float nx, ny, nz;
            u32 base;
            if (hit == 1)
            {
               nx = 0; ny = 1; nz = 0;
               int chk = (m_floor(px) + m_floor(pz)) & 1;
               base = chk ? RGB(78, 66, 130) : RGB(30, 28, 74);
            }
            else
            {
               float ey = py - 1.5f;
               float il2 = rsqf(qx * qx + ey * ey + qz * qz + 1e-6f);
               nx = qx * il2; ny = ey * il2; nz = qz * il2;
               int cell = hash2(m_floor(px * 0.25f + 0.5f), m_floor(pz * 0.25f + 0.5f)) & 255;
               base = pl[cell];
            }
            // Soft shadow towards the light.
            float sh = 1.0f, st = 0.06f;
            for (int k = 0; k < 9; k++)
            {
               float d = sdf(px + lx * st, py + ly * st, pz + lz * st);
               float q = 7.0f * d / st;
               if (q < sh) sh = q;
               st += d < 0.05f ? 0.05f : (d > 0.7f ? 0.7f : d);
               if (sh < 0.02f) break;
            }
            if (sh < 0.0f) sh = 0.0f;
            // Ambient occlusion from two probes along the normal.
            float ao = 1.0f;
            {
               float d1 = sdf(px + nx * 0.18f, py + ny * 0.18f, pz + nz * 0.18f);
               float d2 = sdf(px + nx * 0.5f, py + ny * 0.5f, pz + nz * 0.5f);
               ao = 0.3f + 0.7f * m_clamp((d1 / 0.18f) * 0.45f + (d2 / 0.5f) * 0.55f, 0.0f, 1.0f);
            }
            float diff = nx * lx + ny * ly + nz * lz;
            if (diff < 0.0f) diff = 0.0f;
            float vl = rsqf(rx * rx + dy * dy + rz * rz);
            float vx = -rx * vl, vy = -dy * vl, vz = -rz * vl;
            float hx = lx + vx, hy = ly + vy, hz = lz + vz;
            float hl = rsqf(hx * hx + hy * hy + hz * hz);
            float nh = (nx * hx + ny * hy + nz * hz) * hl;
            if (nh < 0.0f) nh = 0.0f;
            float sp = nh * nh; sp *= sp; sp *= sp; sp *= sp; sp *= sp;
            float lit = (0.22f + 0.95f * diff * sh) * ao;
            int k = (int)(lit * 256.0f);
            col = col_scale(base, k > 340 ? 340 : k);
            int spv = (int)(sp * 200.0f * sh * (hit == 2 ? 1.0f : 0.35f));
            col = col_add(col, RGB(spv, spv * 9 / 10, spv * 8 / 10));
            // Sky reflection, stronger at grazing angles.
            float fr = 1.0f - (nx * vx + ny * vy + nz * vz);
            if (fr < 0.0f) fr = 0.0f;
            float f2 = fr * fr;
            col = col_lerp(col, skyc, (int)(f2 * f2 * 90.0f));
            float fog = m_clamp(tt * (1.0f / 38.0f), 0.0f, 1.0f);
            col = col_mix(col, RGB(220, 128, 92), (int)(fog * fog * 256.0f));
         }
         lo[j * cols + i] = col;
      }
}

static void fx_job(void *vc, int job, int njobs)
{
   const FxCtx *c = vc;
   int r0, r1;
   par_range(job, njobs, c->rows, &r0, &r1);
   if (r0 >= r1) return;
   switch (mode)
   {
   case 0: fx_plasma(c, r0, r1); break;
   case 1: fx_tunnel(c, r0, r1); break;
   case 2: fx_meta(c, r0, r1); break;
   default: fx_march(c, r0, r1); break;
   }
   par_flush(lo + r0 * c->cols, (size_t)(r1 - r0) * (size_t)c->cols * 4);
}

static void render(void)
{
   const int B = grid_b();
   FxCtx c;
   c.cols = (g_sw + B - 1) / B;
   c.rows = (g_sh + B - 1) / B;
   c.pal_sel = pal_sel;
   c.t = g_time;
   if (mode == 1 && (c.cols != tun_cols || c.rows != tun_rows))
   {
      tun_cols = c.cols; tun_rows = c.rows;
      for (int j = 0; j < c.rows; j++)
         for (int i = 0; i < c.cols; i++)
         {
            float xx = ((float)i + 0.5f - (float)c.cols * 0.5f) / ((float)c.rows * 0.5f);
            float yy = ((float)j + 0.5f - (float)c.rows * 0.5f) / ((float)c.rows * 0.5f);
            float r = m_sqrt(xx * xx + yy * yy) + 0.001f;
            tun_ang[j * c.cols + i] = m_atan2(yy, xx) * (1.0f / TAU_F);
            tun_dep[j * c.cols + i] = 0.35f / r;
         }
      par_publish(tun_ang, sizeof(tun_ang));
      par_publish(tun_dep, sizeof(tun_dep));
   }
   par_publish(pal, sizeof(pal));
   par_publish(&c, sizeof(c));
   par_run(fx_job, &c);
   gfx_upsample(lo, c.cols, c.rows, B, B);
}

static void hud(void)
{
   int B = grid_b();
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
      "f = sum r_i / (|p - c_i|^2 + e);  n = grad f",
      "d = min(p.y, |lattice(p) - c| - 1); shadow, ao" };
   s_text(&S_DRC, 107, 444, 2, COL_GREEN, src[mode]);
}

const Scene sc_shader = {
   "SHADER LAB", "PLASMA, TUNNEL, LIT METABALLS, SHADOWED RAYMARCHER", 3, enter, update, render, hud, drc
};
