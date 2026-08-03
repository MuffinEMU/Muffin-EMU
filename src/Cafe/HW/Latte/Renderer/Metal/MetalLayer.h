#pragma once

#include "util/math/vector2.h"

// `sizeInPoints` is the client size of the host view in LOGICAL POINTS (the desktop
// caller passes a wxSize; the iOS caller passes UIScreen/view bounds). Physical pixel
// size is always points * the backing scale returned via scaleX/scaleY, and is
// derived exactly once, by the caller (MetalLayerHandle) - never here.
void* CreateMetalLayer(void* handle, const Vector2i& sizeInPoints, float& scaleX, float& scaleY);
