// Scene 1: procedural voxel landscape. A 256x256 wrapping fBm heightmap is generated in the
// background while the title card shows, then rendered with a front-to-back column raycaster:
// perspective projection, distance fog, slope lighting baked into the colour map, animated water,
// and a full day/night cycle that drives the sky gradient, sun, moon, stars, light and fog colour.
#include "showcase.h"
#include <string.h>

#define HM 256
#define WATER 58
#define DIST 250.0f

static u8 hmap[HM * HM];
static u32 cmap[HM * HM];
static int s_gen;                 // 0..511
static float cx = 128.0f, cy = 128.0f, cam_h = 60.0f, yaw = 0.7f, pitch = 0.0f, lift = 22.0f;
static float tod = 1.25f, tod_speed = 0.10f;
static int tod_auto = 1;
static float speed_now;

static float vnoise(float x, float y, int mask, u32 seed)
{
   int xi = m_floor(x), yi = m_floor(y);
   float fx = x - (float)xi, fy = y - (float)yi;
   fx = fx * fx * (3.0f - 2.0f * fx);
   fy = fy * fy * (3.0f - 2.0f * fy);
   float a = (float)((hash2(xi & mask, yi & mask) ^ seed) & 1023u);
   float b = (float)((hash2((xi + 1) & mask, yi & mask) ^ seed) & 1023u);
   float c = (float)((hash2(xi & mask, (yi + 1) & mask) ^ seed) & 1023u);
   float d = (float)((hash2((xi + 1) & mask, (yi + 1) & mask) ^ seed) & 1023u);
   float top = a + (b - a) * fx, bot = c + (d - c) * fx;
   return (top + (bot - top) * fy) * (1.0f / 1023.0f);
}

int terrain_ready(void) { return s_gen >= 512; }

void terrain_gen_step(int rows)
{
   while (rows-- > 0 && s_gen < 512)
   {
      if (s_gen < 256)
      {
         int y = s_gen;
         for (int x = 0; x < HM; x++)
         {
            float sum = 0.0f, amp = 1.0f, norm = 0.0f;
            int cell = 64;
            for (int o = 0; o < 5; o++)
            {
               sum += amp * vnoise((float)x / (float)cell, (float)y / (float)cell, HM / cell - 1, 0x5A5Au * (u32)(o + 1));
               norm += amp;
               amp *= 0.5f;
               cell >>= 1;
            }
            float h = sum / norm;
            h = h * h * (3.0f - 2.0f * h);
            h = (h - 0.12f) / 0.76f;
            hmap[y * HM + x] = (u8)(m_clamp(h, 0.0f, 1.0f) * 255.0f);
         }
      }
      else
      {
         int y = s_gen - 256;
         for (int x = 0; x < HM; x++)
         {
            int v = hmap[y * HM + x];
            int hl = hmap[y * HM + ((x - 1) & 255)], hr = hmap[y * HM + ((x + 1) & 255)];
            int hu = hmap[((y - 1) & 255) * HM + x], hd = hmap[((y + 1) & 255) * HM + x];
            int slope = (hl - hr) * 3 + (hu - hd) * 2;
            int shade = 190 + slope;
            if (shade < 90) shade = 90;
            if (shade > 300) shade = 300;
            int var = (int)(hash2(x, y) & 15u) - 8;
            int r, g, b;
            if (v < WATER) { r = 20; g = 60 + v; b = 120 + v; shade = 256; }
            else if (v < WATER + 8) { r = 214; g = 196; b = 140; }
            else if (v < 135) { int t = (v - 66) * 255 / 70; r = 46 + t * 50 / 255; g = 104 + t * 46 / 255; b = 48 + t * 12 / 255; }
            else if (v < 185) { int t = (v - 135) * 255 / 50; r = 108 + t * 42 / 255; g = 98 + t * 40 / 255; b = 90 + t * 40 / 255; }
            else { r = 238; g = 242; b = 250; }
            r = (r + var) * shade >> 8; g = (g + var) * shade >> 8; b = (b + var) * shade >> 8;
            if (r > 255) r = 255;
            if (g > 255) g = 255;
            if (b > 255) b = 255;
            if (r < 0) r = 0;
            if (g < 0) g = 0;
            if (b < 0) b = 0;
            cmap[y * HM + x] = RGB(r, g, b);
         }
      }
      s_gen++;
   }
}

static void enter(void)
{
   if (!terrain_ready()) terrain_gen_step(512);
   g_audio_track_override = -1;
}

