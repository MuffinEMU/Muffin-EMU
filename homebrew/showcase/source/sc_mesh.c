// Scene 4: 3D mesh lab. A complete software triangle pipeline on the PPC cores: a 7,680 triangle
// trefoil torus knot and three UV spheres are transformed and projected on the main core, then
// rasterised into a 640x360 z-buffer by all three cores working on interleaved 24-row stripes.
// Every covered pixel is shaded per pixel from an interpolated normal: environment-mapped chrome,
// gold, pearl and glass (Schlick Fresnel, refraction, studio softbox lights), glossy ceramic with
// a Blinn-Phong highlight, sphere-in-knot reflections solved analytically, and a filtered checker
// floor with soft contact shadows and a mirrored-geometry reflection pass. Silhouettes are
// anti-aliased from an object-id buffer in a second parallel pass.
#include "showcase.h"

#include <coreinit/time.h>
#include <string.h>

#define NK_S 240
#define NK_R 16
#define NS_LAT 16
#define NS_LON 24
#define KV (NK_S * NK_R)
#define SV ((NS_LAT + 1) * (NS_LON + 1))
#define NSPH 3
#define MAXV (KV + NSPH * SV)
#define KT (2 * NK_S * NK_R)
#define ST (2 * NS_LAT * NS_LON)
#define MAXT (KT + NSPH * ST)
#define FLOOR_Y (-2.15f)
#define STRIPE 24
#define ID_FLOOR 255

typedef struct { float sx, sy, iz, nx, ny, nz, u, v; } MV;   // 32 bytes: one cache line

// Rest-pose geometry.
static float rv[MAXV][6];                 // x y z nx ny nz
static float ruv[MAXV][2];
static u16 tri_i[MAXT][3];
static u8 tri_obj[MAXT];
static int obj_v0[1 + NSPH], obj_nv[1 + NSPH], obj_t0[1 + NSPH], obj_nt[1 + NSPH];
static int built;

// Per-frame transformed vertices: [0] real, [1] mirrored in the floor.
static MV tv[2][MAXV] __attribute__((aligned(32)));
static float tw[MAXV][3];                 // world positions (real), for nothing but debugging aids

static float zbuf[SCN_W * SCN_H] __attribute__((aligned(32)));
static float mzbuf[SCN_W * SCN_H] __attribute__((aligned(32)));
static u8 idbuf[SCN_W * SCN_H] __attribute__((aligned(32)));

enum { K_CHROME, K_GOLD, K_PEARL, K_GLASS, K_CERAMIC, NKIND };
static const char *kKindName[NKIND] = { "CHROME", "GOLD", "PEARL", "GLASS", "CERAMIC" };

static int s_knot_kind = K_CHROME;
static float cam_yaw = 0.6f, cam_pitch = 0.28f, cam_dist = 8.4f, spin = 0.0f, spin_speed = 0.55f;
static int s_auto_orbit = 1, s_spin_on = 1;
static float s_idle_t, s_demo_mat_t;
static float s_job_ms[PAR_JOBS];
static int s_job_px[PAR_JOBS];
static int s_tris_drawn;

// Frame constants shared with the jobs.
typedef struct
{
   float cam[3], right[3], up[3], fwd[3];
   float f, inv_f, cx, cy;
   float sph[NSPH][4];      // world centre and radius
   u32 sph_col[NSPH];
   int sph_kind[NSPH];
   int knot_kind;
   float knot_c[3];
   float t;
} MCtx;
static MCtx g_c;

static float s_Lk[3], s_Lf[3], s_Lr[3];

// ------------------------------------------------------------------ geometry

static void norm3(float *v)
{
   float l = m_sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
   if (l < 1e-6f) return;
   v[0] /= l; v[1] /= l; v[2] /= l;
}

static void knot_point(float t, float *p)
{
   float r = 2.0f + m_cos(3.0f * t);
   p[0] = r * m_cos(2.0f * t) * 0.5f;
   p[1] = m_sin(3.0f * t) * 0.5f;
   p[2] = r * m_sin(2.0f * t) * 0.5f;
}

