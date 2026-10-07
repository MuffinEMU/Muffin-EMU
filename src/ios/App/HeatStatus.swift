// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

/// How the heat readout is shown.
///
/// Word is the default and the only mode guaranteed to work everywhere - see
/// `HeatStatus.temperatureCelsius` for why the two numeric modes can come back
/// unavailable, and why that is stated rather than papered over.
enum HeatDisplayMode: String, CaseIterable, Identifiable {
    case word
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .word:       return "Word"
        case .celsius:    return "°C"
        case .fahrenheit: return "°F"
        }
    }

    static let storageKey = "muffin.thermal.displayMode"
    static var current: HeatDisplayMode {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let value = HeatDisplayMode(rawValue: raw) else { return .word }
        return value
    }
}

/// The five heat bands, and the colour each one shows as.
///
/// Five words, as asked for. They do NOT come from five iOS states, because iOS only has
/// four (`ProcessInfo.ThermalState`): nominal, fair, serious, critical. Where the fifth
/// comes from depends on what the device will tell us:
///
/// - With a real temperature reading, the bands are real temperature ranges and all five
///   are distinct.
/// - Without one - the normal case on a sideloaded install - `.fair` covers what would
///   otherwise be two bands, so "Fair" and "Warm" collapse into one and four are shown.
///   That is a real limit of the signal, not a shortcut: inventing a fifth band from a
///   four-state input would be making up precision that does not exist.
enum HeatBand: Int, Comparable {
    case cool = 0
    case fair
    case warm
    case hot
    case extremelyHot

    static func < (lhs: HeatBand, rhs: HeatBand) -> Bool { lhs.rawValue < rhs.rawValue }

    var word: String {
        switch self {
        case .cool:         return "Cool"
        case .fair:         return "Fair"
        case .warm:         return "Warm"
        case .hot:          return "Hot"
        case .extremelyHot: return "Extremely Hot"
        }
    }

    /// Green through red, but routed through the theme where the theme has a colour that
    /// means the right thing, so this does not become the one control in the app that
    /// ignores the palette. Hot and Extremely Hot are deliberately NOT theme colours -
    /// a warning that changes hue with the theme stops being a warning.
    var color: Color {
        switch self {
        case .cool:         return MuffinTheme.pixelBlue
        case .fair:         return Color(red: 0.16, green: 0.62, blue: 0.35)
        case .warm:         return MuffinTheme.muffinTopDark
        case .hot:          return Color(red: 0.90, green: 0.45, blue: 0.10)
        case .extremelyHot: return Color(red: 0.85, green: 0.18, blue: 0.18)
        }
    }

    /// From iOS's four-level signal. `.fair` maps to `.warm` rather than `.fair` on
    /// purpose: on-device reports described the device as "warm, but a little bit hot"
    /// in exactly the conditions iOS reports `.fair`, so
    /// "Warm" is the word that matches what a person actually sees there.
    static func from(thermalState: ProcessInfo.ThermalState) -> HeatBand {
        switch thermalState {
        case .nominal:  return .cool
        case .fair:     return .warm
        case .serious:  return .hot
        case .critical: return .extremelyHot
        @unknown default: return .warm
        }
    }

    /// From a real reading. Battery temperature, so the thresholds are battery
    /// thresholds - an iPad battery idles near 30 C and a sustained emulator load pushes
    /// it well past 40 C long before the SoC would read anything like that.
    static func from(celsius: Double) -> HeatBand {
        switch celsius {
        case ..<30:  return .cool
        case ..<35:  return .fair
        case ..<40:  return .warm
        case ..<45:  return .hot
        default:     return .extremelyHot
        }
    }
}

/// The reading itself, and the honest answer about what is available.
///
/// @MainActor because `band` reads `ThermalMonitor.shared.state`, and ThermalMonitor is
/// main-actor isolated - it owns @Published state that drives views and mutates the
/// governor. Isolating this type is the honest fix rather than making ThermalMonitor
/// nonisolated or reaching for `assumeIsolated`: every caller here is already a SwiftUI
/// view (the badge, the CPU section, the device report), so there is nothing to force.
@MainActor
enum HeatStatus {
    /// A real temperature, or nil. Never estimated - see
    /// `cemu_bridge_device_temperature_celsius()` for why this is usually nil on a
    /// sideloaded install and why returning nil is the correct outcome rather than a
    /// fallback worth filling in.
    static var temperatureCelsius: Double? {
        let value = cemu_bridge_device_temperature_celsius()
        return value.isNaN ? nil : value
    }

    static var band: HeatBand {
        if let celsius = temperatureCelsius {
            return .from(celsius: celsius)
        }
        return .from(thermalState: ThermalMonitor.shared.state)
    }

    /// What the chosen mode actually shows. A numeric mode with no reading available
    /// falls back to the word rather than showing a dash: the band is genuinely known
    /// either way, and hiding it to honour a display preference would trade real
    /// information for a formatting choice.
    static func text(for mode: HeatDisplayMode) -> String {
        let band = band
        guard mode != .word else { return band.word }
        guard let celsius = temperatureCelsius else { return band.word }
        switch mode {
        case .celsius:    return String(format: "%.0f°C", celsius)
        case .fahrenheit: return String(format: "%.0f°F", celsius * 9.0 / 5.0 + 32.0)
        case .word:       return band.word
        }
    }

    /// Whether the numeric modes can do anything on this build. Drives the one line of
    /// explanation under the picker, so someone who picks °C and keeps seeing a word
    /// learns why instead of assuming it is broken.
    static var hasRealTemperature: Bool { temperatureCelsius != nil }
}

/// A small coloured heat pill. Reads live, because it observes the same ThermalMonitor
/// that drives the automatic cool-down.
struct HeatStatusBadge: View {
    @ObservedObject private var thermal = ThermalMonitor.shared
    @AppStorage(HeatDisplayMode.storageKey) private var mode = HeatDisplayMode.word.rawValue

    private var displayMode: HeatDisplayMode { HeatDisplayMode(rawValue: mode) ?? .word }

    var body: some View {
        let band = HeatStatus.band
        return HStack(spacing: 6) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 12, weight: .bold))
            Text(HeatStatus.text(for: displayMode))
                .font(.system(size: 13, weight: .bold, design: .rounded))
        }
        // The pill's text is picked against the band colour, and Classic's coloured text
        // against the settings row it sits in: Fair's green, Hot's orange and some themes'
        // pale accent left cream-on-colour or colour-on-white text unreadable.
        .foregroundColor(UIStyle.isClassic
                         ? LegibleInk.ensure(band.color, on: Color(.secondarySystemGroupedBackground))
                         : LegibleInk.on(band.color, light: MuffinTheme.sparkleCream))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            // Classic UI never had coloured pills, so there the colour goes on the text
            // and the pill disappears - the information survives the styling switch even
            // though the shape does not.
            Group {
                if UIStyle.isClassic {
                    Color.clear
                } else {
                    Capsule().fill(band.color)
                }
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Device heat: \(band.word)")
    }
}
