#include "muffin.h"

#include <math.h>
#include <string.h>

#define SEGS 28
#define MAX_VERTS 7000

static Mesh sMesh;
static bool sBuilt;
static Vtx sTmp[MAX_VERTS];
static uint32_t sN;

static const float kLight[3] = {0.34f, 0.84f, 0.42f};

static float hash01(uint32_t a, uint32_t b)
{
   uint32_t h = a * 374761393u + b * 668265263u;
   h = (h ^ (h >> 13)) * 1274126177u;
   h ^= h >> 16;
   return (float)(h & 0xFFFFu) / 65535.0f;
}

static void emit(float x, float y, float z, Col c)
{
   if (sN < MAX_VERTS) {
      Vtx *v = &sTmp[sN++];
      v->x = x; v->y = y; v->z = z;
      v->r = c.r; v->g = c.g; v->b = c.b; v->a = c.a;
      v->u = SOLID_U; v->v = SOLID_V;
   }
}

static float lambert(float nx, float ny, float nz)
{
   float l = nx * kLight[0] + ny * kLight[1] + nz * kLight[2];
   if (l < 0.0f) l = 0.0f;
   return 0.42f + 0.78f * l;
}

typedef struct { float r, y; } Ring;

// body profile, bottom to top: paper cup first, then the risen dome
static const Ring kCup[2] = {{0.60f, 0.00f}, {0.90f, 1.00f}};
static const Ring kDome[9] = {
   {0.90f, 1.00f}, {1.03f, 1.12f}, {1.14f, 1.34f}, {1.16f, 1.60f}, {1.07f, 1.86f},
   {0.88f, 2.08f}, {0.58f, 2.26f}, {0.24f, 2.35f}, {0.00f, 2.37f},
};

static float dome_y_at(float r)
{
   for (int i = 0; i < 8; i++) {
      float r0 = kDome[i].r, r1 = kDome[i + 1].r;
      if (r <= r0 && r >= r1) {
         float t = (r0 - r) / (r0 - r1 + 1e-6f);
         return kDome[i].y + (kDome[i + 1].y - kDome[i].y) * t;
      }
   }
   return 2.37f;
}

static void band(const Ring *a, const Ring *b, bool cup, int ring)
{
   float dr = b->r - a->r, dy = b->y - a->y;
   float len = sqrtf(dr * dr + dy * dy);
   float nr = dy / len, ny = -dr / len;
   for (int i = 0; i < SEGS; i++) {
      float t0 = 6.28318f * (float)i / SEGS, t1 = 6.28318f * (float)(i + 1) / SEGS;
      float c0 = fcos(t0), s0 = fsin(t0), c1 = fcos(t1), s1 = fsin(t1);
      // paper pleats: radial wobble and alternating stripes
      float w0 = cup ? 1.0f + 0.05f * fcos(t0 * 14.0f) : 1.0f;
      float w1 = cup ? 1.0f + 0.05f * fcos(t1 * 14.0f) : 1.0f;
      Col base;
      if (cup) {
         base = ((i / 2) % 2) ? C(0.96f, 0.52f, 0.68f, 1) : C(1.0f, 0.86f, 0.90f, 1);
      } else {
         float k = 0.80f + 0.20f * hash01((uint32_t)i, (uint32_t)ring);
         float crown = (float)ring / 8.0f;
         base = CMIX(C(0.88f, 0.60f, 0.27f, 1), C(0.58f, 0.32f, 0.12f, 1), crown);
         base = CMUL(base, k);
      }
      float li = lambert(nr * fcos((t0 + t1) * 0.5f), ny, nr * fsin((t0 + t1) * 0.5f));
      Col c = CMUL(base, li);
      c.a = 1.0f;
      float ax0 = a->r * w0 * c0, az0 = a->r * w0 * s0, ax1 = a->r * w1 * c1, az1 = a->r * w1 * s1;
      float bx0 = b->r * w0 * c0, bz0 = b->r * w0 * s0, bx1 = b->r * w1 * c1, bz1 = b->r * w1 * s1;
      emit(ax0, a->y, az0, c); emit(bx0, b->y, bz0, c); emit(bx1, b->y, bz1, c);
      emit(ax0, a->y, az0, c); emit(bx1, b->y, bz1, c); emit(ax1, a->y, az1, c);
   }
}

static void berry(float cx, float cy, float cz, float rad, float shade)
{
   const int LAT = 6, LON = 8;
   for (int a = 0; a < LAT; a++) {
      float p0 = 3.14159f * (float)a / LAT - 1.5708f, p1 = 3.14159f * (float)(a + 1) / LAT - 1.5708f;
      for (int o = 0; o < LON; o++) {
         float t0 = 6.28318f * (float)o / LON, t1 = 6.28318f * (float)(o + 1) / LON;
         float n[4][3] = {
            {fcos(p0) * fcos(t0), fsin(p0), fcos(p0) * fsin(t0)}, {fcos(p0) * fcos(t1), fsin(p0), fcos(p0) * fsin(t1)},
            {fcos(p1) * fcos(t1), fsin(p1), fcos(p1) * fsin(t1)}, {fcos(p1) * fcos(t0), fsin(p1), fcos(p1) * fsin(t0)},
         };
         Col col[4];
         float p[4][3];
         for (int k = 0; k < 4; k++) {
            float li = lambert(n[k][0], n[k][1], n[k][2]);
            col[k] = CMUL(C(0.20f * shade, 0.24f * shade, 0.62f * shade, 1), li);
            col[k].a = 1.0f;
            p[k][0] = cx + n[k][0] * rad;
            p[k][1] = cy + n[k][1] * rad;
            p[k][2] = cz + n[k][2] * rad;
         }
         emit(p[0][0], p[0][1], p[0][2], col[0]); emit(p[1][0], p[1][1], p[1][2], col[1]); emit(p[2][0], p[2][1], p[2][2], col[2]);
         emit(p[0][0], p[0][1], p[0][2], col[0]); emit(p[2][0], p[2][1], p[2][2], col[2]); emit(p[3][0], p[3][1], p[3][2], col[3]);
      }
   }
}

void muffin_build(void)
{
   if (sBuilt) return;
   sN = 0;
   band(&kCup[0], &kCup[1], true, 0);
   for (int i = 0; i < 8; i++) band(&kDome[i], &kDome[i + 1], false, i);
   // blueberries scattered by the golden angle
   for (int i = 0; i < 13; i++) {
      float theta = 2.39996f * (float)i;
      float rr = 0.80f * sqrtf(((float)i + 0.6f) / 13.0f);
      float y = dome_y_at(rr) + 0.03f;
      berry(rr * fcos(theta), y, rr * fsin(theta), 0.115f, 0.85f + 0.3f * hash01((uint32_t)i, 7u));
   }
   sMesh = gfx_mesh_from(sTmp, sN);
   sBuilt = sMesh.n > 0;
}

void muffin_draw(const float model[16], const float viewproj[16], const Fog *fog)
{
   if (!sBuilt) return;
   float mvp[16];
   m4_mul(mvp, viewproj, model);
   gfx_draw_mesh(&sMesh, mvp, BLEND_OPAQUE, DEPTH_ON, fog);
}