static float ground_at(float x, float y)
{
   int h = hmap[(((int)y) & 255) * HM + (((int)x) & 255)];
   if (h < WATER) h = WATER;
   return (float)h * 0.55f;
}

static void update(const Input *in, float dt, int demo)
{
   float fwd = in->ly, str = in->lx, turn = in->rx, tilt = in->ry;
   float up = 0.0f;
   if (in->hold & (B_ZR | B_R)) up += 1.0f;
   if (in->hold & (B_ZL | B_L)) up -= 1.0f;
   if (demo)
   {
      fwd = 0.85f;
      str = 0.0f;
      turn = 0.16f + 0.35f * m_sin(g_time * 0.35f);
      tilt = (0.05f - pitch) * 1.2f;
      lift += (22.0f + 14.0f * m_sin(g_time * 0.5f) - lift) * dt;
   }
   if (in->trig & B_X) tod_auto = !tod_auto;
   float boost = (in->hold & B_A) ? 3.0f : 1.0f;
   speed_now = 38.0f * boost;
   float cs = m_cos(yaw), sn = m_sin(yaw);
   cx += (cs * fwd - sn * str) * speed_now * dt;
   cy += (sn * fwd + cs * str) * speed_now * dt;
   if (cx < 0) cx += 256; if (cx >= 256) cx -= 256;
   if (cy < 0) cy += 256; if (cy >= 256) cy -= 256;
   yaw += turn * 1.7f * dt;
   pitch = m_clamp(pitch + tilt * 0.9f * dt, -0.45f, 0.45f);
   lift = m_clamp(lift + up * 45.0f * dt, 6.0f, 120.0f);
   float target = ground_at(cx, cy) + lift;
   cam_h += (target - cam_h) * m_clamp(dt * 3.0f, 0.0f, 1.0f);

   if (in->hold & B_LEFT) tod -= 1.6f * dt;
   else if (in->hold & B_RIGHT) tod += 1.6f * dt;
   else if (tod_auto) tod += tod_speed * (demo ? 2.2f : 1.0f) * dt;
   if (tod > TAU_F) tod -= TAU_F;
   if (tod < 0) tod += TAU_F;
}

typedef struct { u32 zen, hor, fog; int lr, lg, lb; float day; float sunset; } Sky;

static Sky sky_now(void)
{
   Sky s;
   float se = m_sin(tod);
   float day = m_clamp((se + 0.18f) / 0.5f, 0.0f, 1.0f);
   float sunset = m_clamp(1.0f - m_abs(se) / 0.32f, 0.0f, 1.0f);
   u32 nz = RGB(6, 8, 30), nh = RGB(18, 22, 58);
   u32 dz = RGB(52, 112, 214), dh = RGB(168, 208, 246);
   u32 sh = RGB(255, 128, 66);
   s.zen = col_mix(nz, dz, (int)(day * 256));
   s.hor = col_mix(nh, dh, (int)(day * 256));
   s.hor = col_mix(s.hor, sh, (int)(sunset * 0.85f * 256));
   s.zen = col_mix(s.zen, RGB(70, 50, 120), (int)(sunset * 0.35f * 256));
   s.fog = s.hor;
   float amb = 0.16f + 0.84f * day;
   s.lr = (int)(256 * (amb * (1.0f + 0.25f * sunset) + 0.05f * (1 - day)));
   s.lg = (int)(256 * (amb * (1.0f - 0.05f * sunset) + 0.07f * (1 - day)));
   s.lb = (int)(256 * (amb * (1.0f - 0.25f * sunset) + 0.16f * (1 - day)));
   s.day = day; s.sunset = sunset;
   return s;
}

