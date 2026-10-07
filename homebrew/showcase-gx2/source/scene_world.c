// Muffin Valley: a procedurally sculpted island (value-noise fBm heightmap, 128x128
// cells = 32,768 triangles), baked lighting, distance fog, animated water, floating
// muffins and four times of day. The GamePad shows a top-down map of the same mesh.

#include "app.h"
#include "audio.h"
#include "gfx.h"
#include "muffin.h"
#include "ui.h"

#include <coreinit/debug.h>

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TN 129
#define TCELL 2.0f
#define ROWS_PER_FRAME 10

typedef struct
{
   const char *name;
   float top[3], hor[3], tint[3], bright;
   float sun[3], sunCol[3], sunGlow, night;
} Tod;

static const Tod kTod[4] = {
   {"SUNSET", {0.17f, 0.20f, 0.48f}, {1.00f, 0.60f, 0.42f}, {1.12f, 0.92f, 0.82f}, 1.00f,
    {0.85f, 0.13f, -0.50f}, {1.0f, 0.72f, 0.35f}, 1.0f, 0.0f},
   {"NOON", {0.20f, 0.45f, 0.85f}, {0.72f, 0.84f, 0.95f}, {1.0f, 1.0f, 1.0f}, 1.12f,
    {0.25f, 0.92f, 0.30f}, {1.0f, 0.97f, 0.85f}, 0.5f, 0.0f},
   {"NIGHT", {0.01f, 0.02f, 0.09f}, {0.07f, 0.10f, 0.24f}, {0.50f, 0.62f, 1.0f}, 0.62f,
    {-0.45f, 0.55f, 0.70f}, {0.80f, 0.88f, 1.0f}, 0.7f, 1.0f},
   {"DAWN", {0.30f, 0.28f, 0.55f}, {1.0f, 0.72f, 0.78f}, {1.05f, 0.92f, 1.0f}, 0.95f,
    {-0.85f, 0.10f, 0.45f}, {1.0f, 0.70f, 0.75f}, 0.9f, 0.2f},
};

static float sH[TN * TN];
static Col *sCol;
static int sRows;            // heightmap rows generated so far
static bool sMeshReady;
static Mesh sTerrain;

static int sTodSel;
static Tod sCur;             // smoothed toward kTod[sTodSel]
static float sAng, sHeightOff, sYawOff, sPitchOff;
static float sEye[3];
static float sSpeedShown;

static Batch *sSky, *sSkyGlow, *sMotes, *sWater, *sMapMarks, *sMapUi;
static float sViewProj[16];
static float sMapViewProj[16];
static float sUiM[16];

// ---- noise ----------------------------------------------------------------

static uint32_t hash2(int x, int y)
{
   uint32_t h = (uint32_t)x * 374761393u + (uint32_t)y * 668265263u;
   h = (h ^ (h >> 13)) * 1274126177u;
   return h ^ (h >> 16);
}

static float vnoise(float x, float y)
{
   int xi = (int)floorf(x), yi = (int)floorf(y);
   float fx = x - (float)xi, fy = y - (float)yi;
   float u = fx * fx * (3.0f - 2.0f * fx), v = fy * fy * (3.0f - 2.0f * fy);
   float a = (float)(hash2(xi, yi) & 0xFFFFu), b = (float)(hash2(xi + 1, yi) & 0xFFFFu);
   float c = (float)(hash2(xi, yi + 1) & 0xFFFFu), d = (float)(hash2(xi + 1, yi + 1) & 0xFFFFu);
   float top = a + (b - a) * u, bot = c + (d - c) * u;
   return (top + (bot - top) * v) * (1.0f / 65535.0f);
}

static float fbm(float x, float y)
{
   float f = 0.0f, a = 0.5f;
   for (int o = 0; o < 5; o++) {
      f += a * vnoise(x, y);
      x = x * 2.03f + 17.1f;
      y = y * 2.03f + 9.7f;
      a *= 0.5f;
   }
   return f;
}

static float smoothstep(float a, float b, float x)
{
   float t = (x - a) / (b - a);
   t = t < 0.0f ? 0.0f : (t > 1.0f ? 1.0f : t);
   return t * t * (3.0f - 2.0f * t);
}

