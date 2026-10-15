// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

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
