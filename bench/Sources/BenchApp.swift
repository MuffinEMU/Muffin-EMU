// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

//
//  BenchApp.swift
//  Entry point. Everything the app does lives in BenchView/BenchRunner; this file's
//  only job is to exist.
//
import SwiftUI

@main
struct MuffinBenchApp: App {
    var body: some Scene {
        WindowGroup {
            BenchView()
        }
    }
}
