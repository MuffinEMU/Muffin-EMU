#pragma once

#include "util/math/vector2.h"

// `sizeInPoints` is the client size of the host view in LOGICAL POINTS (the desktop
// caller passes a wxSize; the iOS caller passes UIScreen/view bounds). Physical pixel
// size is always points * the backing scale returned via scaleX/scaleY, and is
// derived exactly once, by the caller (MetalLayerHandle) - never here.
void* CreateMetalLayer(void* handle, const Vector2i& sizeInPoints, float& scaleX, float& scaleY);

// Move an existing layer to a new size and backing scale, updating the CALayer's own
// geometry as well as its contentsScale. CreateMetalLayer() sets a frame once and
// nothing re-syncs it afterwards - a manually added sublayer does not resize with its
// superlayer - so this is the callback that comment always said a dynamic-resize path
// would need. Used when the render surface moves between the device's screen and an
// external display, which changes both the size and the scale.
//
// Must be called on the main thread: it touches Core Animation geometry.
//
// Defined in BOTH platform branches of MetalLayer.mm for the same reason
// CreateMetalLayer() is - MetalLayerHandle.cpp compiles for macOS too whenever
// ENABLE_METAL is on, so a declaration with only one definition is a link error that
// no single-file compile would catch.
void ResizeMetalLayer(void* layer, const Vector2i& sizeInPoints, float scale);