static void build_meshes(void)
{
   int v = 0, t = 0;
   // Torus knot: Frenet frame from finite differences.
   obj_v0[0] = 0; obj_t0[0] = 0;
   for (int i = 0; i < NK_S; i++)
   {
      float tt = TAU_F * (float)i / (float)NK_S, h = 0.01f;
      float p0[3], pm[3], pp[3];
      knot_point(tt, p0); knot_point(tt - h, pm); knot_point(tt + h, pp);
      float T[3] = { pp[0] - pm[0], pp[1] - pm[1], pp[2] - pm[2] };
      norm3(T);
      float dd[3] = { pp[0] - 2 * p0[0] + pm[0], pp[1] - 2 * p0[1] + pm[1], pp[2] - 2 * p0[2] + pm[2] };
      float dt = dd[0] * T[0] + dd[1] * T[1] + dd[2] * T[2];
      float N[3] = { dd[0] - T[0] * dt, dd[1] - T[1] * dt, dd[2] - T[2] * dt };
      norm3(N);
      float B[3] = { T[1] * N[2] - T[2] * N[1], T[2] * N[0] - T[0] * N[2], T[0] * N[1] - T[1] * N[0] };
      for (int j = 0; j < NK_R; j++)
      {
         float ph = TAU_F * (float)j / (float)NK_R;
         float c = m_cos(ph), s = m_sin(ph);
         float n[3] = { c * N[0] + s * B[0], c * N[1] + s * B[1], c * N[2] + s * B[2] };
         const float rad = 0.30f;
         rv[v][0] = p0[0] + n[0] * rad; rv[v][1] = p0[1] + n[1] * rad; rv[v][2] = p0[2] + n[2] * rad;
         rv[v][3] = n[0]; rv[v][4] = n[1]; rv[v][5] = n[2];
         ruv[v][0] = (float)i / (float)NK_S; ruv[v][1] = (float)j / (float)NK_R;
         v++;
      }
   }
   obj_nv[0] = v;
   for (int i = 0; i < NK_S; i++)
      for (int j = 0; j < NK_R; j++)
      {
         int i1 = (i + 1) % NK_S, j1 = (j + 1) % NK_R;
         int a = i * NK_R + j, b = i1 * NK_R + j, c = i1 * NK_R + j1, d = i * NK_R + j1;
         tri_i[t][0] = (u16)a; tri_i[t][1] = (u16)b; tri_i[t][2] = (u16)c; tri_obj[t++] = 1;
         tri_i[t][0] = (u16)a; tri_i[t][1] = (u16)c; tri_i[t][2] = (u16)d; tri_obj[t++] = 1;
      }
   obj_nt[0] = t;
   // Unit spheres.
   for (int o = 0; o < NSPH; o++)
   {
      obj_v0[1 + o] = v; obj_t0[1 + o] = t;
      for (int la = 0; la <= NS_LAT; la++)
      {
         float th = PI_F * (float)la / (float)NS_LAT;
         for (int lo = 0; lo <= NS_LON; lo++)
         {
            float ph = TAU_F * (float)lo / (float)NS_LON;
            float x = m_sin(th) * m_cos(ph), y = m_cos(th), z = m_sin(th) * m_sin(ph);
            rv[v][0] = x; rv[v][1] = y; rv[v][2] = z; rv[v][3] = x; rv[v][4] = y; rv[v][5] = z;
            ruv[v][0] = (float)lo / (float)NS_LON; ruv[v][1] = (float)la / (float)NS_LAT;
            v++;
         }
      }
      int base = obj_v0[1 + o];
      for (int la = 0; la < NS_LAT; la++)
         for (int lo = 0; lo < NS_LON; lo++)
         {
            int a = base + la * (NS_LON + 1) + lo, b = a + 1, c = a + (NS_LON + 1), d = c + 1;
            tri_i[t][0] = (u16)a; tri_i[t][1] = (u16)c; tri_i[t][2] = (u16)b; tri_obj[t++] = (u8)(2 + o);
            tri_i[t][0] = (u16)b; tri_i[t][1] = (u16)c; tri_i[t][2] = (u16)d; tri_obj[t++] = (u8)(2 + o);
         }
      obj_nv[1 + o] = v - base;
      obj_nt[1 + o] = t - obj_t0[1 + o];
   }
   built = 1;
}

// ------------------------------------------------------------------ shading helpers

static inline float rs(float x)
{
   u32 i;
   float y;
   memcpy(&i, &x, 4);
   i = 0x5f3759dfu - (i >> 1);
   memcpy(&y, &i, 4);
   y = y * (1.5f - 0.5f * x * y * y);
   return y * (1.5f - 0.5f * x * y * y);
}

static inline float sat(float x) { return x < 0.0f ? 0.0f : (x > 1.0f ? 1.0f : x); }
static inline float sstep(float a, float b, float x) { float t = sat((x - a) / (b - a)); return t * t * (3.0f - 2.0f * t); }
static inline float dot3(const float *a, const float *b) { return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]; }

// Studio environment: sky gradient, a warm key softbox, a cool fill, a magenta rim and an overhead
// strip light. Directions are unit length, y up.
static inline void env(const float *R, float *o)
{
   float ry = R[1];
   float up = ry > 0.0f ? ry : 0.0f;
   float t = m_sqrt(up);
   // Dusky studio: pale horizon glow rising into a deep blue ceiling.
   float r = 0.50f + (0.05f - 0.50f) * t, g = 0.48f + (0.09f - 0.48f) * t, b = 0.58f + (0.26f - 0.58f) * t;
   float hz = 1.0f - sat(m_abs(ry) * 4.0f);
   r += hz * 0.18f; g += hz * 0.10f; b += hz * 0.06f;
   float k = sat((dot3(R, s_Lk) - 0.84f) * 6.5f);
   k = k * k * (3.0f - 2.0f * k);
   r += k * 3.6f; g += k * 3.3f; b += k * 2.8f;
   float f = sat((dot3(R, s_Lf) - 0.78f) * 5.0f);
   f = f * f * (3.0f - 2.0f * f);
   r += f * 0.9f; g += f * 1.5f; b += f * 2.2f;
   float rm = sat((dot3(R, s_Lr) - 0.80f) * 5.0f);
   rm = rm * rm * (3.0f - 2.0f * rm);
   r += rm * 2.0f; g += rm * 0.45f; b += rm * 1.6f;
   float st = (1.0f - sstep(0.06f, 0.20f, m_abs(R[0]))) * sstep(0.35f, 0.7f, ry);
   r += st * 1.6f; g += st * 1.6f; b += st * 1.7f;
   if (ry < 0.0f)
   {
      float d = sat(-ry * 2.4f);
      r = r * (1.0f - d) + 0.05f * d; g = g * (1.0f - d) + 0.05f * d; b = b * (1.0f - d) + 0.08f * d;
   }
   o[0] = r; o[1] = g; o[2] = b;
}

static inline u32 pack(float r, float g, float b)
{
   // Soft shoulder so the hot softboxes roll off instead of clipping flat.
   r = r / (1.0f + r * 0.18f) * 1.18f; g = g / (1.0f + g * 0.18f) * 1.18f; b = b / (1.0f + b * 0.18f) * 1.18f;
   int ir = (int)(sat(r) * 255.0f), ig = (int)(sat(g) * 255.0f), ib = (int)(sat(b) * 255.0f);
   return RGB(ir, ig, ib);
}

static inline float pow5(float x) { float x2 = x * x; return x2 * x2 * x; }

