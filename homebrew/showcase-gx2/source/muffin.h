// The showcase mascot: a blueberry muffin built from a lathe profile at startup.
#pragma once

#include "gfx.h"

void muffin_build(void);   // safe to call repeatedly
void muffin_draw(const float model[16], const float viewproj[16], const Fog *fog);
