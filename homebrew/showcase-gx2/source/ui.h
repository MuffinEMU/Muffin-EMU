// Shared HUD pieces so every scene looks like one program.
#pragma once

#include "gfx.h"

void ui_panel(Batch *b, float x, float y, float w, float h, float alpha);
void ui_header(Batch *b, const char *title, const char *sub);
void ui_footer(Batch *b, const char *hint);
void ui_bar(Batch *b, float x, float y, float w, float h, float frac, Col fill);
void ui_music_strip(Batch *b, float x, float y);
void ui_sky(Batch *b, Col top, Col mid, Col bottom);
void ui_button(Batch *b, float x, float y, float w, float h, const char *label, bool active, Col tint);
bool ui_hit(float tx, float ty, float x, float y, float w, float h);