// Nearest sphere hit along a ray; returns shaded colour in o and 1, or 0 on a miss.
static int sphere_hit(const MCtx *c, const float *P, const float *R, int skip, float *o)
{
   float best = 1e9f;
   int bi = -1;
   for (int i = 0; i < NSPH; i++)
   {
      if (i == skip) continue;
      float ox = P[0] - c->sph[i][0], oy = P[1] - c->sph[i][1], oz = P[2] - c->sph[i][2];
      float b = ox * R[0] + oy * R[1] + oz * R[2];
      float cc = ox * ox + oy * oy + oz * oz - c->sph[i][3] * c->sph[i][3];
      float disc = b * b - cc;
      if (disc <= 0.0f) continue;
      float tt = -b - m_sqrt(disc);
      if (tt > 0.02f && tt < best) { best = tt; bi = i; }
   }
   if (bi < 0) return 0;
   float H[3] = { P[0] + R[0] * best, P[1] + R[1] * best, P[2] + R[2] * best };
   float n[3] = { (H[0] - c->sph[bi][0]) / c->sph[bi][3], (H[1] - c->sph[bi][1]) / c->sph[bi][3], (H[2] - c->sph[bi][2]) / c->sph[bi][3] };
   float rr[3] = { R[0] - 2.0f * dot3(R, n) * n[0], R[1] - 2.0f * dot3(R, n) * n[1], R[2] - 2.0f * dot3(R, n) * n[2] };
   float e[3];
   env(rr, e);
   u32 col = c->sph_col[bi];
   float dl = 0.25f + 0.75f * sat(dot3(n, s_Lk));
   float fr = 0.12f + 0.88f * pow5(1.0f - sat(-dot3(R, n)));
   int kd = c->sph_kind[bi];
   float m = kd == K_GOLD ? 0.9f : 0.35f;
   o[0] = (float)CR(col) * (1.0f / 255.0f) * dl * (1.0f - m) + e[0] * (m * 0.8f + fr * 0.3f) * (kd == K_GOLD ? 1.0f : 0.8f);
   o[1] = (float)CG(col) * (1.0f / 255.0f) * dl * (1.0f - m) + e[1] * (m * 0.8f + fr * 0.3f) * (kd == K_GOLD ? 0.78f : 0.8f);
   o[2] = (float)CB(col) * (1.0f / 255.0f) * dl * (1.0f - m) + e[2] * (m * 0.8f + fr * 0.3f) * (kd == K_GOLD ? 0.34f : 0.8f);
   return 1;
}

// Shades one surface sample. n is the interpolated (unnormalised) normal, D the unit view ray.
static u32 shade_surface(const MCtx *c, int obj, int kind, float nx, float ny, float nz, float u, float v,
                         const float *D, const float *P, u32 base)
{
   float il = rs(nx * nx + ny * ny + nz * nz + 1e-8f);
   float N[3] = { nx * il, ny * il, nz * il };
   float cs = -dot3(N, D);
   if (cs < 0.0f) cs = 0.0f;
   float R[3] = { D[0] + 2.0f * cs * N[0], D[1] + 2.0f * cs * N[1], D[2] + 2.0f * cs * N[2] };
   float e[3], out[3];
   float fr = pow5(1.0f - cs);
   float br = (float)CR(base) * (1.0f / 255.0f), bg = (float)CG(base) * (1.0f / 255.0f), bb = (float)CB(base) * (1.0f / 255.0f);
   switch (kind)
   {
   case K_CHROME:
   case K_GOLD:
   {
      env(R, e);
      float F = 0.72f + 0.28f * fr;
      float tr = 0.93f, tg = 0.95f, tb = 1.0f;
      if (kind == K_GOLD) { tr = 1.0f; tg = 0.76f; tb = 0.30f; }
      if (obj == 1 && kind == K_CHROME)
      {
         // Thin gold inlay running around the tube.
         float st = u * 24.0f; st -= (float)m_floor(st);
         float vv = v - (float)m_floor(v);
         if (st < 0.10f || (vv > 0.46f && vv < 0.54f && st > 0.5f)) { tr = 1.0f; tg = 0.72f; tb = 0.28f; }
      }
      out[0] = e[0] * tr * F; out[1] = e[1] * tg * F; out[2] = e[2] * tb * F;
      float h[3];
      if (obj == 1 && sphere_hit(c, P, R, -1, h))
      {
         out[0] = h[0] * tr * 0.9f; out[1] = h[1] * tg * 0.9f; out[2] = h[2] * tb * 0.9f;
      }
      break;
   }
   case K_PEARL:
   {
      env(R, e);
      float dl = 0.30f + 0.80f * sat(dot3(N, s_Lk)) + 0.22f * sat(dot3(N, s_Lf));
      float ph = cs * 7.0f + u * 6.0f;
      float ir = 0.65f + 0.35f * m_sin(ph), ig = 0.65f + 0.35f * m_sin(ph + 2.1f), ib = 0.65f + 0.35f * m_sin(ph + 4.2f);
      float F = 0.18f + 0.82f * fr;
      out[0] = 0.86f * dl * 0.85f + e[0] * ir * F * 0.9f;
      out[1] = 0.84f * dl * 0.85f + e[1] * ig * F * 0.9f;
      out[2] = 0.88f * dl * 0.85f + e[2] * ib * F * 0.9f;
      break;
   }
   case K_GLASS:
   {
      env(R, e);
      const float eta = 1.0f / 1.45f;
      float k = 1.0f - eta * eta * (1.0f - cs * cs);
      float T[3];
      if (k > 0.0f)
      {
         float a = eta * cs - m_sqrt(k);
         T[0] = eta * D[0] + a * N[0]; T[1] = eta * D[1] + a * N[1]; T[2] = eta * D[2] + a * N[2];
      }
      else { T[0] = R[0]; T[1] = R[1]; T[2] = R[2]; }
      float t2[3];
      env(T, t2);
      float F = 0.05f + 0.95f * fr;
      out[0] = e[0] * F + t2[0] * (1.0f - F) * 0.72f * (0.55f + 0.45f * br);
      out[1] = e[1] * F + t2[1] * (1.0f - F) * 0.82f * (0.60f + 0.40f * bg);
      out[2] = e[2] * F + t2[2] * (1.0f - F) * 0.95f * (0.70f + 0.30f * bb);
      out[0] += 0.04f; out[1] += 0.06f; out[2] += 0.10f;
      break;
   }
   default:   // K_CERAMIC
   {
      env(R, e);
      float dk = sat(dot3(N, s_Lk)), df = sat(dot3(N, s_Lf));
      float diff = 0.22f + 0.95f * dk + 0.28f * df;
      float H[3] = { s_Lk[0] - D[0], s_Lk[1] - D[1], s_Lk[2] - D[2] };
      float nh = sat(dot3(N, H) * rs(dot3(H, H) + 1e-6f));
      float sp = nh * nh; sp *= sp; sp *= sp; sp *= sp; sp *= sp; sp *= sp;   // ^64
      float F = 0.04f + 0.96f * fr;
      out[0] = br * diff + sp * 1.3f + e[0] * F * 0.8f;
      out[1] = bg * diff + sp * 1.25f + e[1] * F * 0.8f;
      out[2] = bb * diff + sp * 1.2f + e[2] * F * 0.8f;
      break;
   }
   }
   return pack(out[0], out[1], out[2]);
}

