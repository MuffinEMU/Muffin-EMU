// Scene 2: particles. Two modes share one pool of up to 6000 additive sparks / 7000 stars:
// fireworks (rockets, sphere/ring/heart/willow bursts, gravity, drag, trails) and a spiral galaxy
// (7000 stars on differential-rotation orbits, rotated and perspective-projected in 3D).
// Everything is plain CPU maths into the scene buffer. Touch the GamePad view to fire a burst.
#include "showcase.h"

#define MAXP 6000
#define NSTAR 7000
#define IMG_X 107
#define IMG_Y 14

static float px[MAXP], py[MAXP], vx[MAXP], vy[MAXP], life[MAXP], maxl[MAXP], drag[MAXP];
static u32 pcol[MAXP];
static int np;

typedef struct { float x, y, vx, vy; int on; u32 col; int type; } Rocket;
static Rocket rk[6];
static float launch_t;

static float gr[NSTAR], ga[NSTAR], gz[NSTAR];
static u32 gcol[NSTAR];
static int mode;            // 0 fireworks, 1 galaxy
static float gyaw, gtilt = 0.9f, pulse, mode_t;
static int stars_ready;
static int total_bursts;

static void spark(float x, float y, float sx, float sy, float l, float dr, u32 c)
{
   if (np >= MAXP) return;
   px[np] = x; py[np] = y; vx[np] = sx; vy[np] = sy; life[np] = l; maxl[np] = l; drag[np] = dr; pcol[np] = c;
   np++;
}

static void burst(float x, float y, int type, u32 col)
{
   total_bursts++;
   switch (type)
   {
   case 0:
      for (int i = 0; i < 170; i++)
      {
         float a = frand() * TAU_F, s = 14.0f + 62.0f * m_sqrt(frand());
         spark(x, y, m_cos(a) * s, m_sin(a) * s, 1.1f + frand() * 1.0f, 0.985f, i % 5 == 0 ? COL_WHITE : col);
      }
      break;
   case 1:
      for (int i = 0; i < 120; i++)
      {
         float a = TAU_F * (float)i / 120.0f;
         spark(x, y, m_cos(a) * 62.0f, m_sin(a) * 62.0f, 1.6f, 0.982f, col);
         if (i % 2) spark(x, y, m_cos(a) * 34.0f, m_sin(a) * 34.0f, 1.3f, 0.982f, col_mix(col, COL_WHITE, 140));
      }
      break;
   case 2:
      for (int i = 0; i < 150; i++)
      {
         float t = TAU_F * (float)i / 150.0f;
         float s = m_sin(t);
         float hx = 16.0f * s * s * s;
         float hy = -(13.0f * m_cos(t) - 5.0f * m_cos(2 * t) - 2.0f * m_cos(3 * t) - m_cos(4 * t));
         spark(x, y, hx * 3.4f, hy * 3.4f, 1.9f, 0.985f, RGB(255, 80 + (i & 31), 140));
      }
      break;
   default:
      for (int i = 0; i < 160; i++)
      {
         float a = frand() * TAU_F, s = 20.0f + 40.0f * frand();
         spark(x, y, m_cos(a) * s, m_sin(a) * s, 2.8f + frand() * 1.2f, 0.965f, RGB(255, 190 + (i & 31), 90));
      }
      break;
   }
}

static void launch(float x)
{
   for (int i = 0; i < 6; i++)
      if (!rk[i].on)
      {
         rk[i].on = 1;
         rk[i].x = x; rk[i].y = (float)SCN_H - 14.0f;
         rk[i].vx = frands() * 12.0f;
         rk[i].vy = -(120.0f + frand() * 40.0f);
         rk[i].type = (int)(rnd() & 3u);
         rk[i].col = hsv(frand(), 0.75f, 1.0f);
         return;
      }
}

static void init_stars(void)
{
   u32 s = 0xC0FFEEu;
   for (int i = 0; i < NSTAR; i++)
   {
      float r = m_sqrt((float)(rnd_r(&s) >> 8) * (1.0f / 16777216.0f)) * 0.95f + 0.04f;
      int arm = (int)(rnd_r(&s) & 1u);
      float jitter = ((float)(rnd_r(&s) >> 8) * (1.0f / 16777216.0f) - 0.5f) * (0.9f - 0.5f * r) * 1.6f;
      ga[i] = (float)arm * PI_F + r * 5.2f + jitter;
      gr[i] = r;
      gz[i] = (((float)(rnd_r(&s) >> 8) * (1.0f / 16777216.0f)) - 0.5f) * 0.10f * (1.2f - r);
      float core = m_clamp(1.0f - r * 1.6f, 0.0f, 1.0f);
      int b = 70 + (int)(rnd_r(&s) & 63u);
      int rr = (int)((float)b * (0.55f + 0.7f * core)), gg = (int)((float)b * (0.62f + 0.4f * core)),
          bb = (int)((float)b * (1.2f - 0.55f * core));
      gcol[i] = RGB(rr > 255 ? 255 : rr, gg > 255 ? 255 : gg, bb > 255 ? 255 : bb);
   }
   stars_ready = 1;
}