static void render(void)
{
   const int W = g_sw, H = g_sh;
   Sky sk = sky_now();
   int hor = (int)((float)H * (0.46f + pitch));
   if (hor < 4) hor = 4;
   if (hor > H - 4) hor = H - 4;

   for (int y = 0; y < hor; y++)
   {
      int t = y * 256 / hor;
      s_rect(&S_SCN, 0, y, W, 1, col_mix(sk.zen, sk.hor, (t * t) >> 8));
   }
   s_rect(&S_SCN, 0, hor, W, H - hor, sk.fog);

   // Stars fade in with the dark.
   if (sk.day < 0.6f)
   {
      int a = (int)((1.0f - sk.day / 0.6f) * 255);
      for (int i = 0; i < 70; i++)
      {
         u32 h = hash2(i, 77);
         float sa = (float)(h & 1023u) * (TAU_F / 1024.0f);
         float el = (float)((h >> 10) & 255u) / 255.0f;
         float da = sa - yaw;
         da -= TAU_F * (float)m_floor(da / TAU_F + 0.5f);
         int sx = W / 2 + (int)(da / 1.05f * (float)W);
         int sy = hor - 2 - (int)(el * (float)hor * 0.95f);
         if (sx < 0 || sx >= W || sy < 0) continue;
         int tw = 120 + (int)(135.0f * (0.5f + 0.5f * m_sin(g_time * 3.0f + (float)i)));
         u32 c = col_scale(COL_WHITE, a * tw >> 8);
         s_add_pixel(&S_SCN, sx, sy, c);
      }
   }

   // Sun and moon on the same arc, opposite phases.
   for (int body = 0; body < 2; body++)
   {
      float ang = body ? tod + PI_F : tod;
      float el = m_sin(ang);
      if (el < -0.08f) continue;
      float az = 1.1f + (body ? 0.0f : 0.0f) + m_cos(ang) * 0.9f;
      float da = az - yaw;
      da -= TAU_F * (float)m_floor(da / TAU_F + 0.5f);
      int px = W / 2 + (int)(da / 1.05f * (float)W);
      int py = hor - (int)(el * (float)hor * 0.92f);
      int r = body ? 5 : 8;
      if (g_sw < 200) r = r / 2 + 1;
      u32 core = body ? RGB(225, 230, 255) : RGB(255, 238, 190);
      u32 glow = body ? RGB(40, 50, 90) : RGB(120, 80, 30);
      for (int k = 3; k >= 1; k--)
         s_rect_a(&S_SCN, px - r * k, py - r * k, r * k * 2, r * k * 2, glow, 28);
      s_disc(&S_SCN, px, py, r, core);
   }

   // Column raycaster.
   const float K = (float)H * 0.95f;
   const float fov = 1.05f;
   const float ox = cx + 1024.0f, oy = cy + 1024.0f;
   for (int x = 0; x < W; x++)
   {
      float a = yaw + ((float)x / (float)W - 0.5f) * fov;
      float dx = m_cos(a), dy = m_sin(a);
      int ybuf = H;
      float z = 2.0f, dz = 0.55f;
      while (z < DIST && ybuf > 0)
      {
         float mxf = ox + dx * z, myf = oy + dy * z;
         int mi = ((int)mxf) & 255, mj = ((int)myf) & 255;
         int idx = mj * HM + mi;
         int hh = hmap[idx];
         int water = hh < WATER;
         if (water) hh = WATER;
         float sy = (float)hor + (cam_h - (float)hh * 0.55f) * K / z;
         int top = (int)sy;
         if (top < 0) top = 0;
         if (top < ybuf)
         {
            u32 c = cmap[idx];
            int r = (int)CR(c), g = (int)CG(c), b = (int)CB(c);
            if (water)
            {
               int sp = ((hash2(mi + (int)(g_time * 2.5f), mj + (int)(g_time * 1.7f)) & 31u) == 0) ? 70 : 0;
               r = 24 + sp; g = 70 + sp; b = 140 + sp;
            }
            r = r * sk.lr >> 8; g = g * sk.lg >> 8; b = b * sk.lb >> 8;
            float u = (z - 40.0f) * (1.0f / (DIST - 40.0f));
            int f = u > 0.0f ? (int)(u * u * 256.0f) : 0;
            if (f > 256) f = 256;
            if (f > 0)
            {
               r += ((int)CR(sk.fog) - r) * f >> 8;
               g += ((int)CG(sk.fog) - g) * f >> 8;
               b += ((int)CB(sk.fog) - b) * f >> 8;
            }
            if (r > 255) r = 255;
            if (g > 255) g = 255;
            if (b > 255) b = 255;
            u32 px = RGB(r, g, b);
            u32 *p = S_SCN.p + top * W + x;
            for (int y = top; y < ybuf; y++) { *p = px; p += W; }
            ybuf = top;
         }
         z += dz;
         dz *= 1.02f;
      }
   }
}

static const char *tod_name(void)
{
   float se = m_sin(tod);
   float ce = m_cos(tod);
   if (se > 0.35f) return "DAY";
   if (se > 0.0f) return ce > 0 ? "SUNRISE" : "SUNSET";
   if (se > -0.2f) return ce > 0 ? "DAWN" : "DUSK";
   return "NIGHT";
}