static float height_at_grid(int gx, int gz)
{
   float f = fbm((float)gx * 0.045f + 11.3f, (float)gz * 0.045f + 4.7f);
   float base = f - 0.40f;
   float h = base > 0.0f ? base * 85.0f : base * 30.0f;
   float dx = (float)gx - 64.0f, dz = (float)gz - 64.0f;
   float d = sqrtf(dx * dx + dz * dz) / 64.0f;
   float m = 1.0f - smoothstep(0.55f, 1.0f, d);
   return h * m + (-6.0f) * (1.0f - m);
}

static float world_h(float x, float z)
{
   float gx = x / TCELL + 64.0f, gz = z / TCELL + 64.0f;
   if (gx < 0.0f || gz < 0.0f || gx >= (float)(TN - 1) || gz >= (float)(TN - 1)) return -6.0f;
   int ix = (int)gx, iz = (int)gz;
   float fx = gx - (float)ix, fz = gz - (float)iz;
   float a = sH[iz * TN + ix], b = sH[iz * TN + ix + 1];
   float c = sH[(iz + 1) * TN + ix], d = sH[(iz + 1) * TN + ix + 1];
   float t = a + (b - a) * fx, bt = c + (d - c) * fx;
   return t + (bt - t) * fz;
}

// ---- mesh -----------------------------------------------------------------

static Col albedo(float h, float slope, float jit)
{
   Col c;
   if (h < -1.5f) {
      c = C(0.18f, 0.32f, 0.40f, 1);
   } else if (h < 1.3f) {
      c = CMIX(C(0.18f, 0.32f, 0.40f, 1), C(0.88f, 0.79f, 0.57f, 1), smoothstep(-1.5f, 0.2f, h));
   } else if (h < 22.0f) {
      Col lo = CMIX(C(0.30f, 0.58f, 0.20f, 1), C(0.46f, 0.66f, 0.24f, 1), jit);
      Col hi = C(0.14f, 0.36f, 0.15f, 1);
      c = CMIX(C(0.88f, 0.79f, 0.57f, 1), lo, smoothstep(1.3f, 3.5f, h));
      c = CMIX(c, hi, smoothstep(6.0f, 18.0f, h));
   } else if (h < 28.0f) {
      c = CMIX(C(0.14f, 0.36f, 0.15f, 1), C(0.52f, 0.47f, 0.43f, 1), smoothstep(22.0f, 25.0f, h));
   } else {
      c = CMIX(C(0.52f, 0.47f, 0.43f, 1), C(0.96f, 0.98f, 1.0f, 1), smoothstep(28.0f, 31.0f, h));
   }
   if (h > 1.3f) c = CMIX(c, C(0.50f, 0.45f, 0.42f, 1), smoothstep(0.55f, 0.95f, slope) * 0.85f);
   return c;
}

static void bake_colors(void)
{
   const float L[3] = {0.62f, 0.62f, 0.48f};
   float ll = sqrtf(L[0] * L[0] + L[1] * L[1] + L[2] * L[2]);
   for (int z = 0; z < TN; z++) {
      for (int x = 0; x < TN; x++) {
         int xm = x > 0 ? x - 1 : x, xp = x < TN - 1 ? x + 1 : x;
         int zm = z > 0 ? z - 1 : z, zp = z < TN - 1 ? z + 1 : z;
         float nx = sH[z * TN + xm] - sH[z * TN + xp];
         float nz = sH[zm * TN + x] - sH[zp * TN + x];
         float ny = 2.0f * TCELL;
         float nl = sqrtf(nx * nx + ny * ny + nz * nz);
         nx /= nl; ny /= nl; nz /= nl;
         float dif = (nx * L[0] + ny * L[1] + nz * L[2]) / ll;
         if (dif < 0.0f) dif = 0.0f;
         float slope = 1.0f - ny;
         float jit = (float)(hash2(x, z) & 0xFF) / 255.0f;
         Col a = albedo(sH[z * TN + x], slope * 2.2f, jit);
         float light = 0.38f + 0.85f * dif;
         sCol[z * TN + x] = C(a.r * light, a.g * light, a.b * light, 1.0f);
      }
   }
}