static void enter(void)
{
   np = 0;
   for (int i = 0; i < 6; i++) rk[i].on = 0;
   mode_t = 0;
   s_fill(&S_SCN, RGB(0, 0, 0));
   if (!stars_ready) init_stars();
}

static void update(const Input *in, float dt, int demo)
{
   mode_t += dt;
   if (in->trig & B_X) mode ^= 1;
   if (demo && mode_t > 7.0f) { mode = 1; }
   if (demo && mode_t < 0.1f) mode = 0;

   // GamePad second view: touch fires a burst at that spot; the two buttons below pick the mode.
   if (in->touch_trig)
   {
      if (in->ty > 390.0f && in->ty < 450.0f)
      {
         if (in->tx > 107.0f && in->tx < 367.0f) mode = 0;
         if (in->tx > 387.0f && in->tx < 747.0f) mode = 1;
      }
      else if (mode == 0 && in->tx >= IMG_X && in->tx < IMG_X + 640 && in->ty >= IMG_Y && in->ty < IMG_Y + 360)
      {
         burst((in->tx - IMG_X) * 0.5f, (in->ty - IMG_Y) * 0.5f, (int)(rnd() & 3u), hsv(frand(), 0.7f, 1.0f));
         input_rumble(8);
      }
   }

   if (mode == 0)
   {
      if (in->trig & B_A) { burst(60.0f + frand() * 200.0f, 40.0f + frand() * 60.0f, (int)(rnd() & 3u), hsv(frand(), 0.7f, 1.0f)); }
      launch_t -= dt;
      if (launch_t <= 0.0f)
      {
         launch(50.0f + frand() * 220.0f);
         launch_t = 0.35f + frand() * 0.55f;
      }
      for (int i = 0; i < 6; i++)
      {
         Rocket *r = &rk[i];
         if (!r->on) continue;
         r->x += r->vx * dt; r->y += r->vy * dt; r->vy += 90.0f * dt;
         spark(r->x, r->y, frands() * 6.0f, 18.0f + frand() * 14.0f, 0.35f, 0.95f, RGB(255, 190, 110));
         if (r->vy > -18.0f) { burst(r->x, r->y, r->type, r->col); r->on = 0; }
      }
      for (int i = 0; i < np;)
      {
         life[i] -= dt;
         if (life[i] <= 0.0f) { np--; px[i] = px[np]; py[i] = py[np]; vx[i] = vx[np]; vy[i] = vy[np];
            life[i] = life[np]; maxl[i] = maxl[np]; drag[i] = drag[np]; pcol[i] = pcol[np]; continue; }
         vx[i] *= drag[i]; vy[i] = vy[i] * drag[i] + 38.0f * dt;
         px[i] += vx[i] * dt; py[i] += vy[i] * dt;
         i++;
      }
   }
   else
   {
      gyaw += (0.35f + in->rx * 1.6f) * dt;
      gtilt = m_clamp(gtilt + in->ry * 0.9f * dt, 0.15f, 1.45f);
      if (in->trig & B_A) pulse = 1.0f;
      pulse *= 1.0f - m_clamp(dt * 1.6f, 0.0f, 1.0f);
   }
}

