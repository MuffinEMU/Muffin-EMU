// Scene 4: input lab. Exercises VPAD (buttons, both sticks, touch panel, accelerometer, gyroscope,
// rumble motor) and KPAD (Pro Controller). The GamePad is a live drawing canvas plus readouts;
// the TV shows a software-rendered 3D cube that you tilt with the GamePad's motion sensors.
#include "showcase.h"
#include <string.h>

static u32 canvas[DRC_W * DRC_H];
static Surf S_CAN = { canvas, DRC_W, DRC_W, DRC_H };
static float rot_x = 0.4f, rot_y = 0.6f, rot_z;
static float tilt_x, tilt_y;
static float tx_s = -1, ty_s = -1;      // last touch in canvas space (-1 = none)
static float hue;
static float rumble_t;
static Input last;

typedef struct { float x, y, age; } Ripple;
static Ripple rip[16];
static int rip_n;
static float trail[48][2];
static int trail_n;

static void enter(void)
{
   s_fill(&S_CAN, RGB(10, 9, 26));
   g_audio_track_override = -1;
}

static void add_ripple(float x, float y)
{
   rip[rip_n & 15].x = x; rip[rip_n & 15].y = y; rip[rip_n & 15].age = 0.0f;
   rip_n++;
}

static void update(const Input *in, float dt, int demo)
{
   last = *in;
   float gy = demo ? 0.0f : in->gyro[1], gx = demo ? 0.0f : in->gyro[0], gz = demo ? 0.0f : in->gyro[2];
   rot_y += (0.35f + in->rx * 2.2f + gy * TAU_F) * dt;
   rot_x += (in->ry * 2.2f + gx * TAU_F) * dt;
   rot_z += gz * TAU_F * dt;
   if (demo) { rot_x = 0.5f + 0.4f * m_sin(g_time * 0.8f); }
   tilt_x += ((demo ? 0.3f * m_sin(g_time) : in->acc[1]) * 0.7f - tilt_x) * 0.2f;
   tilt_y += ((demo ? 0.3f * m_cos(g_time * 0.7f) : in->acc[0]) * 0.7f - tilt_y) * 0.2f;

   if ((in->trig & B_X)) s_fill(&S_CAN, RGB(10, 9, 26));
   if (in->trig & B_A) { input_rumble(40); rumble_t = 0.6f; }
   if (rumble_t > 0) { rumble_t -= dt; if (rumble_t <= 0) input_rumble_stop(); }

   if (in->touched)
   {
      float x = in->tx, y = in->ty;
      hue += dt * 0.4f;
      u32 c = hsv(hue, 0.8f, 1.0f);
      if (in->touch_trig)
      {
         if (x > 700 && y > 395)            // rumble button
         {
            input_rumble(40); rumble_t = 0.6f;
         }
         else if (x < 140 && y > 400)       // clear button
            s_fill(&S_CAN, RGB(10, 9, 26));
         add_ripple(x * (float)g_sw / (float)DRC_W, y * (float)g_sh / (float)DRC_H);
         tx_s = -1;
      }
      if (!(x > 700 && y > 395) && !(x < 140 && y > 400))
      {
         if (tx_s >= 0) s_line(&S_CAN, (int)tx_s, (int)ty_s, (int)x, (int)y, c);
         s_disc(&S_CAN, (int)x, (int)y, 3, c);
         tx_s = x; ty_s = y;
      }
      float sx = x * (float)g_sw / (float)DRC_W, sy = y * (float)g_sh / (float)DRC_H;
      if (trail_n < 48) { trail[trail_n][0] = sx; trail[trail_n][1] = sy; trail_n++; }
      else { memmove(trail[0], trail[1], sizeof(trail[0]) * 47); trail[47][0] = sx; trail[47][1] = sy; }
   }
   else
   {
      tx_s = -1;
      if (trail_n > 0) trail_n--;
   }
   for (int i = 0; i < 16; i++) rip[i].age += dt;
}

static void rotate(float *x, float *y, float *z, float cx_, float sx_, float cy_, float sy_, float cz_, float sz_)
{
   float a = *x * cy_ + *z * sy_, c = -*x * sy_ + *z * cy_;
   float b = *y * cx_ - c * sx_;
   c = *y * sx_ + c * cx_;
   float d = a * cz_ - b * sz_, e = a * sz_ + b * cz_;
   *x = d; *y = e; *z = c;
}

