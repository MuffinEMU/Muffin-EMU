// Scene 1: procedural landscape. A 256x256 wrapping fBm heightmap is generated in the background
// while the title card shows, then rendered with a front-to-back column raycaster split across
// the three PPC cores: bilinear height and colour, per-pixel sun/moon diffuse lighting from the
// bilinear surface gradient, soft heightfield shadows refreshed a few rows per frame, animated
// water with Fresnel reflection, wave normals and sun glints, in-scattered fog, clouds, and a full
// day/night cycle that drives sky, sun, moon, stars, light colour and fog.
#include "showcase.h"
#include <string.h>

#define HM 256
#define WATER 58
#define DIST 260.0f

static u8 hmap[HM * HM];
static u32 cmap[HM * HM];        // albedo only; lighting is applied per pixel
static u32 mapimg[HM * HM];      // hill-shaded copy for the GamePad map
static u8 shmap[HM * HM];        // soft shadow factor 0..255 for the current light
static int s_shrow;
static float lgt_x = 0.4f, lgt_y = 0.3f, lgt_z = 0.8f;   // unit vector towards the light
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

static float rsq(float x)
{
   u32 i;
   float y;
   memcpy(&i, &x, 4);
   i = 0x5f3759dfu - (i >> 1);
   memcpy(&y, &i, 4);
   y = y * (1.5f - 0.5f * x * y * y);
   return y * (1.5f - 0.5f * x * y * y);
}