static void build_mesh(void)
{
   uint32_t quads = (TN - 1) * (TN - 1);
   Vtx *v = (Vtx *)malloc(sizeof(Vtx) * quads * 6);
   if (!v) return;
   uint32_t n = 0;
   for (int z = 0; z < TN - 1; z++) {
      for (int x = 0; x < TN - 1; x++) {
         int idx[4] = {z * TN + x, z * TN + x + 1, (z + 1) * TN + x + 1, (z + 1) * TN + x};
         float px[4], pz[4];
         for (int k = 0; k < 4; k++) {
            px[k] = ((float)(idx[k] % TN) - 64.0f) * TCELL;
            pz[k] = ((float)(idx[k] / TN) - 64.0f) * TCELL;
         }
         static const int tri[6] = {0, 1, 2, 0, 2, 3};
         for (int k = 0; k < 6; k++) {
            int q = tri[k];
            Vtx *o = &v[n++];
            o->x = px[q];
            o->y = sH[idx[q]];
            o->z = pz[q];
            o->r = sCol[idx[q]].r;
            o->g = sCol[idx[q]].g;
            o->b = sCol[idx[q]].b;
            o->a = 1.0f;
            o->u = SOLID_U;
            o->v = SOLID_V;
         }
      }
   }
   sTerrain = gfx_mesh_from(v, n);
   free(v);
   sMeshReady = sTerrain.n > 0;
   OSReport("showcase: terrain mesh %u vertices\n", (unsigned)sTerrain.n);
}

// ---- scene ----------------------------------------------------------------

static void world_enter(void)
{
   muffin_build();
   if (!sCol) sCol = (Col *)malloc(sizeof(Col) * TN * TN);
   sCur = kTod[sTodSel];
}

static void world_leave(void) {}

static void lerp3(float *a, const float *b, float k)
{
   for (int i = 0; i < 3; i++) a[i] += (b[i] - a[i]) * k;
}

static void ease_tod(float dt)
{
   const Tod *t = &kTod[sTodSel];
   float k = 1.0f - expf(-dt * 2.2f);
   lerp3(sCur.top, t->top, k);
   lerp3(sCur.hor, t->hor, k);
   lerp3(sCur.tint, t->tint, k);
   lerp3(sCur.sun, t->sun, k);
   lerp3(sCur.sunCol, t->sunCol, k);
   sCur.bright += (t->bright - sCur.bright) * k;
   sCur.sunGlow += (t->sunGlow - sCur.sunGlow) * k;
   sCur.night += (t->night - sCur.night) * k;
}

static bool project(const float vp[16], const float p[3], float *sx, float *sy)
{
   float cx = vp[0] * p[0] + vp[4] * p[1] + vp[8] * p[2] + vp[12];
   float cy = vp[1] * p[0] + vp[5] * p[1] + vp[9] * p[2] + vp[13];
   float cw = vp[3] * p[0] + vp[7] * p[1] + vp[11] * p[2] + vp[15];
   if (cw < 0.01f) return false;
   *sx = (cx / cw * 0.5f + 0.5f) * VW;
   *sy = (0.5f - cy / cw * 0.5f) * VH;
   return true;
}