// ------------------------------------------------------------------ floor and sky

static float checker_f(float x, float z, float w)
{
   float fx = (x - 0.5f * w) * 0.5f, gx = (x + 0.5f * w) * 0.5f;
   float fz = (z - 0.5f * w) * 0.5f, gz = (z + 0.5f * w) * 0.5f;
   float ax = m_abs(fx - (float)m_floor(fx) - 0.5f) - m_abs(gx - (float)m_floor(gx) - 0.5f);
   float az = m_abs(fz - (float)m_floor(fz) - 0.5f) - m_abs(gz - (float)m_floor(gz) - 0.5f);
   float ix = 2.0f * ax / w, iz = 2.0f * az / w;
   return 0.5f - 0.5f * ix * iz;
}

static u32 shade_bg(const MCtx *c, const float *D, float dxv, int *is_floor)
{
   (void)dxv;
   *is_floor = 0;
   float e[3];
   if (D[1] >= -0.003f)
   {
      env(D, e);
      return pack(e[0], e[1], e[2]);
   }
   *is_floor = 1;
   float s = (FLOOR_Y - c->cam[1]) / D[1];    // distance along the unit ray
   float H[3] = { c->cam[0] + D[0] * s, FLOOR_Y, c->cam[2] + D[2] * s };
   float w = s * c->inv_f * (1.0f + 1.0f / (m_abs(D[1]) + 0.06f)) * 0.55f + 0.004f;
   float ck = checker_f(H[0] * 0.8f, H[2] * 0.8f, w * 0.8f);
   if (w > 1.5f) ck = 0.5f;
   float dark = 0.055f, light = 0.19f;
   float base = dark + (light - dark) * ck;
   // Soft contact shadows under the spheres and the knot.
   float sh = 1.0f;
   for (int i = 0; i < NSPH; i++)
   {
      float dx = H[0] - c->sph[i][0], dz = H[2] - c->sph[i][2];
      float r = c->sph[i][3] * 1.5f;
      float t = 1.0f - (dx * dx + dz * dz) / (r * r);
      if (t > 0.0f) sh -= 0.55f * t * t;
   }
   {
      float dx = H[0] - c->knot_c[0], dz = H[2] - c->knot_c[2];
      float t = 1.0f - (dx * dx + dz * dz) / (3.2f * 3.2f);
      if (t > 0.0f) sh -= 0.45f * t * t;
   }
   if (sh < 0.15f) sh = 0.15f;
   // Light pool from the key light plus a faint blue tint in the dark squares.
   float pool = 1.0f / (1.0f + (H[0] * H[0] + H[2] * H[2]) * 0.018f);
   float lit = (0.5f + 1.2f * pool) * sh;
   float Rf[3] = { D[0], -D[1], D[2] };
   env(Rf, e);
   float F = 0.06f + 0.94f * pow5(1.0f - sat(-D[1]));
   float r = base * lit * 0.95f + e[0] * F * 0.55f * sh;
   float g = base * lit * 0.95f + e[1] * F * 0.55f * sh;
   float b = base * lit * 1.18f + e[2] * F * 0.55f * sh + 0.012f;
   // Haze toward the horizon, in the colour the sky has there so the two meet without a seam.
   float fade = sat((s - 10.0f) * (1.0f / 30.0f));
   fade = fade * fade;
   float dh = rs(D[0] * D[0] + D[2] * D[2] + 1e-8f);
   float Dh[3] = { D[0] * dh, 0.0f, D[2] * dh };
   float hz[3];
   env(Dh, hz);
   r += (hz[0] - r) * fade; g += (hz[1] - g) * fade; b += (hz[2] - b) * fade;
   return pack(r, g, b);
}

// ------------------------------------------------------------------ rasteriser

typedef struct { int obj_kind[5]; u32 obj_col[5]; } Mats;
static Mats g_m;

static inline int owned(int y, int job, int njobs) { return ((y / STRIPE) % njobs) == job; }

