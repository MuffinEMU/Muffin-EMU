// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// Where an on-screen overlay is drawn, mirroring CemuConfig.h's own ScreenPosition enum
/// value-for-value (kDisabled = 0 through kBottomRight = 6) so the raw int a picker stores
/// can be pushed straight into the matching cemu_bridge_set_*_position() bridge call with
/// no remapping step to get wrong. Declared disabled-first, matching the core's own default
/// and putting "off" at the top of the picker rather than buried among six placements.
///
/// Shared between the Performance Overlay and Notifications settings sections: the engine
/// draws them as two independent ImGui windows (LatteOverlay_renderOverlay() and
/// LatteOverlay_RenderNotifications()), each with its own ScreenPosition field on
/// CemuConfig, but the placement semantics - and this app's UI for choosing one - are
/// identical, so one enum backs both pickers instead of two copies drifting apart.
///
/// Not to be confused with `ScreenLayout` (DisplayRouter.swift): that decides which
/// physical device (TV/GamePad) shows on which display, an on-device arrangement concept.
/// This decides where a corner-anchored readout sits within whichever screen it draws on.
enum ScreenPosition: Int, CaseIterable, Identifiable {
    case disabled = 0
    case topLeft = 1
    case topCenter = 2
    case topRight = 3
    case bottomLeft = 4
    case bottomCenter = 5
    case bottomRight = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .disabled:     return "Off"
        case .topLeft:      return "Top left"
        case .topCenter:    return "Top centre"
        case .topRight:     return "Top right"
        case .bottomLeft:   return "Bottom left"
        case .bottomCenter: return "Bottom centre"
        case .bottomRight:  return "Bottom right"
        }
    }
}