static void hud(void)
{
   s_panel(&S_TV, 24, TV_H - 84, 340, 60, COL_CYAN);
   s_textf(&S_TV, 38, TV_H - 74, 2, COL_WHITE, "ALT %3d  SPD %3d", (int)cam_h, (int)speed_now);
   s_textf(&S_TV, 38, TV_H - 52, 2, COL_ACCENT, "%s  %s", tod_name(), tod_auto ? "AUTO" : "HOLD");
}

static void drc(const Input *in)
{
   (void)in;
   s_vgrad(&S_DRC, 0, 0, DRC_W, DRC_H, RGB(14, 12, 34), RGB(6, 6, 18));
   s_text_sh(&S_DRC, 20, 14, 3, COL_ACCENT, "TERRAIN MAP");
   int mx = 20, my = 58;
   for (int y = 0; y < HM; y += 1)
   {
      u32 *d = S_DRC.p + (my + y) * S_DRC.pitch + mx;
      const u32 *s = cmap + y * HM;
      for (int x = 0; x < HM; x++) d[x] = s[x];
      if (my + y >= DRC_H - 2) break;
   }
   s_box_outline(&S_DRC, mx - 1, my - 1, HM + 2, HM + 2, COL_CYAN);
   int px = mx + ((int)cx & 255), py = my + ((int)cy & 255);
   s_line(&S_DRC, px, py, px + (int)(m_cos(yaw - 0.52f) * 46), py + (int)(m_sin(yaw - 0.52f) * 46), COL_WHITE);
   s_line(&S_DRC, px, py, px + (int)(m_cos(yaw + 0.52f) * 46), py + (int)(m_sin(yaw + 0.52f) * 46), COL_WHITE);
   s_disc(&S_DRC, px, py, 3, COL_ACCENT);

   int tx = 300;
   s_text_sh(&S_DRC, tx, 66, 2, COL_CYAN, "SKY CLOCK");
   int dcx = tx + 74, dcy = 168, dr = 56;
   s_ring(&S_DRC, dcx, dcy, dr, COL_DIM);
   for (int i = 0; i < 24; i++)
   {
      float a = TAU_F * (float)i / 24.0f;
      s_line(&S_DRC, dcx + (int)(m_cos(a) * (dr - 6)), dcy + (int)(m_sin(a) * (dr - 6)),
             dcx + (int)(m_cos(a) * dr), dcy + (int)(m_sin(a) * dr), COL_DIM);
   }
   s_disc(&S_DRC, dcx + (int)(m_cos(tod - 1.5708f) * (dr - 14)), dcy + (int)(m_sin(tod - 1.5708f) * (dr - 14)), 8, RGB(255, 220, 120));
   s_disc(&S_DRC, dcx + (int)(m_cos(tod + 1.5708f) * (dr - 14)), dcy + (int)(m_sin(tod + 1.5708f) * (dr - 14)), 5, RGB(200, 210, 255));
   s_textf(&S_DRC, tx + 10, 236, 2, COL_ACCENT, "%s", tod_name());

   int bx = 560;
   s_text_sh(&S_DRC, bx, 66, 2, COL_CYAN, "FLIGHT");
   s_textf(&S_DRC, bx, 96, 2, COL_WHITE, "ALT   %d", (int)cam_h);
   s_textf(&S_DRC, bx, 120, 2, COL_WHITE, "SPEED %d", (int)speed_now);
   s_textf(&S_DRC, bx, 144, 2, COL_WHITE, "HDG   %d", ((int)(yaw * 57.29578f) % 360 + 360) % 360);
   s_textf(&S_DRC, bx, 168, 2, COL_WHITE, "POS   %d,%d", (int)cx, (int)cy);
   s_text_sh(&S_DRC, bx, 214, 2, COL_CYAN, "CONTROLS");
   s_text(&S_DRC, bx, 240, 2, COL_DIM, "L STICK  MOVE");
   s_text(&S_DRC, bx, 260, 2, COL_DIM, "R STICK  LOOK");
   s_text(&S_DRC, bx, 280, 2, COL_DIM, "ZL/ZR    ALTITUDE");
   s_text(&S_DRC, bx, 300, 2, COL_DIM, "A        BOOST");
   s_text(&S_DRC, bx, 320, 2, COL_DIM, "X        CLOCK HOLD");
   s_text(&S_DRC, bx, 340, 2, COL_DIM, "D-PAD    SCRUB TIME");
}

const Scene sc_landscape = {
   "3D LANDSCAPE", "PROCEDURAL VOXEL TERRAIN, FOG, DAY-NIGHT SKY", 1, enter, update, render, hud, drc
};