static void world_update(float dt)
{
   float t = (float)g_time;

   // terrain generation is spread over frames so the menu never freezes
   if (sRows < TN) {
      for (int r = 0; r < ROWS_PER_FRAME && sRows < TN; r++, sRows++) {
         for (int x = 0; x < TN; x++) sH[sRows * TN + x] = height_at_grid(x, sRows);
      }
      if (sRows >= TN && sCol) {
         bake_colors();
         build_mesh();
      }
   }

   if (PRESSED(VPAD_BUTTON_X)) {
      sTodSel = (sTodSel + 1) % 4;
      audio_sfx(1);
   }
   if (g_in.touchStart) {
      for (int i = 0; i < 4; i++) {
         if (ui_hit(g_in.tx, g_in.ty, 1030.0f, 92.0f + (float)i * 62.0f, 220.0f, 52.0f)) {
            sTodSel = i;
            audio_sfx(0);
         }
      }
   }
   ease_tod(dt);

   // camera: a slow orbit that follows the land, steerable
   float boost = HELD(VPAD_BUTTON_A) ? 2.4f : 1.0f;
   float speed = 0.10f * (1.0f + g_in.lx * 1.4f) * boost;
   sSpeedShown = speed;
   sAng += speed * dt;
   sHeightOff += g_in.ly * dt * 22.0f;
   if (sHeightOff < -8.0f) sHeightOff = -8.0f;
   if (sHeightOff > 60.0f) sHeightOff = 60.0f;
   sYawOff += g_in.rx * dt * 1.8f;
   sPitchOff += g_in.ry * dt * 1.2f;
   float ret = 1.0f - dt * 0.6f;
   if (fabsf(g_in.rx) < 0.1f) sYawOff *= ret;
   if (fabsf(g_in.ry) < 0.1f) sPitchOff *= ret;
   if (sPitchOff > 0.8f) sPitchOff = 0.8f;
   if (sPitchOff < -0.8f) sPitchOff = -0.8f;

   float R = 78.0f + 12.0f * fsin(t * 0.13f);
   float ex = fcos(sAng) * R, ez = fsin(sAng) * R;
   float ground = world_h(ex, ez);
   if (ground < 0.0f) ground = 0.0f;
   float ey = ground + 16.0f + sHeightOff + 5.0f * fsin(t * 0.4f);
   float la = sAng + 0.55f;
   float tx = fcos(la) * R * 0.45f, tz = fsin(la) * R * 0.45f;
   float ty = world_h(tx, tz) * 0.5f + 4.0f;
   float dx = tx - ex, dz = tz - ez;
   float cy = fcos(sYawOff), sy = fsin(sYawOff);
   float rdx = dx * cy - dz * sy, rdz = dx * sy + dz * cy;
   float len = sqrtf(rdx * rdx + rdz * rdz);
   float dy = (ty - ey) + sPitchOff * len;
   sEye[0] = ex; sEye[1] = ey; sEye[2] = ez;

   float v[16], p[16];
   m4_lookat(v, ex, ey, ez, ex + rdx, ey + dy, ez + rdz);
   m4_persp(p, 1.0f, VW / VH, 0.5f, 700.0f);
   m4_mul(sViewProj, p, v);

   // top-down map for the GamePad
   float mv[16], mp[16];
   m4_lookat(mv, 0.0f, 215.0f, 22.0f, 0.0f, 0.0f, 0.0f);
   m4_persp(mp, 0.95f, VW / VH, 5.0f, 600.0f);
   m4_mul(sMapViewProj, mp, mv);
   m4_ortho_ui(sUiM);

   sSky = gfx_batch();
   sSkyGlow = gfx_batch();
   sMotes = gfx_batch();
   sWater = gfx_batch();
   sMapMarks = gfx_batch();
   sMapUi = gfx_batch();

   // sky
   Col top = C(sCur.top[0], sCur.top[1], sCur.top[2], 1);
   Col hor = C(sCur.hor[0], sCur.hor[1], sCur.hor[2], 1);
   ui_sky(sSky, top, CMIX(top, hor, 0.75f), hor);
   float sunPos[3] = {ex + sCur.sun[0] * 800.0f, ey + sCur.sun[1] * 800.0f, ez + sCur.sun[2] * 800.0f};
   float sx, sy2;
   if (project(sViewProj, sunPos, &sx, &sy2)) {
      Col sc = C(sCur.sunCol[0], sCur.sunCol[1], sCur.sunCol[2], 1);
      b_glow(sSkyGlow, sx, sy2, 360.0f * sCur.sunGlow + 40.0f * g_audio.beat, CA(sc, 0.35f));
      b_glow(sSkyGlow, sx, sy2, 120.0f * sCur.sunGlow, CA(sc, 0.8f));
      b_circle(sSky, sx, sy2, 34.0f * (0.7f + 0.3f * sCur.sunGlow), CA(CMIX(sc, C(1, 1, 1, 1), 0.5f), 1.0f), 28);
   }
   if (sCur.night > 0.05f) {
      for (int i = 0; i < 120; i++) {
         float x = (float)(hash2(i, 5) & 0xFFFF) / 65535.0f * VW;
         float y = (float)(hash2(i, 9) & 0xFFFF) / 65535.0f * VH * 0.5f;
         float tw = 0.5f + 0.5f * fsin(t * 2.0f + (float)i * 1.7f);
         b_glow(sSkyGlow, x, y, 4.0f + 4.0f * tw, C(1, 1, 1, sCur.night * (0.3f + 0.6f * tw)));
      }
   }

   // motes drifting through the air near the camera (fireflies at night)
   {
      float right[3] = {v[0], v[4], v[8]}, up[3] = {v[1], v[5], v[9]};
      for (int i = 0; i < 70; i++) {
         float ox = ((float)(hash2(i, 1) & 0xFFFF) / 65535.0f - 0.5f) * 90.0f;
         float oy = ((float)(hash2(i, 2) & 0xFFFF) / 65535.0f - 0.5f) * 30.0f;
         float oz = ((float)(hash2(i, 3) & 0xFFFF) / 65535.0f - 0.5f) * 90.0f;
         float ph = (float)i * 0.91f;
         float pos[3] = {ex + ox + 4.0f * fsin(t * 0.6f + ph), ey + oy - 6.0f + 3.0f * fsin(t * 0.9f + ph * 1.3f),
                         ez + oz + 4.0f * fcos(t * 0.5f + ph)};
         float tw = 0.5f + 0.5f * fsin(t * 2.5f + ph);
         Col c = sCur.night > 0.5f ? C(0.8f, 1.0f, 0.4f, 0.5f + 0.5f * tw) : C(1.0f, 0.95f, 0.8f, 0.25f * tw);
         b_billboard(sMotes, pos, right, up, 0.55f + 0.25f * tw, c);
      }
   }

   // water
   {
      const int N = 24;
      const float S = 40.0f, off = -(float)N * S * 0.5f;
      for (int zi = 0; zi < N; zi++) {
         for (int xi = 0; xi < N; xi++) {
            float xs[2] = {off + (float)xi * S, off + (float)(xi + 1) * S};
            float zs[2] = {off + (float)zi * S, off + (float)(zi + 1) * S};
            float p4[4][3];
            Col c4[4];
            for (int k = 0; k < 4; k++) {
               float wx = xs[(k == 1 || k == 2) ? 1 : 0], wz = zs[k >= 2 ? 1 : 0];
               float wave = 0.35f * fsin(wx * 0.11f + t * 1.1f) * fcos(wz * 0.09f + t * 0.9f);
               p4[k][0] = wx; p4[k][1] = wave; p4[k][2] = wz;
               float sp = 0.5f + 0.5f * fsin(wx * 0.4f + wz * 0.3f + t * 2.0f);
               c4[k] = C(0.10f + 0.10f * sp, 0.36f + 0.12f * sp, 0.55f + 0.10f * sp, 0.80f);
            }
            b_vtx(sWater, p4[0][0], p4[0][1], p4[0][2], c4[0], SOLID_U, SOLID_V);
            b_vtx(sWater, p4[1][0], p4[1][1], p4[1][2], c4[1], SOLID_U, SOLID_V);
            b_vtx(sWater, p4[2][0], p4[2][1], p4[2][2], c4[2], SOLID_U, SOLID_V);
            b_vtx(sWater, p4[0][0], p4[0][1], p4[0][2], c4[0], SOLID_U, SOLID_V);
            b_vtx(sWater, p4[2][0], p4[2][1], p4[2][2], c4[2], SOLID_U, SOLID_V);
            b_vtx(sWater, p4[3][0], p4[3][1], p4[3][2], c4[3], SOLID_U, SOLID_V);
         }
      }
   }

   // map markers: camera position and the path it follows
   for (int i = 0; i < 48; i++) {
      float a = (float)i / 48.0f * 6.28318f;
      b_box(sMapMarks, fcos(a) * 78.0f, 40.0f, fsin(a) * 78.0f, 1.3f, 1.3f, 1.3f, C(1, 1, 1, 1));
   }
   b_box(sMapMarks, ex, 60.0f, ez, 5.0f, 5.0f, 5.0f, C(1.0f, 0.25f + 0.5f * g_audio.beat, 0.25f, 1));

   // GamePad overlay
   ui_header(sMapUi, "MUFFIN VALLEY MAP", "TOP-DOWN VIEW OF THE SAME MESH");
   if (g_hud) {
      for (int i = 0; i < 4; i++) {
         ui_button(sMapUi, 1030.0f, 92.0f + (float)i * 62.0f, 220.0f, 52.0f, kTod[i].name, i == sTodSel,
                   C(kTod[i].hor[0], kTod[i].hor[1], kTod[i].hor[2], 1));
      }
      b_textf(sMapUi, 36.0f, 640.0f, 2.0f, C(1, 1, 1, 0.95f), "SPEED %.2f   HEIGHT %+.0f", sSpeedShown / 0.10f, sHeightOff);
      ui_footer(sMapUi, "TAP A TIME OF DAY   X: NEXT   LEFT STICK: SPEED+HEIGHT   RIGHT STICK: LOOK");
   }
}

