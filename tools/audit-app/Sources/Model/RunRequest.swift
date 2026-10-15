// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

//
//  RunRequest.swift
//  What a run is asked to do.
//
import Foundation

struct RunRequest {
    /// "quick" (the catalogue's quick tests, attended), "standard" (every selected test once) or "soak" (selected unattended tests, repeatedly, for `soakMinutes`).
    var mode: String = "standard"
    var suiteIds: [String] = []
    /// Empty means every test of the selected suites.
    var testIds: [String] = []
    /// "metal" or "vulkan".
    var renderer: String = "metal"
    /// "auto", "interpreter" or "recompiler".
    var cpu: String = "auto"
    var padSurface: Bool = false
    var attended: Bool = true
    var soakMinutes: Int = 0
    var repeatCount: Int = 1
    var seed: UInt32 = 1
    /// 0 guest lines only, 1 audit set (default), 2 verbose.
    var logProfile: Int = 1
}
