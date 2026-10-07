#include "ui.h"
#include "audio.h"

#include <stdio.h>
#include <string.h>

void ui_panel(Batch *b, float x, float y, float w, float h, float alpha)
{
   b_rect(b, x, y, w, h, C(0.03f, 0.02f, 0.08f, alpha));
   b_rect(b, x, y, w, 2.0f, C(1.0f, 1.0f, 1.0f, 0.10f * alpha / 0.6f));
}

void ui_bar(Batch *b, float x, float y, float w, float h, float frac, Col fill)
{
   if (frac < 0.0f) frac = 0.0f;
   if (frac > 1.0f) frac = 1.0f;
   b_rect(b, x, y, w, h, C(0.0f, 0.0f, 0.0f, 0.55f));
   if (frac > 0.0f) b_rect_grad(b, x, y, w * frac, h, CMUL(fill, 1.15f), CMUL(fill, 0.7f));
}

bool ui_hit(float tx, float ty, float x, float y, float w, float h)
{
   return tx >= x && tx <= x + w && ty >= y && ty <= y + h;
}

void ui_music_strip(Batch *b, float x, float y)
{
   // four level bars and a beat dot
   static const Col cols[CH_COUNT] = {{1.0f, 0.55f, 0.75f, 1}, {0.55f, 0.85f, 1.0f, 1},
                                      {1.0f, 0.85f, 0.35f, 1}, {0.65f, 1.0f, 0.55f, 1}};
   for (int c = 0; c < CH_COUNT; c++) {
      float lv = g_audio.level[c];
      b_rect(b, x + (float)c * 14.0f, y, 10.0f, 30.0f, C(0, 0, 0, 0.5f));
      b_rect(b, x + (float)c * 14.0f, y + 30.0f * (1.0f - lv), 10.0f, 30.0f * lv, cols[c]);
   }
   b_glow(b, x + 80.0f, y + 15.0f, 14.0f + 16.0f * g_audio.beat, C(1.0f, 0.8f, 0.4f, 0.35f + 0.65f * g_audio.beat));
}

void ui_header(Batch *b, const char *title, const char *sub)
{
   if (!g_hud) return;
   ui_panel(b, 0, 0, VW, 74.0f, 0.55f);
   b_text_shadow(b, 28.0f, 12.0f, 4.0f, C(1.0f, 0.93f, 0.8f, 1), title);
   if (sub) b_text_shadow(b, 30.0f, 49.0f, 2.0f, C(0.85f, 0.8f, 1.0f, 0.9f), sub);
   char fps[24];
   snprintf(fps, sizeof(fps), "%d FPS", (int)(g_fps + 0.5f));
   float w = text_width(fps, 3.0f);
   b_text_shadow(b, VW - 28.0f - w, 14.0f, 3.0f, g_fps > 50.0f ? C(0.6f, 1.0f, 0.6f, 1) : C(1.0f, 0.8f, 0.4f, 1), fps);
   if (g_audio.playing) ui_music_strip(b, VW - 128.0f, 40.0f);
}

void ui_footer(Batch *b, const char *hint)
{
   if (!g_hud) return;
   ui_panel(b, 0, VH - 40.0f, VW, 40.0f, 0.55f);
   b_text_shadow(b, 24.0f, VH - 30.0f, 2.0f, C(1.0f, 1.0f, 1.0f, 0.85f), hint);
}

void ui_sky(Batch *b, Col top, Col mid, Col bottom)
{
   b_rect_grad(b, 0, 0, VW, VH * 0.55f, top, mid);
   b_rect_grad(b, 0, VH * 0.55f, VW, VH * 0.45f, mid, bottom);
}

void ui_button(Batch *b, float x, float y, float w, float h, const char *label, bool active, Col tint)
{
   Col base = active ? tint : CMUL(tint, 0.35f);
   b_rect(b, x - 2.0f, y - 2.0f, w + 4.0f, h + 4.0f, C(0, 0, 0, 0.6f));
   b_rect_grad(b, x, y, w, h, CMUL(base, 1.15f), CMUL(base, 0.75f));
   float s = 2.6f;
   float tw = text_width(label, s);
   b_text_shadow(b, x + (w - tw) * 0.5f, y + (h - 7.0f * s) * 0.5f, s, active ? C(1, 1, 1, 1) : C(1, 1, 1, 0.55f), label);
}