static int ci(int v) { return v < 0 ? 0 : (v > 255 ? 255 : v); }
static u32 mixc(int r0, int g0, int b0, int r1, int g1, int b1, int t)   // t 0..256
{
   return RGB(r0 + ((r1 - r0) * t >> 8), g0 + ((g1 - g0) * t >> 8), b0 + ((b1 - b0) * t >> 8));
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
            for (int o = 0; o < 6; o++)
            {
               sum += amp * vnoise((float)x / (float)cell, (float)y / (float)cell, HM / cell - 1, 0x5A5Au * (u32)(o + 1));
               norm += amp;
               amp *= 0.5f;
               cell = cell > 2 ? cell >> 1 : 2;
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
            int sl = (hl > hr ? hl - hr : hr - hl) + (hu > hd ? hu - hd : hd - hu);
            int shade = 190 + slope;
            if (shade < 90) shade = 90;
            if (shade > 300) shade = 300;
            int var = (int)(hash2(x, y) & 15u) - 8;
            float n1 = vnoise((float)x / 8.0f, (float)y / 8.0f, 31, 0xA11Cu);
            float n2 = vnoise((float)x / 24.0f, (float)y / 24.0f, 10, 0xF04Eu);
            u32 al;
            if (v < WATER)
               al = mixc(196, 176, 126, 70, 84, 96, (WATER - v) * 256 / WATER);
            else if (v < WATER + 7)
               al = mixc(222, 204, 150, 200, 182, 130, (int)(n1 * 256));
            else
            {
               // Grass and forest, then rock with height and slope, snow on the high flats.
               int forest = (int)(m_clamp((n2 - 0.42f) * 6.0f, 0.0f, 1.0f) * 256.0f);
               u32 grass = mixc(86, 138, 58, 52, 104, 50, (int)(n1 * 256));
               grass = col_mix(grass, RGB(26, 70, 38), forest);
               int rock_t = (v - 118) * 256 / 50;
               rock_t = rock_t < 0 ? 0 : (rock_t > 256 ? 256 : rock_t);
               int rk = (sl - 12) * 256 / 26;
               rk = rk < 0 ? 0 : (rk > 256 ? 256 : rk);
               if (rk < rock_t) rk = rock_t;
               u32 rock = mixc(120, 108, 98, 146, 136, 128, (int)(n1 * 256));
               al = col_mix(grass, rock, rk);
               if (v >= 186)
               {
                  int sn = (v - 186) * 256 / 12 - sl * 3;
                  sn = sn < 0 ? 0 : (sn > 256 ? 256 : sn);
                  al = col_mix(al, RGB(240, 244, 252), sn);
               }
            }
            int r = ci((int)CR(al) + var), g = ci((int)CG(al) + var), b = ci((int)CB(al) + var);
            cmap[y * HM + x] = RGB(r, g, b);
            if (v < WATER) mapimg[y * HM + x] = RGB(20, 60 + v, 120 + v);
            else mapimg[y * HM + x] = RGB(ci(r * shade >> 8), ci(g * shade >> 8), ci(b * shade >> 8));
            shmap[y * HM + x] = 255;
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

typedef struct
{
   u32 zen, hor, fog;
   int lr, lg, lb;            // ambient light, 256 = 1.0
   int sr, sg, sb;            // direct light colour times intensity
   float day, sunset, sun_i;
   float body_az, body_el;    // the body that lights the world (sun by day, moon by night)
   u32 warm;
} Sky;

static Sky sky_now(void)
{
   Sky s;
   float se = m_sin(tod);
   float day = m_clamp((se + 0.18f) / 0.5f, 0.0f, 1.0f);
   float sunset = m_clamp(1.0f - m_abs(se) / 0.32f, 0.0f, 1.0f);
   u32 nz = RGB(6, 8, 30), nh = RGB(18, 22, 58);
   u32 dz = RGB(40, 98, 214), dh = RGB(160, 204, 246);
   u32 sh = RGB(255, 128, 66);
   s.zen = col_mix(nz, dz, (int)(day * 256));
   s.hor = col_mix(nh, dh, (int)(day * 256));
   s.hor = col_mix(s.hor, sh, (int)(sunset * 0.85f * 256));
   s.zen = col_mix(s.zen, RGB(70, 50, 120), (int)(sunset * 0.35f * 256));
   s.fog = s.hor;
   float amb = 0.10f + 0.34f * day;
   s.lr = (int)(256 * (amb * (1.0f + 0.30f * sunset) + 0.03f * (1 - day)));
   s.lg = (int)(256 * (amb * (1.0f - 0.05f * sunset) + 0.05f * (1 - day)));
   s.lb = (int)(256 * (amb * (1.0f - 0.30f * sunset) + 0.12f * (1 - day)));
   // Direct light: the sun while it is up, a weak blue moon otherwise.
   float sun_w = m_clamp((se + 0.04f) / 0.22f, 0.0f, 1.0f);
   float moon_w = m_clamp(-se / 0.3f, 0.0f, 1.0f) * 0.20f * (1.0f - sun_w);
   float sun_i = sun_w * (0.55f + 0.55f * m_clamp(se, 0.0f, 1.0f));
   int sr = (int)(256.0f * sun_i * (1.0f + 0.05f * (1 - sunset) + 0.25f * sunset));
   int sg = (int)(256.0f * sun_i * (0.97f - 0.22f * sunset));
   int sb = (int)(256.0f * sun_i * (0.90f - 0.50f * sunset));
   s.sr = sr + (int)(256.0f * moon_w * 0.55f);
   s.sg = sg + (int)(256.0f * moon_w * 0.70f);
   s.sb = sb + (int)(256.0f * moon_w * 1.05f);
   s.day = day; s.sunset = sunset; s.sun_i = sun_i + moon_w;
   float ang = se >= -0.02f ? tod : tod + PI_F;
   s.body_el = m_sin(ang);
   s.body_az = 1.1f + m_cos(ang) * 0.9f;
   s.warm = col_mix(RGB(255, 200, 130), RGB(255, 120, 60), (int)(sunset * 256));
   return s;
}

// Soft shadows: march from each texel towards the light and keep the narrowest clearance, which
// gives a penumbra that widens with distance. A few rows per frame keep the map following the
// slowly moving sun.
static void shadow_rows(int n)
{
   float lh = m_sqrt(lgt_x * lgt_x + lgt_y * lgt_y);
   if (lh < 0.01f) lh = 0.01f;
   const float dxs = lgt_x / lh, dys = lgt_y / lh;
   const float tan_e = lgt_z / lh;
   while (n-- > 0)
   {
      int y = s_shrow;
      s_shrow = (s_shrow + 1) & 255;
      for (int x = 0; x < HM; x++)
      {
         float h0 = (float)hmap[y * HM + x] * 0.55f + 0.6f;
         float res = 1.0f;
         float t = 1.5f;
         for (int k = 0; k < 44 && t < 110.0f; k++)
         {
            int mx = (int)((float)x + dxs * t + 1024.0f) & 255, my = (int)((float)y + dys * t + 1024.0f) & 255;
            float th = (float)hmap[my * HM + mx] * 0.55f;
            if (th < (float)WATER * 0.55f) th = (float)WATER * 0.55f;
            float clear = h0 + t * tan_e - th;
            float v = clear * 5.0f / (t + 6.0f);
            if (v < res) { res = v; if (res <= 0.0f) break; }
            t += 1.5f + t * 0.06f;
         }
         shmap[y * HM + x] = (u8)(res <= 0.0f ? 0 : (res >= 1.0f ? 255 : (int)(res * 255.0f)));
      }
   }
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
   if (cx < 0) cx += 256;
   if (cx >= 256) cx -= 256;
   if (cy < 0) cy += 256;
   if (cy >= 256) cy -= 256;
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

   if (terrain_ready())
   {
      Sky sk = sky_now();
      float el = m_clamp(sk.body_el, 0.05f, 1.0f) * 0.94f;
      float hm = m_sqrt(1.0f - el * el);
      lgt_x = m_cos(sk.body_az) * hm;
      lgt_y = m_sin(sk.body_az) * hm;
      lgt_z = el;
      shadow_rows(demo || m_abs(in->lx) > 0.0f ? 10 : 8);
   }
}

// ------------------------------------------------------------------ sky

static int sky_x(float az, int W) { float da = az - yaw; da -= TAU_F * (float)m_floor(da / TAU_F + 0.5f); return W / 2 + (int)(da / 1.05f * (float)W); }

static void draw_sky(const Sky *sk, int hor)
{
   const int W = g_sw, H = g_sh;
   const int k = W / 320;   // 2 at full quality
   for (int y = 0; y < hor; y++)
   {
      int t = y * 256 / hor;
      s_rect(&S_SCN, 0, y, W, 1, col_mix(sk->zen, sk->hor, (t * t) >> 8));
   }
   s_rect(&S_SCN, 0, hor, W, H - hor, sk->fog);

   // Stars fade in with the dark.
   if (sk->day < 0.6f)
   {
      int a = (int)((1.0f - sk->day / 0.6f) * 255);
      for (int i = 0; i < 160; i++)
      {
         u32 h = hash2(i, 77);
         float sa = (float)(h & 1023u) * (TAU_F / 1024.0f);
         float el = (float)((h >> 10) & 255u) / 255.0f;
         int sx = sky_x(sa, W);
         int sy = hor - 2 - (int)(el * (float)hor * 0.95f);
         if (sx < 0 || sx >= W - 1 || sy < 0) continue;
         int tw = 110 + (int)(145.0f * (0.5f + 0.5f * m_sin(g_time * 3.0f + (float)i)));
         int br = 90 + (int)((h >> 18) & 127u);
         u32 c = col_scale(RGB(br + 40, br + 50, 255), a * tw >> 8);
         s_add_pixel(&S_SCN, sx, sy, c);
         if (k >= 2 && (h & 7u) == 0)
         {
            u32 c2 = col_scale(c, 110);
            s_add_pixel(&S_SCN, sx + 1, sy, c2); s_add_pixel(&S_SCN, sx, sy + 1, c2);
            s_add_pixel(&S_SCN, sx - 1, sy, c2); s_add_pixel(&S_SCN, sx, sy - 1, c2);
         }
      }
   }

   // Sun and moon on the same arc, opposite phases.
   for (int body = 0; body < 2; body++)
   {
      float ang = body ? tod + PI_F : tod;
      float el = m_sin(ang);
      if (el < -0.12f) continue;
      float az = 1.1f + m_cos(ang) * 0.9f;
      int px = sky_x(az, W);
      int py = hor - (int)(el * (float)hor * 0.92f);
      float r = (body ? 5.0f : 8.0f) * (float)k * 0.5f;
      if (!body)
      {
         int a = 256;
         if (el < 0.0f) a = (int)(256.0f * (1.0f + el / 0.12f));
         s_glow(&S_SCN, px, py, H / 2, sk->warm, a * (80 + (int)(sk->sunset * 90.0f)) >> 8);
         s_glow(&S_SCN, px, py, H / 6, RGB(255, 240, 210), a * 150 >> 8);
         s_disc_aa(&S_SCN, (float)px, (float)py, r * 1.2f, RGB(255, 246, 214));
      }
      else
      {
         s_glow(&S_SCN, px, py, H / 5, RGB(70, 90, 150), 150);
         s_disc_aa(&S_SCN, (float)px, (float)py, r * 1.35f, RGB(226, 232, 255));
         s_disc_aa(&S_SCN, (float)px - r * 0.35f, (float)py - r * 0.2f, r * 0.34f, RGB(190, 198, 228));
         s_disc_aa(&S_SCN, (float)px + r * 0.4f, (float)py + r * 0.3f, r * 0.26f, RGB(196, 204, 232));
      }
   }

   // Clouds: soft blob clusters drifting in azimuth, tinted by the light.
   u32 base = col_mix(RGB(34, 40, 74), RGB(252, 252, 255), (int)(sk->day * 256));
   base = col_mix(base, RGB(255, 168, 120), (int)(sk->sunset * 0.7f * 256));
   u32 under = col_scale(base, 190);
   for (int i = 0; i < 16; i++)
   {
      u32 h = hash2(i, 311);
      float az = (float)(h & 1023u) * (TAU_F / 1024.0f) + g_time * (0.004f + (float)((h >> 12) & 7u) * 0.0008f);
      float el = 0.10f + (float)((h >> 10) & 127u) / 127.0f * 0.55f;
      int px = sky_x(az, W);
      int py = hor - (int)(el * (float)hor * 0.9f);
      int sz = (6 + (int)((h >> 20) & 15u)) * k;
      if (px < -sz * 4 || px > W + sz * 4) continue;
      float pers = 1.0f - el * 0.5f;
      for (int b = 0; b < 5; b++)
      {
         u32 hb = hash2(i * 7 + b, 12);
         int ox = (int)((hb & 255u) - 128u) * sz / 70, oy = (int)(((hb >> 8) & 63u) - 32u) * sz / 90;
         int rx = (int)((float)(sz * 2 + (int)((hb >> 14) & 15u) * k) * pers), ry = rx * 2 / 7 + 1;
         s_blob(&S_SCN, px + ox, py + oy + ry / 4, rx, ry, under, 120);
         s_blob(&S_SCN, px + ox, py + oy - ry / 5, rx * 9 / 10, ry * 9 / 10, base, 130);
      }
   }
}

// ------------------------------------------------------------------ terrain

typedef struct
{
   Sky sk;
   int hor;
   float K, fov, ox, oy, camh, yaw, time;
   float sdx, sdy;     // unit horizontal direction towards the light
} RCtx;

static void terrain_cols(void *vc, int job, int njobs)
{
   const RCtx *c = vc;
   const int W = g_sw, H = g_sh;
   int x0 = (W * job / njobs) & ~7, x1 = (job + 1 == njobs) ? W : ((W * (job + 1) / njobs) & ~7);
   const Sky *sk = &c->sk;
   const int hor = c->hor;
   const float fogr = (float)CR(sk->fog), fogg = (float)CG(sk->fog), fogb = (float)CB(sk->fog);
   const float t = c->time;
   // Direct light direction for the water glint: towards the light, y-up convention (z is up).
   const float Lx = lgt_x, Ly = lgt_y, Lz = lgt_z;
   const int near_lim = 110;

   for (int x = x0; x < x1; x++)
   {
      float a = c->yaw + ((float)x / (float)W - 0.5f) * c->fov;
      float dx = m_cos(a), dy = m_sin(a);
      float sun_dot = dx * c->sdx + dy * c->sdy;
      float g = sun_dot > 0.0f ? sun_dot : 0.0f;
      g *= g; g *= g; g *= g;     // ^8
      int scat = (int)(g * sk->sun_i * 170.0f);
      u32 fogc = col_mix(sk->fog, sk->warm, scat > 230 ? 230 : scat);
      int fr = (int)CR(fogc), fg = (int)CG(fogc), fb = (int)CB(fogc);
      (void)fogr; (void)fogg; (void)fogb;
      int ybuf = H;
      float z = 1.5f, dz = 0.34f;
      while (z < DIST && ybuf > 0)
      {
         float mxf = c->ox + dx * z, myf = c->oy + dy * z;
         int xi = (int)mxf, yi = (int)myf;
         float fx = mxf - (float)xi, fy = myf - (float)yi;
         int i0 = xi & 255, j0 = yi & 255, i1 = (xi + 1) & 255, j1 = (yi + 1) & 255;
         int idx = j0 * HM + i0;
         float h00 = (float)hmap[idx], h10 = (float)hmap[j0 * HM + i1];
         float h01 = (float)hmap[j1 * HM + i0], h11 = (float)hmap[j1 * HM + i1];
         float ta = h00 + (h10 - h00) * fx, tb = h01 + (h11 - h01) * fx;
         float h = ta + (tb - ta) * fy;
         int water = h < (float)WATER;
         float hh = water ? (float)WATER : h;
         float sy = (float)hor + (c->camh - hh * 0.55f) * c->K / z;
         int top = (int)sy;
         if (top < 0) top = 0;
         if (top < ybuf)
         {
            int r, gc, b;
            if (!water)
            {
               float gx = (h10 - h00) * (1.0f - fy) + (h11 - h01) * fy;
               float gy = (h01 - h00) * (1.0f - fx) + (h11 - h10) * fx;
               gx *= 0.55f; gy *= 0.55f;
               float ndl = (Lz - gx * Lx - gy * Ly) * rsq(1.0f + gx * gx + gy * gy);
               if (ndl < 0.0f) ndl = 0.0f;
               int shw = shmap[idx];
               int direct = (int)(ndl * (float)shw);          // 0..255
               u32 al;
               if (z < (float)near_lim)
               {
                  u32 a0 = col_lerp(cmap[idx], cmap[j0 * HM + i1], (int)(fx * 256.0f));
                  u32 a1 = col_lerp(cmap[j1 * HM + i0], cmap[j1 * HM + i1], (int)(fx * 256.0f));
                  al = col_lerp(a0, a1, (int)(fy * 256.0f));
                  if (z < 38.0f)
                  {
                     int dn = (int)(hash2((int)(mxf * 5.0f), (int)(myf * 5.0f)) & 15u) - 8;
                     int k = dn * (int)(38.0f - z) / 38;
                     al = RGB(ci((int)CR(al) + k), ci((int)CG(al) + k), ci((int)CB(al) + k));
                  }
               }
               else al = cmap[idx];
               int lr = sk->lr + (sk->sr * direct >> 8);
               int lg = sk->lg + (sk->sg * direct >> 8);
               int lb = sk->lb + (sk->sb * direct >> 8);
               r = (int)CR(al) * lr >> 8; gc = (int)CG(al) * lg >> 8; b = (int)CB(al) * lb >> 8;
            }
            else
            {
               // Water: animated wave normal, Fresnel mix of deep colour and sky, sun glint.
               float wx = dx * z + (float)xi, wy = dy * z + (float)yi;
               float nx = 0.16f * m_sin(wx * 0.9f + t * 1.7f) + 0.10f * m_sin(wy * 1.3f - t * 1.2f + wx * 0.4f);
               float ny = 0.16f * m_sin(wy * 0.8f + t * 1.4f) + 0.10f * m_sin(wx * 1.1f + t * 1.9f - wy * 0.5f);
               float vh = c->camh - (float)WATER * 0.55f;
               float vl = rsq(z * z + vh * vh);
               float vx = -dx * z * vl, vy = -dy * z * vl, vz = vh * vl;     // surface -> eye
               float fres = 1.0f - vz;                                        // cos(theta) = vz
               if (fres < 0.0f) fres = 0.0f;
               float f2 = fres * fres;
               float F = 0.04f + 0.96f * f2 * f2 * fres;
               int depth = (int)((float)(WATER - (int)h) * 256.0f / (float)WATER);
               if (depth < 0) depth = 0;
               if (depth > 256) depth = 256;
               u32 shallow = RGB(36, 150, 158), deep = RGB(8, 44, 100);
               u32 wc = col_mix(shallow, deep, depth);
               int dl = (int)(sk->sun_i * 150.0f) + 70;
               wc = RGB(ci((int)CR(wc) * (sk->lr + dl) >> 8), ci((int)CG(wc) * (sk->lg + dl) >> 8), ci((int)CB(wc) * (sk->lb + dl) >> 8));
               // Reflected sky colour: horizon at grazing angles, zenith looking straight down.
               int rs = (int)(vz * 256.0f * 1.4f);
               u32 sc = col_mix(sk->hor, sk->zen, rs > 256 ? 256 : rs);
               wc = col_mix(wc, sc, (int)(F * 256.0f));
               // Blinn-Phong glint from the perturbed normal.
               float nl = rsq(1.0f + nx * nx + ny * ny);
               float Nx = -nx * nl, Ny = -ny * nl, Nz = nl;
               float hx = Lx + vx, hy = Ly + vy, hz = Lz + vz;
               float hl = rsq(hx * hx + hy * hy + hz * hz);
               float nh = (Nx * hx + Ny * hy + Nz * hz) * hl;
               if (nh > 0.0f && sk->sun_i > 0.02f)
               {
                  float p = nh * nh; p *= p; p *= p; p *= p; p *= p; p *= p;   // ^64
                  int sp = (int)(p * 255.0f * sk->sun_i);
                  wc = col_add(wc, RGB(sp, sp * 9 / 10, sp * 7 / 10));
               }
               // Shore foam where the water is shallow.
               if (h > (float)WATER - 3.0f)
               {
                  float fo = (h - ((float)WATER - 3.0f)) * 0.33f;
                  float wv = 0.5f + 0.5f * m_sin(wx * 2.2f + wy * 1.7f + t * 2.6f);
                  int fa = (int)(fo * wv * 230.0f);
                  wc = col_mix(wc, RGB(236, 244, 250), fa > 256 ? 256 : fa);
               }
               r = (int)CR(wc); gc = (int)CG(wc); b = (int)CB(wc);
            }
            float u = (z - 36.0f) * (1.0f / (DIST - 36.0f));
            int f = u > 0.0f ? (int)(u * u * 256.0f) : 0;
            if (f > 256) f = 256;
            if (f > 0)
            {
               r += (fr - r) * f >> 8;
               gc += (fg - gc) * f >> 8;
               b += (fb - b) * f >> 8;
            }
            if (r > 255) r = 255;
            if (gc > 255) gc = 255;
            if (b > 255) b = 255;
            u32 px = RGB(r, gc, b);
            u32 *p = S_SCN.p + top * W + x;
            for (int y = top; y < ybuf; y++) { *p = px; p += W; }
            ybuf = top;
         }
         z += dz;
         dz *= 1.011f;
      }
   }
   // Each core owns a band of columns (a multiple of 8 words, so no cache line is shared).
   for (int y = 0; y < H; y++) par_flush(S_SCN.p + y * W + x0, (size_t)(x1 - x0) * 4);
}

static void render(void)
{
   const int W = g_sw, H = g_sh;
   Sky sk = sky_now();
   int hor = (int)((float)H * (0.46f + pitch));
   if (hor < 4) hor = 4;
   if (hor > H - 4) hor = H - 4;
   draw_sky(&sk, hor);

   RCtx c;
   c.sk = sk;
   c.hor = hor;
   c.K = (float)H * 0.95f;
   c.fov = 1.05f;
   c.ox = cx + 1024.0f; c.oy = cy + 1024.0f;
   c.camh = cam_h; c.yaw = yaw; c.time = g_time;
   float hm = m_sqrt(lgt_x * lgt_x + lgt_y * lgt_y);
   c.sdx = hm > 0.001f ? lgt_x / hm : 1.0f;
   c.sdy = hm > 0.001f ? lgt_y / hm : 0.0f;
   par_publish(S_SCN.p, (size_t)W * (size_t)H * 4);
   par_run(terrain_cols, &c);
   par_consume(S_SCN.p, (size_t)W * (size_t)H * 4);
   (void)W;
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
      const u32 *s = mapimg + y * HM;
      for (int x = 0; x < HM; x++) d[x] = s[x];
      if (my + y >= DRC_H - 2) break;
   }
   s_box_outline(&S_DRC, mx - 1, my - 1, HM + 2, HM + 2, COL_CYAN);
   float fx = (float)((int)cx & 255), fy = (float)((int)cy & 255);
   float pxf = (float)mx + fx, pyf = (float)my + fy;
   s_line_aa(&S_DRC, pxf, pyf, pxf + m_cos(yaw - 0.52f) * 46.0f, pyf + m_sin(yaw - 0.52f) * 46.0f, COL_WHITE);
   s_line_aa(&S_DRC, pxf, pyf, pxf + m_cos(yaw + 0.52f) * 46.0f, pyf + m_sin(yaw + 0.52f) * 46.0f, COL_WHITE);
   s_disc_aa(&S_DRC, pxf, pyf, 3.5f, COL_ACCENT);

   int tx = 300;
   s_text_sh(&S_DRC, tx, 66, 2, COL_CYAN, "SKY CLOCK");
   int dcx = tx + 74, dcy = 168, dr = 56;
   for (int i = 0; i < 24; i++)
   {
      float a = TAU_F * (float)i / 24.0f;
      s_line_aa(&S_DRC, (float)dcx + m_cos(a) * (float)(dr - 6), (float)dcy + m_sin(a) * (float)(dr - 6),
                (float)dcx + m_cos(a) * (float)dr, (float)dcy + m_sin(a) * (float)dr, COL_DIM);
   }
   for (int i = 0; i < 72; i++)
   {
      float a0 = TAU_F * (float)i / 72.0f, a1 = TAU_F * (float)(i + 1) / 72.0f;
      s_line_aa(&S_DRC, (float)dcx + m_cos(a0) * (float)dr, (float)dcy + m_sin(a0) * (float)dr,
                (float)dcx + m_cos(a1) * (float)dr, (float)dcy + m_sin(a1) * (float)dr, COL_DIM);
   }
   s_disc_aa(&S_DRC, (float)dcx + m_cos(tod - 1.5708f) * (float)(dr - 14), (float)dcy + m_sin(tod - 1.5708f) * (float)(dr - 14), 8.0f, RGB(255, 220, 120));
   s_disc_aa(&S_DRC, (float)dcx + m_cos(tod + 1.5708f) * (float)(dr - 14), (float)dcy + m_sin(tod + 1.5708f) * (float)(dr - 14), 5.0f, RGB(200, 210, 255));
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
   "3D LANDSCAPE", "LIT TERRAIN WITH SHADOWS, REFLECTIVE WATER, CLOUDS, DAY-NIGHT SKY", 1, enter, update, render, hud, drc
};
