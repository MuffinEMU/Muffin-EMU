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