static void render_fireworks(void)
{
   s_fade(&S_SCN, 200);
   const float sc = (float)g_sw / (float)SCN_W;
   for (int i = 0; i < 70; i++)
   {
      u32 h = hash2(i, 5);
      int x = (int)((h & 1023u) % (u32)g_sw), y = (int)(((h >> 10) & 1023u) % (u32)(g_sh * 3 / 4));
      int tw = 40 + (int)(60.0f * (0.5f + 0.5f * m_sin(g_time * 2.0f + (float)i)));
      s_add_pixel(&S_SCN, x, y, RGB(tw, tw, tw + 20));
   }
   for (int i = 0; i < np; i++)
   {
      int x = (int)(px[i] * sc), y = (int)(py[i] * sc);
      float f = life[i] / maxl[i];
      int k = (int)(f * 255.0f);
      if (k > 255) k = 255;
      u32 c = col_scale(pcol[i], k);
      s_add_pixel(&S_SCN, x, y, c);
      if (f > 0.6f)
      {
         u32 c2 = col_scale(c, 110);
         s_add_pixel(&S_SCN, x + 1, y, c2);
         s_add_pixel(&S_SCN, x, y + 1, c2);
      }
   }
   // Skyline with lit windows, drawn over the sparks.
   int base = g_sh - 1;
   for (int x = 0; x < g_sw; x += 1)
   {
      int bx = x / (g_sw / 20 + 1);
      u32 h = hash2(bx, 9);
      int bh = g_sh / 12 + (int)(h % (u32)(g_sh / 5 + 1));
      s_rect(&S_SCN, x, base - bh, 1, bh + 1, RGB(8, 7, 18));
      if (((x & 3) == 1) && (hash2(x, (int)(g_time * 0.7f) + bx) & 7u) < 2u)
         for (int wy = base - bh + 3; wy < base - 2; wy += 4)
            if ((hash2(x, wy) & 3u) == 0) s_rect(&S_SCN, x, wy, 1, 1, RGB(120, 100, 50));
   }
}

static void render_galaxy(void)
{
   s_fade(&S_SCN, 140);
   const int cxp = g_sw / 2, cyp = g_sh / 2;
   const float scl = (float)g_sh * 0.46f;
   float ct = m_cos(gtilt), st = m_sin(gtilt);
   float cy_ = m_cos(gyaw), sy_ = m_sin(gyaw);
   float expand = 1.0f + pulse * 0.45f;
   for (int i = 0; i < NSTAR; i++)
   {
      float r = gr[i];
      float om = 0.95f / (0.16f + r);
      float a = ga[i] + g_time * om * 0.35f;
      float x = r * expand * m_cos(a), y = r * expand * m_sin(a), z = gz[i];
      float x2 = x * cy_ - y * sy_, y2 = x * sy_ + y * cy_;
      float y3 = y2 * ct - z * st, z3 = y2 * st + z * ct;
      float s = 1.0f / (2.2f - z3 * 0.6f);
      int sx = cxp + (int)(x2 * scl * s * 2.0f), sy = cyp + (int)(y3 * scl * s * 2.0f);
      s_add_pixel(&S_SCN, sx, sy, gcol[i]);
   }
   // Bright core glow.
   for (int k = 6; k >= 1; k--)
      s_rect_a(&S_SCN, cxp - k * 3, cyp - k * 2, k * 6, k * 4, RGB(255, 200, 140), 20 + (int)(pulse * 40.0f));
   s_disc(&S_SCN, cxp, cyp, 2, COL_WHITE);
}

static void render(void)
{
   if (mode == 0) render_fireworks(); else render_galaxy();
}

static void hud(void)
{
   s_panel(&S_TV, 24, TV_H - 84, 410, 60, COL_PINK);
   if (mode == 0)
      s_textf(&S_TV, 38, TV_H - 74, 2, COL_WHITE, "SPARKS %4d / %d", np, MAXP);
   else
      s_textf(&S_TV, 38, TV_H - 74, 2, COL_WHITE, "STARS  %4d", NSTAR);
   s_textf(&S_TV, 38, TV_H - 52, 2, COL_ACCENT, "MODE %s  X TO SWITCH", mode ? "GALAXY" : "FIREWORKS");
}

static void drc(const Input *in)
{
   (void)in;
   s_vgrad(&S_DRC, 0, 0, DRC_W, DRC_H, RGB(14, 12, 34), RGB(6, 6, 18));
   gfx_blit_scene_drc(IMG_X, IMG_Y);
   s_box_outline(&S_DRC, IMG_X - 1, IMG_Y - 1, 642, 362, mode ? COL_CYAN : COL_PINK);
   for (int b = 0; b < 2; b++)
   {
      int x = 107 + b * 280;
      int on = (b == mode);
      s_rect(&S_DRC, x, 395, 260, 50, on ? COL_ACCENT : COL_PANEL);
      s_box_outline(&S_DRC, x, 395, 260, 50, on ? COL_WHITE : COL_DIM);
      const char *t = b ? "GALAXY" : "FIREWORKS";
      s_text_sh(&S_DRC, x + (260 - text_w(t, 3)) / 2, 410, 3, on ? RGB(30, 20, 10) : COL_WHITE, t);
   }
   s_textf(&S_DRC, 107, 456, 2, COL_DIM, "TOUCH THE VIEW TO FIRE A BURST    BURSTS %d", total_bursts);
}

const Scene sc_particles = {
   "PARTICLES", "THOUSANDS OF ADDITIVE SPARKS, FIREWORKS AND A 3D GALAXY", 2, enter, update, render, hud, drc
};