static void render(void)
{
   const int W = g_sw, H = g_sh;
   s_vgrad(&S_SCN, 0, 0, W, H, RGB(10, 8, 30), RGB(26, 14, 52));
   // Scrolling grid.
   int off = (int)(g_time * 8.0f) % 16;
   u32 gc = RGB(34, 28, 78);
   for (int y = H / 3 + off % 8; y < H; y += 10) s_hline(&S_SCN, 0, y, W, gc);
   for (int x = -16 + off; x < W; x += 16) s_vline(&S_SCN, x, H / 3, H, gc);

   for (int i = 0; i < 16; i++)
   {
      if (rip[i].age > 1.2f) continue;
      int r = (int)(rip[i].age * 70.0f), k = (int)((1.0f - rip[i].age / 1.2f) * 255.0f);
      s_ring(&S_SCN, (int)rip[i].x, (int)rip[i].y, r, col_scale(COL_CYAN, k));
      s_ring(&S_SCN, (int)rip[i].x, (int)rip[i].y, r / 2, col_scale(COL_PINK, k));
   }
   for (int i = 1; i < trail_n; i++)
      s_line(&S_SCN, (int)trail[i - 1][0], (int)trail[i - 1][1], (int)trail[i][0], (int)trail[i][1],
             col_scale(COL_ACCENT, 80 + i * 3));

   // Cube.
   static const float V[8][3] = { {-1,-1,-1},{1,-1,-1},{1,1,-1},{-1,1,-1},{-1,-1,1},{1,-1,1},{1,1,1},{-1,1,1} };
   static const int F[6][4] = { {0,1,2,3},{5,4,7,6},{4,0,3,7},{1,5,6,2},{3,2,6,7},{4,5,1,0} };
   static const float N[6][3] = { {0,0,-1},{0,0,1},{-1,0,0},{1,0,0},{0,1,0},{0,-1,0} };
   static const u32 FC[6] = { RGB(255,120,80), RGB(90,200,255), RGB(120,230,130), RGB(255,210,80), RGB(200,120,255), RGB(255,100,160) };
   float ax = rot_x + tilt_x, ay = rot_y, az = rot_z - tilt_y;
   float cx_ = m_cos(ax), sx_ = m_sin(ax), cy_ = m_cos(ay), sy_ = m_sin(ay), cz_ = m_cos(az), sz_ = m_sin(az);
   float P[8][3];
   int sxp[8], syp[8];
   const float focal = (float)H * 1.0f;
   for (int i = 0; i < 8; i++)
   {
      P[i][0] = V[i][0]; P[i][1] = V[i][1]; P[i][2] = V[i][2];
      rotate(&P[i][0], &P[i][1], &P[i][2], cx_, sx_, cy_, sy_, cz_, sz_);
      float z = P[i][2] + 4.8f;
      sxp[i] = W / 2 + (int)(P[i][0] * focal / z * 1.25f);
      syp[i] = H / 2 + (int)(P[i][1] * focal / z * 1.25f);
   }
   int order[6];
   float depth[6];
   for (int f = 0; f < 6; f++)
   {
      order[f] = f;
      depth[f] = (P[F[f][0]][2] + P[F[f][1]][2] + P[F[f][2]][2] + P[F[f][3]][2]) * 0.25f;
   }
   for (int i = 0; i < 6; i++)
      for (int j = i + 1; j < 6; j++)
         if (depth[order[j]] > depth[order[i]]) { int t = order[i]; order[i] = order[j]; order[j] = t; }
   for (int k = 0; k < 6; k++)
   {
      int f = order[k];
      float nx = N[f][0], ny = N[f][1], nz = N[f][2];
      rotate(&nx, &ny, &nz, cx_, sx_, cy_, sy_, cz_, sz_);
      if (nz > 0.0f) continue;             // facing away from the camera
      float lit = 0.35f + 0.65f * m_clamp(-nx * 0.3f - ny * 0.6f - nz * 0.7f, 0.0f, 1.0f);
      u32 c = col_scale(FC[f], (int)(lit * 256.0f));
      s_tri(&S_SCN, sxp[F[f][0]], syp[F[f][0]], sxp[F[f][1]], syp[F[f][1]], sxp[F[f][2]], syp[F[f][2]], c);
      s_tri(&S_SCN, sxp[F[f][0]], syp[F[f][0]], sxp[F[f][2]], syp[F[f][2]], sxp[F[f][3]], syp[F[f][3]], c);
      for (int e = 0; e < 4; e++)
      {
         int a = F[f][e], b = F[f][(e + 1) & 3];
         s_line(&S_SCN, sxp[a], syp[a], sxp[b], syp[b], col_scale(COL_WHITE, 220));
      }
   }
}

static void stick(Surf *s, int cx, int cy, int r, float x, float y, const char *label)
{
   s_disc(s, cx, cy, r, RGB(22, 18, 48));
   s_ring(s, cx, cy, r, COL_DIM);
   s_hline(s, cx - r, cy, 2 * r, RGB(60, 55, 100));
   s_vline(s, cx, cy - r, 2 * r, RGB(60, 55, 100));
   int px = cx + (int)(x * (float)r * 0.9f), py = cy - (int)(y * (float)r * 0.9f);
   s_line(s, cx, cy, px, py, COL_ACCENT);
   s_disc(s, px, py, r / 6 + 2, COL_ACCENT);
   s_text(s, cx - text_w(label, 2) / 2, cy + r + 8, 2, COL_DIM, label);
}

