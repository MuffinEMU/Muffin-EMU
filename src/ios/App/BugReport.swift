// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import Foundation

/// One text with everything a helper asks for first: the device, the app's main settings, the game
/// that was running, what the engine last said, and the tail of the launch log. Copied in one tap
/// from the boot-failure screen and from Settings > Help and about, so nobody has to find log.txt
/// in Files and describe their setup from memory.
enum BugReport {
    /// The log lines the engine kept for the current run (the live log ring is always collecting, with or
    /// without the on-screen launch log). Newest last.
    static func launchLogTail(_ count: Int) -> [String] {
        var cursor: UInt64 = 0
        var dropped: UInt64 = 0
        var lines: [String] = []
        // The ring is drained in chunks; keep pulling until it hands back nothing.
        for _ in 0..<64 {
            let chunk = withUnsafeMutablePointer(to: &cursor) { cursorPtr in
                withUnsafeMutablePointer(to: &dropped) { droppedPtr in
                    String(cString: ios_live_log_drain(cursorPtr, droppedPtr))
                }
            }
            if chunk.isEmpty { break }
            lines.append(contentsOf: chunk.split(separator: "\n", omittingEmptySubsequences: true).map(String.init))
        }
        return Array(lines.suffix(count))
    }

    /// The log files on the device, for the share sheet: the engine's log.txt and the bridge's crash log.
    static var logFiles: [URL] {
        var urls: [URL] = []
        if let log = WiiUMenu.mlcRootURL?.appendingPathComponent("log.txt") { urls.append(log) }
        let crashPath = String(cString: cemu_bridge_crash_log_path())
        if !crashPath.isEmpty { urls.append(URL(fileURLWithPath: crashPath)) }
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// What the player chose that bears on how a game runs. Read from UserDefaults so it reflects the
    /// stored choice even while no game is up.
    @MainActor
    private static var settingsSummary: String {
        let d = UserDefaults.standard
        let advanced = SettingsMode.isAdvanced
        let renderer = (d.object(forKey: RendererAPI.storageKey) as? Int).flatMap(RendererAPI.init(rawValue:)) ?? RendererAPI.defaultValue
        let accuracy = d.object(forKey: "muffin.cpu.favourAccuracy") as? Bool ?? false
        var lines = [
            "settings mode: \(advanced ? "Advanced" : "Basic")",
            "cpu: \(String(cString: cemu_bridge_cpu_mode_detail()))",
            "jit active now: \(JITStatus.isActive ? "yes" : "no")",
            "cores: \(CoreMode.current.title)",
            "renderer: \(renderer.title)",
            "resolution: \(RenderScale.current.title)",
            "favour accuracy: \(accuracy ? "on" : "off"), favour performance: \(FavourPerformance.isEnabled ? "on" : "off")",
            "steady frame rate: \(FullSpeedRenders.isEnabled ? "on (\(FullSpeedRenders.shaderMode.title))" : "off")",
            "texture filtering: \(TextureFiltering.stored.title)",
        ]
        if OneCoreMode.isEnabled { lines.append("one-core mode: on") }
        if let jitLog = d.stringArray(forKey: JITCoordinator.lastLogKey), !jitLog.isEmpty {
            lines.append("built-in JIT, last run:")
            lines.append(contentsOf: jitLog.map { "  " + $0 })
        }
        return lines.joined(separator: "\n")
    }

    /// The whole report. `game` is the one that was being played or started, if any.
    @MainActor
    static func text(game: GameMetadata?) -> String {
        var sections: [String] = []
        sections.append("MuffinEMU bug report, \(ISO8601DateFormatter().string(from: Date()))")
        sections.append("== Device ==\n" + String(cString: cemu_bridge_device_report())
            + "\n" + PlatformCapabilities.summary
            + "\nthermal: " + ThermalMonitor.shared.description
            + " · heat " + HeatStatus.band.word)
        sections.append("== Settings ==\n" + settingsSummary)
        if let game {
            let format = URL(fileURLWithPath: game.romPath).pathExtension.lowercased()
            sections.append("== Game ==\n"
                + "name: \(game.displayTitle ?? game.title)\n"
                + "title id: \(game.titleId.map { String(format: "%016llx", $0) } ?? "unknown")\n"
                + "format: \(format.isEmpty ? "folder" : format)\(game.isExternal ? ", linked (not copied)" : "")\n"
                + "keys.txt installed: \(WiiUKeys.keysFileExists() ? "yes" : "no")")
        }
        sections.append("== Engine status ==\n" + String(cString: cemu_bridge_status_text()))
        let tail = launchLogTail(60)
        sections.append("== Launch log (last \(tail.count) lines) ==\n" + (tail.isEmpty ? "(nothing logged yet)" : tail.joined(separator: "\n")))
        return sections.joined(separator: "\n\n")
    }
}
