// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

//
//  IOSGraphicPackBridge.h
//  Plain-C surface for the graphic pack screens (implemented in Core/IOSGraphicPacks.cpp).
//
//  Packs are addressed by their normalized path - the first field of a muffin_gp_list() record,
//  e.g. "graphicPacks/downloadedGraphicPacks/src/SomeGame/Graphics/rules.txt". It is stable
//  across rescans and is the same key the core stores its settings under.
//
//  Separators in every returned string: 0x1E between records, 0x1F between fields, 0x1D between
//  the two halves of muffin_gp_details(). None can occur inside a pack's own text.
//
#ifndef IOSGraphicPackBridge_h
#define IOSGraphicPackBridge_h

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// True while a game is running. Packs can be browsed then but not changed or rescanned.
bool muffin_gp_title_running(void);

/// Rescans Documents/mlc/graphicPacks (mlcPath is Documents/mlc). Works before the engine has
/// ever started. Returns false, leaving the list as it was, while a game is running.
bool muffin_gp_reload(const char* mlcPath);

/// One record per pack: normalized path, name, virtual path ("Game/Category/Pack"), enabled,
/// default-enabled, universal, pack format version, comma-joined title IDs (16 hex digits),
/// rendererFilter ("" or vulkan/opengl/metal), vendorFilter ("" or apple/amd/...), has GLSL
/// shader replacements, has Metal (MSL) shader replacements, has GLSL output/upscale/downscale
/// shaders, preset count, short description.
const char* muffin_gp_list(void);

/// Full description, 0x1D, then one record per preset: category, name, active, visible, default.
const char* muffin_gp_details(const char* packPath);

/// Turn a pack on or off for its games. Persisted immediately; applies when a game next
/// launches. False (nothing changed) while a game is running or for an unknown pack.
bool muffin_gp_set_enabled(const char* packPath, bool enabled);

/// Choose the active preset in one category. Other categories can change as a result
/// (hidden options), so re-read muffin_gp_details() afterwards.
bool muffin_gp_set_preset(const char* packPath, const char* category, const char* preset);

/// Back to the pack's own default on/off state and default presets.
bool muffin_gp_reset_pack(const char* packPath);

#ifdef __cplusplus
}
#endif

#endif /* IOSGraphicPackBridge_h */