static Fog make_fog(bool map)
{
   Fog f = fog_none();
   f.tr = sCur.tint[0]; f.tg = sCur.tint[1]; f.tb = sCur.tint[2];
   f.bright = sCur.bright;
   if (!map) {
      f.r = sCur.hor[0]; f.g = sCur.hor[1]; f.b = sCur.hor[2];
      f.density = 1.0f;
      f.start = 40.0f;
      f.end = 340.0f;
   }
   return f;
}

static void world_draw(Target tg)
{
   if (tg == TARGET_TV) {
      Fog fog = make_fog(false);
      gfx_draw_batch(sSky, sUiM, BLEND_ALPHA, DEPTH_OFF, NULL);
      gfx_draw_batch(sSkyGlow, sUiM, BLEND_ADD, DEPTH_OFF, NULL);
      if (sMeshReady) gfx_draw_mesh(&sTerrain, sViewProj, BLEND_OPAQUE, DEPTH_ON, &fog);

      // floating muffins
      float t = (float)g_time;
      for (int i = 0; i < 6; i++) {
         float a = (float)i * 1.0472f + 0.3f;
         float m[16], rot[16], sc[16], tmp[16];
         m4_translate(m, fcos(a) * 62.0f, 38.0f + 5.0f * fsin(t * 0.8f + (float)i), fsin(a) * 62.0f);
         m4_rot_y(rot, t * 0.4f + (float)i);
         m4_scale(sc, 4.0f, 4.0f, 4.0f);
         m4_mul(tmp, rot, sc);
         m4_mul(tmp, m, tmp);
         muffin_draw(tmp, sViewProj, &fog);
      }
      gfx_draw_batch(sWater, sViewProj, BLEND_ALPHA, DEPTH_READ, &fog);
      gfx_draw_batch(sMotes, sViewProj, BLEND_ADD, DEPTH_READ, NULL);

      Batch *ui = gfx_batch();
      char sub[80];
      if (sMeshReady) {
         snprintf(sub, sizeof(sub), "%u TRIANGLES  FOG  WATER  %s", (unsigned)(sTerrain.n / 3), kTod[sTodSel].name);
      } else {
         snprintf(sub, sizeof(sub), "SCULPTING TERRAIN %d%%", sRows * 100 / TN);
      }
      ui_header(ui, "MUFFIN VALLEY", sub);
      ui_footer(ui, "LEFT STICK: SPEED+HEIGHT   RIGHT STICK: LOOK   A: BOOST   X: TIME OF DAY   B: MENU");
      gfx_draw_batch(ui, sUiM, BLEND_ALPHA, DEPTH_OFF, NULL);
   } else {
      Fog fog = make_fog(true);
      Batch *bg = gfx_batch();
      b_rect(bg, 0, 0, VW, VH, C(0.02f, 0.05f, 0.12f, 1));
      gfx_draw_batch(bg, sUiM, BLEND_OPAQUE, DEPTH_OFF, NULL);
      if (sMeshReady) gfx_draw_mesh(&sTerrain, sMapViewProj, BLEND_OPAQUE, DEPTH_ON, &fog);
      gfx_draw_batch(sWater, sMapViewProj, BLEND_ALPHA, DEPTH_READ, &fog);
      gfx_draw_batch(sMapMarks, sMapViewProj, BLEND_OPAQUE, DEPTH_ON, &fog);
      gfx_draw_batch(sMapUi, sUiM, BLEND_ALPHA, DEPTH_OFF, NULL);
   }
}

const Scene scene_world = {
   "MUFFIN VALLEY", "33K-TRIANGLE FOG TERRAIN, WATER, SUNSET", world_enter, world_leave, world_update, NULL, world_draw, 26.0f,
};