static int raster(const MCtx *c, const MV *V, int t, int job, int njobs, int mirror, int *px_count)
{
   const MV *a = &V[tri_i[t][0]], *b = &V[tri_i[t][1]], *cc = &V[tri_i[t][2]];
   if (a->iz <= 0.0f || b->iz <= 0.0f || cc->iz <= 0.0f) return 0;
   float area = (b->sx - a->sx) * (cc->sy - a->sy) - (cc->sx - a->sx) * (b->sy - a->sy);
   // Front faces have positive area here; the mirror image flips the winding.
   if (mirror ? (area >= 0.0f) : (area <= 0.0f)) return 0;
   float minx = a->sx < b->sx ? (a->sx < cc->sx ? a->sx : cc->sx) : (b->sx < cc->sx ? b->sx : cc->sx);
   float maxx = a->sx > b->sx ? (a->sx > cc->sx ? a->sx : cc->sx) : (b->sx > cc->sx ? b->sx : cc->sx);
   float miny = a->sy < b->sy ? (a->sy < cc->sy ? a->sy : cc->sy) : (b->sy < cc->sy ? b->sy : cc->sy);
   float maxy = a->sy > b->sy ? (a->sy > cc->sy ? a->sy : cc->sy) : (b->sy > cc->sy ? b->sy : cc->sy);
   const int W = g_sw, H = g_sh;
   int x0 = (int)(minx - 0.5f), x1 = (int)(maxx + 0.5f), y0 = (int)(miny - 0.5f), y1 = (int)(maxy + 0.5f);
   if (x1 < 0 || y1 < 0 || x0 >= W || y0 >= H) return 0;
   if (x0 < 0) x0 = 0;
   if (y0 < 0) y0 = 0;
   if (x1 >= W) x1 = W - 1;
   if (y1 >= H) y1 = H - 1;
   if (y0 / STRIPE == y1 / STRIPE && !owned(y0, job, njobs)) return 0;
   if (y1 - y0 < STRIPE && !owned(y0, job, njobs) && !owned(y1, job, njobs)) return 0;

   // Edge functions: wa for edge b->c, wb for c->a, wc for a->b; each equals area at its vertex.
   float Aa = -(cc->sy - b->sy), Ba = (cc->sx - b->sx), Ca = -Aa * b->sx - Ba * b->sy;
   float Ab = -(a->sy - cc->sy), Bb = (a->sx - cc->sx), Cb = -Ab * cc->sx - Bb * cc->sy;
   float Ac = -(b->sy - a->sy), Bc = (b->sx - a->sx), Cc = -Ac * a->sx - Bc * a->sy;
   float inv_area = 1.0f / area;
   const float sgn = area < 0.0f ? 1.0f : -1.0f;   // inside means sgn * w <= 0
   int obj = tri_obj[t];
   int mi = obj == 1 ? 0 : obj - 1;
   int kind = g_m.obj_kind[mi];
   u32 base = g_m.obj_col[mi];
   int drawn = 0;
   for (int y = y0; y <= y1; y++)
   {
      if (!owned(y, job, njobs)) { y = (y / STRIPE + 1) * STRIPE - 1; continue; }
      float py = (float)y + 0.5f;
      float wa0 = Ba * py + Ca, wb0 = Bb * py + Cb, wc0 = Bc * py + Cc;
      // Solve each edge (area < 0, so inside means w <= 0) for the span on this row.
      float xl = (float)x0 - 0.5f, xr = (float)x1 + 0.5f;
      float cA[3] = { Aa * sgn, Ab * sgn, Ac * sgn }, cW[3] = { wa0 * sgn, wb0 * sgn, wc0 * sgn };
      int ok = 1;
      for (int e = 0; e < 3; e++)
      {
         float A = cA[e], w = cW[e];
         if (A > 1e-7f) { float xb = -w / A; if (xb < xr) xr = xb; }        // w <= 0 -> x <= -w/A
         else if (A < -1e-7f) { float xb = -w / A; if (xb > xl) xl = xb; }  // w <= 0 -> x >= -w/A
         else if (w > 0.0f) ok = 0;
      }
      if (!ok || xl > xr) continue;
      int xs = (int)(xl + 0.5f), xe = (int)(xr - 0.5f);
      if (xs < x0) xs = x0;
      if (xe > x1) xe = x1;
      for (int x = xs; x <= xe; x++)
      {
         float px = (float)x + 0.5f;
         float la = (Aa * px + wa0) * inv_area, lb = (Ab * px + wb0) * inv_area;
         float lc = 1.0f - la - lb;
         float iz = la * a->iz + lb * b->iz + lc * cc->iz;
         int idx = y * W + x;
         if (mirror)
         {
            if (idbuf[idx] != ID_FLOOR || iz <= mzbuf[idx]) continue;
            mzbuf[idx] = iz;
         }
         else
         {
            if (iz <= zbuf[idx]) continue;
            zbuf[idx] = iz;
         }
         float nx = la * a->nx + lb * b->nx + lc * cc->nx;
         float ny = la * a->ny + lb * b->ny + lc * cc->ny;
         float nz = la * a->nz + lb * b->nz + lc * cc->nz;
         float u = la * a->u + lb * b->u + lc * cc->u;
         float v = la * a->v + lb * b->v + lc * cc->v;
         float dxv = (px - c->cx) * c->inv_f, dyv = -(py - c->cy) * c->inv_f;
         float Dw[3] = { c->fwd[0] + c->right[0] * dxv + c->up[0] * dyv, c->fwd[1] + c->right[1] * dxv + c->up[1] * dyv,
                         c->fwd[2] + c->right[2] * dxv + c->up[2] * dyv };
         float il = rs(dot3(Dw, Dw));
         float D[3] = { Dw[0] * il, Dw[1] * il, Dw[2] * il };
         float z = 1.0f / iz;
         float P[3] = { c->cam[0] + Dw[0] * z, c->cam[1] + Dw[1] * z, c->cam[2] + Dw[2] * z };
         if (mirror) { P[1] = 2.0f * FLOOR_Y - P[1]; D[1] = -D[1]; }   // shade the real surface seen from the mirrored eye
         u32 col = shade_surface(c, obj, kind, nx, ny, nz, u, v, D, P, base);
         if (mirror)
         {
            // Blend the mirror image into the already shaded floor pixel.
            float fade = sat(1.0f - z * 0.035f);
            S_SCN.p[idx] = col_lerp(S_SCN.p[idx], col, (int)(fade * 120.0f));
         }
         else
         {
            S_SCN.p[idx] = col;
            idbuf[idx] = (u8)obj;
         }
         drawn++;
      }
   }
   *px_count += drawn;
   return 1;
}

