// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import Foundation

/// Export and import of every setting as one JSON file: the settings keys (SettingsDefaults.isPortableSetting)
/// and each game's own options. Nothing private goes in: no premium unlock, accounts, Wii U keys or library
/// records. An import is checked before anything is touched, and the person confirms before it replaces
/// what they have.
///
/// File shape:
///
///     { "format": "MuffinEMU settings", "version": 1, "app": "7.3 (5)", "exported": "2026-10-06T10:00:00Z",
///       "settings": { "muffin.audio.tvVolume": 50, "renderScale": "balanced", ... },
///       "perGame":  { "<title ID>": { "renderScale": "high", ... } } }
///
/// Numbers, strings and booleans are written as themselves; raw bytes (a saved pad layout) as
/// `{"$data": "<base64>"}`.
enum SettingsBackup {
    static let formatName = "MuffinEMU settings"
    static let currentVersion = 1
    /// A settings file is a few kilobytes; anything far bigger is not one.
    private static let maxFileBytes = 2_000_000

    enum BackupError: LocalizedError {
        case unreadable
        case notASettingsFile
        case newerVersion(Int)
        case nothingToImport

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "That file couldn't be read."
            case .notASettingsFile:
                return "That isn't a MuffinEMU settings file."
            case .newerVersion(let version):
                return "That file is from a newer MuffinEMU (settings file version \(version)). Update the app, then try again."
            case .nothingToImport:
                return "That file has no settings MuffinEMU can use."
            }
        }
    }

    /// What a file holds, checked and ready to apply.
    struct Preview {
        let settings: [String: Any]
        let perGame: [String: GameOverrides]
        /// Entries that were left out: unknown keys, wrong types, values out of range.
        let skippedCount: Int

        var settingCount: Int { settings.count }
        var gameCount: Int { perGame.count }
    }

    // MARK: - Export

    /// The file's bytes, from what is stored right now.
    static func exportData() throws -> Data {
        let defaults = UserDefaults.standard
        var settings: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where SettingsDefaults.isPortableSetting(key) {
            if let converted = jsonValue(value) { settings[key] = converted }
        }
        // While the cool-down holds Resolution at battery saver, the stored value is the cool-down's, not theirs.
        if ThermalSettings.isHoldingScale,
           let chosen = defaults.string(forKey: ThermalSettings.scaleKey) {
            settings[RenderScale.storageKey] = chosen
        }

        var perGame: [String: Any] = [:]
        if let data = defaults.data(forKey: PerGameSettingsStore.storageKey),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            perGame = object
        }

        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String ?? "0") + " (" + (info?["CFBundleVersion"] as? String ?? "0") + ")"
        let document: [String: Any] = [
            "format": formatName,
            "version": currentVersion,
            "app": version,
            "exported": ISO8601DateFormatter().string(from: Date()),
            "settings": settings,
            "perGame": perGame,
        ]
        return try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
    }

    /// Writes the export to a temporary file named for the day, ready for the Files picker.
    static func exportFile() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("MuffinEMU settings \(formatter.string(from: Date())).json")
        try exportData().write(to: url, options: .atomic)
        return url
    }

    // MARK: - Import

    /// Reads and checks a file without changing anything.
    static func preview(of url: URL) throws -> Preview {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count <= maxFileBytes else { throw BackupError.unreadable }
        return try preview(of: data)
    }

    static func preview(of data: Data) throws -> Preview {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["format"] as? String == formatName else { throw BackupError.notASettingsFile }
        guard let version = (root["version"] as? NSNumber)?.intValue else { throw BackupError.notASettingsFile }
        guard version <= currentVersion else { throw BackupError.newerVersion(version) }

        var skipped = 0
        var settings: [String: Any] = [:]
        for (key, raw) in (root["settings"] as? [String: Any]) ?? [:] {
            guard SettingsDefaults.isPortableSetting(key),
                  let value = plistValue(raw),
                  isAcceptable(value, for: key) else {
                skipped += 1
                continue
            }
            settings[key] = value
        }

        var perGame: [String: GameOverrides] = [:]
        if let games = root["perGame"] as? [String: Any], !games.isEmpty {
            guard JSONSerialization.isValidJSONObject(games),
                  let bytes = try? JSONSerialization.data(withJSONObject: games),
                  let decoded = try? JSONDecoder().decode([String: GameOverrides].self, from: bytes) else {
                throw BackupError.notASettingsFile
            }
            perGame = decoded.filter { !$0.value.isIdentity }
        }

        guard !settings.isEmpty || !perGame.isEmpty else { throw BackupError.nothingToImport }
        return Preview(settings: settings, perGame: perGame, skippedCount: skipped)
    }

    /// Replaces the settings and every game's own options with what the file holds. Settings the file
    /// doesn't mention go back to their defaults, since the file was written with them at their defaults.
    @MainActor
    static func apply(_ preview: Preview) {
        let defaults = UserDefaults.standard
        // Unwind an active cool-down first: it restores Resolution from a key removed below.
        ThermalMonitor.shared.titleStopped()
        for key in defaults.dictionaryRepresentation().keys where SettingsDefaults.isPortableSetting(key) {
            defaults.removeObject(forKey: key)
        }
        for (key, value) in preview.settings { defaults.set(value, forKey: key) }
        PerGameSettingsStore.shared.replaceOverrides(preview.perGame)
        // Whatever Basic had saved belongs to the old settings.
        AdvancedSettings.discardSnapshot()
        // A file written in Basic mode never carries advanced values, but an edited one could; Basic means defaults.
        if !SettingsMode.isAdvanced { AdvancedSettings.clearAdvanced() }

        // The stores that keep their own copy, as after a reset.
        UIStyleStore.shared.reloadFromDefaults()
        ControllerCustomLayout.shared.reloadFromDefaults()
        PreviewPadStore.shared.reloadFromDefaults()
        DisplayRouter.shared.reapplyRenderScale(reason: "settings import")
        // The values the engine holds a copy of that Settings pushes as they change. The rest reach it at the next game start.
        AdvancedSettings.applyToBridge()
        MotionSettings.applyToBridge()
        NotificationCenter.default.post(name: .muffinSettingsWereReset, object: nil)
    }

    // MARK: - Value conversion

    /// A UserDefaults value as something JSONSerialization writes, or nil for a value that has no JSON form.
    private static func jsonValue(_ value: Any) -> Any? {
        switch value {
        case let number as NSNumber:
            if !isBoolean(number), !number.doubleValue.isFinite { return nil }
            return number
        case let text as String:
            return text
        case let data as Data:
            return ["$data": data.base64EncodedString()]
        case let list as [Any]:
            let converted = list.compactMap(jsonValue)
            return converted.count == list.count ? converted : nil
        case let dictionary as [String: Any]:
            let converted = dictionary.compactMapValues(jsonValue)
            return converted.count == dictionary.count ? converted : nil
        default:
            return nil
        }
    }

    /// The reverse: a value read from the file as something UserDefaults can store.
    private static func plistValue(_ value: Any) -> Any? {
        switch value {
        case let number as NSNumber:
            if !isBoolean(number), !number.doubleValue.isFinite { return nil }
            return number
        case let text as String:
            return text
        case let list as [Any]:
            let converted = list.compactMap(plistValue)
            return converted.count == list.count ? converted : nil
        case let dictionary as [String: Any]:
            if dictionary.count == 1, let encoded = dictionary["$data"] as? String {
                return Data(base64Encoded: encoded)
            }
            let converted = dictionary.compactMapValues(plistValue)
            return converted.count == dictionary.count ? converted : nil
        default:
            return nil
        }
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    // MARK: - Checks

    /// Settings with a fixed set of choices. A value outside it would fall back to the default when read, but
    /// it is better refused here than stored.
    private static let allowedStrings: [String: Set<String>] = [
        RenderScale.storageKey: Set(RenderScale.allCases.map(\.rawValue)),
        MoltenVKBuild.storageKey: Set(MoltenVKBuild.allCases.map(\.rawValue)),
        CoreMode.storageKey: Set(CoreMode.allCases.map(\.rawValue)),
        SettingsMode.storageKey: Set(SettingsMode.allCases.map(\.rawValue)),
        TopBarAutoHide.handleSizeKey: Set(TopBarAutoHide.HandleSize.allCases.map(\.rawValue)),
        ThermalSettings.thresholdKey: Set(ThermalSettings.Threshold.allCases.map(\.rawValue)),
        LocalScreenLayoutSettings.layoutKey: Set(ScreenLayout.allCases.map(\.rawValue)),
    ]

    private static let allowedInts: [String: ClosedRange<Int>] = [
        RendererAPI.storageKey: 1...2,
        UpscaleFilterSetting.storageKey: 0...3,
        DownscaleFilterSetting.storageKey: 0...3,
        FullSpeedRenders.shaderModeKey: 0...1,
        TopBarAutoHide.hideDelayKey: 2...8,
        TopBarAutoHide.overrideKey: 0...2,
    ]

    private static let allowedDoubles: [String: ClosedRange<Double>] = [
        DisplayGammaSetting.storageKey: DisplayGammaSetting.minValue...DisplayGammaSetting.maxValue,
        OverrideGammaSetting.storageKey: OverrideGammaSetting.minValue...OverrideGammaSetting.maxValue,
        MotionSettings.sensitivityKey: MotionSettings.minSensitivity...MotionSettings.maxSensitivity,
        ControllerLayoutSettings.deadzoneKey: ControllerLayoutSettings.minDeadzone...ControllerLayoutSettings.maxDeadzone,
        ControllerLayoutSettings.stickCurveKey: ControllerLayoutSettings.minStickCurve...ControllerLayoutSettings.maxStickCurve,
        ControllerLayoutSettings.scaleKey: ControllerLayoutSettings.minScale...ControllerLayoutSettings.maxScale,
        ControllerLayoutSettings.opacityKey: 0.2...1.0,
    ]

    /// The value has the type the setting is stored as, and is one it can take.
    private static func isAcceptable(_ value: Any, for key: String) -> Bool {
        if let allowed = allowedStrings[key] {
            guard let text = value as? String else { return false }
            return allowed.contains(text)
        }
        if let range = allowedInts[key] {
            guard let number = value as? NSNumber, !isBoolean(number),
                  number.doubleValue == number.doubleValue.rounded() else { return false }
            return range.contains(number.intValue)
        }
        if let range = allowedDoubles[key] {
            guard let number = value as? NSNumber, !isBoolean(number) else { return false }
            return range.contains(number.doubleValue)
        }
        // Everything else the registry knows: the type of its default.
        if let setting = AdvancedSettings.allSettings.first(where: { $0.key == key }), let fallback = setting.defaultValue {
            guard let number = fallback as? NSNumber else { return value is String }
            guard let given = value as? NSNumber else { return false }
            return isBoolean(number) == isBoolean(given)
        }
        return true
    }
}