static void lamp(Surf *s, int x, int y, int w, int h, const char *label, int on)
{
   s_rect(s, x, y, w, h, on ? COL_ACCENT : COL_PANEL);
   s_box_outline(s, x, y, w, h, on ? COL_WHITE : COL_DIM);
   s_text(s, x + (w - text_w(label, 2)) / 2, y + (h - 14) / 2, 2, on ? RGB(30, 20, 10) : COL_DIM, label);
}

static void hud(void)
{
   const Input *in = &last;
   s_panel(&S_TV, 24, 24, 360, 150, COL_CYAN);
   s_textf(&S_TV, 38, 36, 2, COL_CYAN, "VPAD  %s", in->vpad_ok ? "GAMEPAD OK" : "NO GAMEPAD");
   s_textf(&S_TV, 38, 62, 2, COL_WHITE, "ACC  %5.2f %5.2f %5.2f", in->acc[0], in->acc[1], in->acc[2]);
   s_textf(&S_TV, 38, 86, 2, COL_WHITE, "GYRO %5.2f %5.2f %5.2f", in->gyro[0], in->gyro[1], in->gyro[2]);
   s_textf(&S_TV, 38, 110, 2, COL_WHITE, "TOUCH %s %3d,%3d", in->touched ? "DOWN" : "UP  ", (int)in->tx, (int)in->ty);
   s_textf(&S_TV, 38, 140, 2, COL_ACCENT, "PRO CONTROLLER %s", in->pro ? "YES" : "NO");
   stick(&S_TV, 120, 560, 70, in->lx, in->ly, "LEFT STICK");
   stick(&S_TV, 1160, 560, 70, in->rx, in->ry, "RIGHT STICK");
   static const struct { const char *l; u32 b; } btn[] = {
      { "ZL", B_ZL }, { "L", B_L }, { "UP", B_UP }, { "DN", B_DOWN }, { "LT", B_LEFT }, { "RT", B_RIGHT },
      { "-", B_MINUS }, { "+", B_PLUS }, { "Y", B_Y }, { "X", B_X }, { "B", B_B }, { "A", B_A }, { "R", B_R }, { "ZR", B_ZR } };
   for (int i = 0; i < 14; i++)
      lamp(&S_TV, 232 + i * 56, 640, 50, 34, btn[i].l, (in->hold & btn[i].b) != 0);
   if (rumble_t > 0) s_text_sh(&S_TV, 500, 100, 4, COL_RED, "RUMBLE!");
}

static void drc(const Input *in)
{
   for (int y = 0; y < DRC_H; y++)
      memcpy(S_DRC.p + y * S_DRC.pitch, canvas + y * DRC_W, DRC_W * 4);
   s_rect_a(&S_DRC, 0, 0, DRC_W, 30, RGB(0, 0, 0), 150);
   s_text_sh(&S_DRC, 12, 8, 2, COL_ACCENT, "INPUT LAB  DRAW WITH YOUR FINGER");
   stick(&S_DRC, 70, 150, 44, in->lx, in->ly, "L");
   stick(&S_DRC, 784, 150, 44, in->rx, in->ry, "R");
   s_rect_a(&S_DRC, 150, 40, 554, 52, COL_PANEL, 190);
   s_textf(&S_DRC, 160, 48, 2, COL_WHITE, "ACC %5.2f %5.2f %5.2f", in->acc[0], in->acc[1], in->acc[2]);
   s_textf(&S_DRC, 160, 70, 2, COL_WHITE, "GYRO %5.2f %5.2f %5.2f    TOUCH %d,%d", in->gyro[0], in->gyro[1], in->gyro[2], (int)in->tx, (int)in->ty);
   // Tilt bar: accelerometer x/y as a bubble level.
   int bx = 427, by = 330;
   s_ring(&S_DRC, bx, by, 38, COL_DIM);
   s_disc(&S_DRC, bx + (int)(m_clamp(in->acc[0], -1.0f, 1.0f) * 34), by - (int)(m_clamp(in->acc[1], -1.0f, 1.0f) * 34), 6, COL_GREEN);
   lamp(&S_DRC, 12, 420, 128, 48, "CLEAR", 0);
   int on = rumble_t > 0;
   s_rect(&S_DRC, 700, 405, 142, 62, on ? COL_RED : COL_PANEL);
   s_box_outline(&S_DRC, 700, 405, 142, 62, on ? COL_WHITE : COL_PINK);
   s_text_sh(&S_DRC, 700 + (142 - text_w("RUMBLE", 3)) / 2, 427, 3, COL_WHITE, "RUMBLE");
   s_text_sh(&S_DRC, 160, 446, 2, COL_DIM, "A = RUMBLE   X = CLEAR   STICKS SPIN THE CUBE");
}

const Scene sc_inputlab = {
   "INPUT LAB", "TOUCH, STICKS, BUTTONS, GYRO, ACCELEROMETER AND RUMBLE", 4, enter, update, render, hud, drc
};