typedef struct { int pass; } PassCtx;

static void mesh_job(void *vc, int job, int njobs)
{
   const PassCtx *pc = vc;
   const MCtx *c = &g_c;
   const int W = g_sw, H = g_sh;
   OSTime t0 = OSGetSystemTime();
   int px_count = 0;
   if (pc->pass == 0)
   {
      par_consume(tv, sizeof(tv));
      for (int y0 = 0; y0 < H; y0 += STRIPE)
      {
         if (!owned(y0, job, njobs)) continue;
         int y1 = y0 + STRIPE < H ? y0 + STRIPE : H;
         memset(zbuf + y0 * W, 0, (size_t)(y1 - y0) * W * 4);
         memset(mzbuf + y0 * W, 0, (size_t)(y1 - y0) * W * 4);
         memset(idbuf + y0 * W, 0, (size_t)(y1 - y0) * W);
      }
      int n = obj_t0[NSPH] + obj_nt[NSPH];
      for (int t = 0; t < n; t++) raster(c, tv[0], t, job, njobs, 0, &px_count);
      // Background and floor for every pixel no triangle covered.
      for (int y0 = 0; y0 < H; y0 += STRIPE)
      {
         if (!owned(y0, job, njobs)) continue;
         int y1 = y0 + STRIPE < H ? y0 + STRIPE : H;
         for (int y = y0; y < y1; y++)
         {
            float dyv = -((float)y + 0.5f - c->cy) * c->inv_f;
            for (int x = 0; x < W; x++)
            {
               int idx = y * W + x;
               if (idbuf[idx]) continue;
               float dxv = ((float)x + 0.5f - c->cx) * c->inv_f;
               float Dw[3] = { c->fwd[0] + c->right[0] * dxv + c->up[0] * dyv, c->fwd[1] + c->right[1] * dxv + c->up[1] * dyv,
                               c->fwd[2] + c->right[2] * dxv + c->up[2] * dyv };
               float il = rs(dot3(Dw, Dw));
               float D[3] = { Dw[0] * il, Dw[1] * il, Dw[2] * il };
               int fl;
               S_SCN.p[idx] = shade_bg(c, D, dxv, &fl);
               if (fl) idbuf[idx] = ID_FLOOR;
            }
         }
      }
      for (int t = 0; t < n; t++) raster(c, tv[1], t, job, njobs, 1, &px_count);
      for (int y0 = 0; y0 < H; y0 += STRIPE)
      {
         if (!owned(y0, job, njobs)) continue;
         int y1 = y0 + STRIPE < H ? y0 + STRIPE : H;
         par_flush(S_SCN.p + y0 * W, (size_t)(y1 - y0) * W * 4);
         par_flush(idbuf + y0 * W, (size_t)(y1 - y0) * W);
      }
   }
   else
   {
      // Silhouette anti-aliasing from the id buffer, then a light vignette.
      par_consume(S_SCN.p, (size_t)W * H * 4);
      par_consume(idbuf, (size_t)W * H);
      for (int y0 = 0; y0 < H; y0 += STRIPE)
      {
         if (!owned(y0, job, njobs)) continue;
         int y1 = y0 + STRIPE < H ? y0 + STRIPE : H;
         for (int y = y0; y < y1; y++)
         {
            u32 *row = S_SCN.p + y * W;
            const u8 *id = idbuf + y * W;
            float vy = ((float)y - c->cy) * (1.0f / (float)H);
            if (y > 0 && y < H - 1)
            {
               const u8 *iu = id - W, *idn = id + W;
               const u32 *ru = row - W, *rd = row + W;
               for (int x = 1; x < W - 1; x++)
               {
                  int me = id[x] == ID_FLOOR ? 0 : id[x];
                  int l = id[x - 1] == ID_FLOOR ? 0 : id[x - 1], r = id[x + 1] == ID_FLOOR ? 0 : id[x + 1];
                  int u = iu[x] == ID_FLOOR ? 0 : iu[x], d = idn[x] == ID_FLOOR ? 0 : idn[x];
                  if (me != l || me != r || me != u || me != d)
                  {
                     u32 h = col_avg(col_avg(row[x - 1], row[x + 1]), col_avg(ru[x], rd[x]));
                     row[x] = col_lerp(row[x], h, 150);
                  }
               }
            }
            for (int x = 0; x < W; x++)
            {
               float vx = ((float)x - c->cx) * (1.0f / (float)W);
               int k = 256 - (int)((vx * vx * 1.3f + vy * vy * 1.6f) * 150.0f);
               row[x] = col_scale(row[x], k);
            }
         }
         par_flush(S_SCN.p + y0 * W, (size_t)(y1 - y0) * W * 4);
      }
   }
   if (pc->pass == 0)
   {
      s_job_ms[job] = (float)OSTicksToMicroseconds(OSGetSystemTime() - t0) / 1000.0f;
      s_job_px[job] = px_count;
   }
}

// ------------------------------------------------------------------ per-frame transform

