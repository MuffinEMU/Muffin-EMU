// Small math/colour helpers. No libm: everything here is self-contained so the RPX links with
// nothing beyond wut and newlib's libc.
#include "showcase.h"
#include <string.h>

static float sintab[1025];
static u32 g_rng = 0x1234ABCDu;

void util_init(void)
{
   for (int i = 0; i <= 1024; i++)
   {
      double x = (double)i * 6.283185307179586 / 1024.0;
      if (x > 3.141592653589793) x -= 6.283185307179586;
      double x2 = x * x;
      double s = x * (1.0 - x2 / 6.0 * (1.0 - x2 / 20.0 * (1.0 - x2 / 42.0 * (1.0 - x2 / 72.0 * (1.0 - x2 / 110.0 * (1.0 - x2 / 156.0))))));
      sintab[i] = (float)s;
   }
   sintab[1024] = sintab[0];
}

int m_floor(float x)
{
   int i = (int)x;
   return (x < (float)i) ? i - 1 : i;
}

float m_abs(float x) { return x < 0 ? -x : x; }
float m_clamp(float x, float lo, float hi) { return x < lo ? lo : (x > hi ? hi : x); }
float m_mix(float a, float b, float t) { return a + (b - a) * t; }

float m_sin(float x)
{
   float t = x * (1024.0f / TAU_F);
   int i = m_floor(t);
   float f = t - (float)i;
   int k = i & 1023;
   return sintab[k] + (sintab[k + 1] - sintab[k]) * f;
}

float m_cos(float x) { return m_sin(x + 1.57079633f); }

float m_sqrt(float x)
{
   if (x <= 0.0f) return 0.0f;
   u32 i;
   float y;
   memcpy(&i, &x, 4);
   i = 0x5f3759dfu - (i >> 1);
   memcpy(&y, &i, 4);
   y = y * (1.5f - 0.5f * x * y * y);
   y = y * (1.5f - 0.5f * x * y * y);
   y = y * (1.5f - 0.5f * x * y * y);
   return x * y;
}

float m_atan2(float y, float x)
{
   float ax = m_abs(x), ay = m_abs(y);
   float mx = ax > ay ? ax : ay;
   if (mx < 1e-12f) return 0.0f;
   float mn = ax > ay ? ay : ax;
   float a = mn / mx, s = a * a;
   float r = ((-0.0464964749f * s + 0.15931422f) * s - 0.327622764f) * s * a + a;
   if (ay > ax) r = 1.57079633f - r;
   if (x < 0) r = PI_F - r;
   if (y < 0) r = -r;
   return r;
}

float m_exp2(float x)
{
   int i = m_floor(x);
   float f = x - (float)i;
   float p = 1.0f + f * (0.6931472f + f * (0.2402265f + f * (0.0555041f + f * 0.0096181f)));
   u32 bits = (u32)(i + 127) << 23;
   float s;
   memcpy(&s, &bits, 4);
   return p * s;
}

u32 rnd_r(u32 *st)
{
   u32 x = *st;
   x ^= x << 13; x ^= x >> 17; x ^= x << 5;
   *st = x;
   return x;
}
u32 rnd(void) { return rnd_r(&g_rng); }
float frand(void) { return (float)(rnd() >> 8) * (1.0f / 16777216.0f); }
float frands(void) { return frand() * 2.0f - 1.0f; }

u32 hash2(int x, int y)
{
   u32 h = (u32)x * 374761393u + (u32)y * 668265263u;
   h = (h ^ (h >> 13)) * 1274126177u;
   return h ^ (h >> 16);
}

u32 col_mix(u32 a, u32 b, int t)
{
   int r = (int)CR(a) + (((int)CR(b) - (int)CR(a)) * t >> 8);
   int g = (int)CG(a) + (((int)CG(b) - (int)CG(a)) * t >> 8);
   int bl = (int)CB(a) + (((int)CB(b) - (int)CB(a)) * t >> 8);
   return RGB(r, g, bl);
}

u32 col_add(u32 a, u32 b)
{
   u32 r = CR(a) + CR(b), g = CG(a) + CG(b), bl = CB(a) + CB(b);
   if (r > 255) r = 255;
   if (g > 255) g = 255;
   if (bl > 255) bl = 255;
   return RGB(r, g, bl);
}

u32 col_scale(u32 c, int k)
{
   return RGB((CR(c) * (u32)k) >> 8, (CG(c) * (u32)k) >> 8, (CB(c) * (u32)k) >> 8);
}

u32 hsv(float h, float s, float v)
{
   h = h - (float)m_floor(h);
   float h6 = h * 6.0f;
   int i = (int)h6;
   float f = h6 - (float)i;
   float p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f));
   float r, g, b;
   switch (i % 6)
   {
   case 0: r = v; g = t; b = p; break;
   case 1: r = q; g = v; b = p; break;
   case 2: r = p; g = v; b = t; break;
   case 3: r = p; g = q; b = v; break;
   case 4: r = t; g = p; b = v; break;
   default: r = v; g = p; b = q; break;
   }
   return RGB((int)(r * 255.0f), (int)(g * 255.0f), (int)(b * 255.0f));
}