static void xform_object(int o, const float *R, const float *T, float s, const float *cam, const float *right,
                         const float *up, const float *fwd, float f, float cx, float cy)
{
   int v0 = obj_v0[o], nv = obj_nv[o];
   for (int i = 0; i < nv; i++)
   {
      const float *p = rv[v0 + i];
      float x = p[0] * s, y = p[1] * s, z = p[2] * s;
      float wx = R[0] * x + R[1] * y + R[2] * z + T[0];
      float wy = R[3] * x + R[4] * y + R[5] * z + T[1];
      float wz = R[6] * x + R[7] * y + R[8] * z + T[2];
      float nx = R[0] * p[3] + R[1] * p[4] + R[2] * p[5];
      float ny = R[3] * p[3] + R[4] * p[4] + R[5] * p[5];
      float nz = R[6] * p[3] + R[7] * p[4] + R[8] * p[5];
      for (int m = 0; m < 2; m++)
      {
         float py = m ? 2.0f * FLOOR_Y - wy : wy;
         float dx = wx - cam[0], dy = py - cam[1], dz = wz - cam[2];
         float vx = dx * right[0] + dy * right[1] + dz * right[2];
         float vy = dx * up[0] + dy * up[1] + dz * up[2];
         float vz = dx * fwd[0] + dy * fwd[1] + dz * fwd[2];
         MV *o2 = &tv[m][v0 + i];
         if (vz < 0.15f) { o2->iz = 0.0f; continue; }
         float iz = 1.0f / vz;
         o2->sx = cx + f * vx * iz;
         o2->sy = cy - f * vy * iz;
         o2->iz = iz;
         o2->nx = nx; o2->ny = ny; o2->nz = nz;
         o2->u = ruv[v0 + i][0]; o2->v = ruv[v0 + i][1];
      }
      tw[v0 + i][0] = wx; tw[v0 + i][1] = wy; tw[v0 + i][2] = wz;
   }
}

static void rot_yxz(float ay, float ax, float az, float *R)
{
   float cy = m_cos(ay), sy = m_sin(ay), cx = m_cos(ax), sx = m_sin(ax), cz = m_cos(az), sz = m_sin(az);
   // R = Ry * Rx * Rz
   float Rz[9] = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 };
   float Rx[9] = { 1, 0, 0, 0, cx, -sx, 0, sx, cx };
   float Ry[9] = { cy, 0, sy, 0, 1, 0, -sy, 0, cy };
   float T1[9];
   for (int i = 0; i < 3; i++)
      for (int j = 0; j < 3; j++)
         T1[i * 3 + j] = Rx[i * 3] * Rz[j] + Rx[i * 3 + 1] * Rz[3 + j] + Rx[i * 3 + 2] * Rz[6 + j];
   for (int i = 0; i < 3; i++)
      for (int j = 0; j < 3; j++)
         R[i * 3 + j] = Ry[i * 3] * T1[j] + Ry[i * 3 + 1] * T1[3 + j] + Ry[i * 3 + 2] * T1[6 + j];
}

// ------------------------------------------------------------------ scene interface

static void enter(void)
{
   if (!built) build_meshes();
   g_audio_track_override = -1;
   s_idle_t = 0.0f;
}

static void update(const Input *in, float dt, int demo)
{
   int active = m_abs(in->lx) > 0.05f || m_abs(in->ly) > 0.05f || m_abs(in->ry) > 0.05f || m_abs(in->rx) > 0.05f;
   if (!demo)
   {
      cam_yaw += in->lx * 1.8f * dt;
      cam_pitch = m_clamp(cam_pitch + in->ry * 0.9f * dt, 0.04f, 0.85f);
      cam_dist = m_clamp(cam_dist - in->ly * 5.0f * dt, 5.0f, 13.0f);
      if (in->hold & B_ZR) cam_dist = m_clamp(cam_dist - 4.0f * dt, 5.0f, 13.0f);
      if (in->hold & B_ZL) cam_dist = m_clamp(cam_dist + 4.0f * dt, 5.0f, 13.0f);
      spin += in->rx * 2.0f * dt;
      if (in->trig & B_A) s_knot_kind = (s_knot_kind + 1) % K_CERAMIC;
      if (in->trig & B_X) s_spin_on = !s_spin_on;
      if (in->trig & B_RIGHT) s_auto_orbit = !s_auto_orbit;
      if (in->touch_trig && in->ty > 392.0f && in->ty < 440.0f)
      {
         int b = (int)((in->tx - 107.0f) / 160.0f);
         if (b >= 0 && b < 4) s_knot_kind = b;
      }
   }
   else
   {
      s_demo_mat_t += dt;
      s_knot_kind = ((int)(s_demo_mat_t / 3.2f)) % 4;
      cam_dist = 8.2f + 1.2f * m_sin(g_time * 0.3f);
      cam_pitch = 0.26f + 0.10f * m_sin(g_time * 0.21f);
   }
   if (active) s_idle_t = 0.0f; else s_idle_t += dt;
   if (s_auto_orbit && (demo || s_idle_t > 0.4f || !active)) cam_yaw += 0.16f * dt;
   if (s_spin_on) spin += spin_speed * dt;
}

static void render(void)
{
   const int W = g_sw, H = g_sh;
   MCtx *c = &g_c;
   float cp = m_cos(cam_pitch), sp = m_sin(cam_pitch);
   float cyw = m_cos(cam_yaw), syw = m_sin(cam_yaw);
   const float target[3] = { 0.0f, -0.35f, 0.0f };
   c->cam[0] = target[0] + cam_dist * cp * syw;
   c->cam[1] = target[1] + cam_dist * sp;
   c->cam[2] = target[2] + cam_dist * cp * cyw;
   c->fwd[0] = target[0] - c->cam[0]; c->fwd[1] = target[1] - c->cam[1]; c->fwd[2] = target[2] - c->cam[2];
   norm3(c->fwd);
   // right = fwd x up(0,1,0), up = right x fwd
   c->right[0] = -c->fwd[2]; c->right[1] = 0.0f; c->right[2] = c->fwd[0];
   norm3(c->right);
   c->up[0] = c->right[1] * c->fwd[2] - c->right[2] * c->fwd[1];
   c->up[1] = c->right[2] * c->fwd[0] - c->right[0] * c->fwd[2];
   c->up[2] = c->right[0] * c->fwd[1] - c->right[1] * c->fwd[0];
   norm3(c->up);
   c->f = (float)H * 1.12f;
   c->inv_f = 1.0f / c->f;
   c->cx = (float)W * 0.5f;
   c->cy = (float)H * 0.5f;
   c->t = g_time;
   c->knot_kind = s_knot_kind;
   c->knot_c[0] = 0.0f; c->knot_c[1] = 0.0f; c->knot_c[2] = 0.0f;

   // Lights, fixed in world space.
   s_Lk[0] = 0.50f; s_Lk[1] = 0.75f; s_Lk[2] = 0.42f; norm3(s_Lk);
   s_Lf[0] = -0.78f; s_Lf[1] = 0.36f; s_Lf[2] = -0.30f; norm3(s_Lf);
   s_Lr[0] = 0.10f; s_Lr[1] = 0.22f; s_Lr[2] = -0.97f; norm3(s_Lr);

   static const u32 kSphCol[NSPH] = { RGB(210, 28, 40), RGB(255, 190, 80), RGB(70, 150, 255) };
   static const int kSphKind[NSPH] = { K_CERAMIC, K_GOLD, K_GLASS };
   g_m.obj_kind[0] = s_knot_kind; g_m.obj_col[0] = RGB(210, 220, 240);
   for (int i = 0; i < NSPH; i++)
   {
      float ang = g_time * 0.42f + TAU_F * (float)i / (float)NSPH;
      float rad = 0.78f + 0.06f * m_sin(g_time * 0.9f + (float)i);
      c->sph[i][0] = m_cos(ang) * 3.5f;
      c->sph[i][2] = m_sin(ang) * 3.5f;
      c->sph[i][3] = rad;
      c->sph[i][1] = FLOOR_Y + rad + 0.04f + 0.10f * (0.5f + 0.5f * m_sin(g_time * 1.7f + (float)i * 2.0f));
      c->sph_col[i] = kSphCol[i];
      c->sph_kind[i] = kSphKind[i];
      g_m.obj_kind[1 + i] = kSphKind[i]; g_m.obj_col[1 + i] = kSphCol[i];
   }

   // Transform everything.
   float R[9];
   rot_yxz(spin, 0.35f * m_sin(g_time * 0.4f) + 0.25f, 0.30f * m_sin(g_time * 0.3f), R);
   float T0[3] = { 0.0f, 0.0f, 0.0f };
   xform_object(0, R, T0, 1.0f, c->cam, c->right, c->up, c->fwd, c->f, c->cx, c->cy);
   const float I3[9] = { 1, 0, 0, 0, 1, 0, 0, 0, 1 };
   for (int i = 0; i < NSPH; i++)
      xform_object(1 + i, I3, c->sph[i], c->sph[i][3], c->cam, c->right, c->up, c->fwd, c->f, c->cx, c->cy);

   par_publish(tv, sizeof(tv));
   par_publish(&g_c, sizeof(g_c));
   par_publish(&g_m, sizeof(g_m));
   par_publish(s_Lk, sizeof(s_Lk)); par_publish(s_Lf, sizeof(s_Lf)); par_publish(s_Lr, sizeof(s_Lr));
   PassCtx p0 = { 0 }, p1 = { 1 };
   par_run(mesh_job, &p0);
   par_run(mesh_job, &p1);
   par_consume(S_SCN.p, (size_t)W * (size_t)H * 4);
   s_tris_drawn = obj_t0[NSPH] + obj_nt[NSPH];
}

static void hud(void)
{
   int px = 0;
   for (int i = 0; i < PAR_JOBS; i++) px += s_job_px[i];
   s_panel(&S_TV, 24, TV_H - 120, 420, 96, COL_CYAN);
   s_textf(&S_TV, 38, TV_H - 110, 2, COL_WHITE, "%d TRIANGLES  %d VERTS", s_tris_drawn, obj_v0[NSPH] + obj_nv[NSPH]);
   s_textf(&S_TV, 38, TV_H - 88, 2, COL_WHITE, "%d SHADED PIXELS", px);
   s_textf(&S_TV, 38, TV_H - 66, 2, COL_ACCENT, "KNOT %s  A: MATERIAL", kKindName[s_knot_kind]);
   s_textf(&S_TV, 38, TV_H - 44, 2, COL_DIM, "%dX%d  3 CORES  Z-BUFFER", g_sw, g_sh);
}

static void drc(const Input *in)
{
   (void)in;
   s_vgrad(&S_DRC, 0, 0, DRC_W, DRC_H, RGB(14, 12, 34), RGB(6, 6, 18));
   gfx_blit_scene_drc(107, 14);
   s_box_outline(&S_DRC, 106, 13, 642, 362, COL_CYAN);
   for (int b = 0; b < 4; b++)
   {
      int x = 107 + b * 160;
      int on = (b == s_knot_kind);
      s_rect(&S_DRC, x, 392, 152, 38, on ? COL_ACCENT : COL_PANEL);
      s_box_outline(&S_DRC, x, 392, 152, 38, on ? COL_WHITE : COL_DIM);
      s_text_sh(&S_DRC, x + (152 - text_w(kKindName[b], 2)) / 2, 403, 2, on ? RGB(30, 20, 10) : COL_WHITE, kKindName[b]);
   }
   for (int j = 0; j < PAR_JOBS; j++)
      s_textf(&S_DRC, 107 + j * 220, 444, 2, COL_GREEN, "CORE %d  %.1f MS", j, s_job_ms[j]);
   s_text(&S_DRC, 107, 462, 1, COL_DIM, "L STICK ORBIT  R STICK TILT AND SPIN  ZL/ZR ZOOM  X SPIN  RIGHT: AUTO ORBIT");
}

const Scene sc_mesh = {
   "3D MESH LAB", "7,680 TRIANGLE KNOT, SHADED PIXEL BY PIXEL ON THREE CORES, WITH REFLECTIONS", 3, enter, update, render, hud, drc
};
