import SwiftUI
import Combine

/// Per-element placement, on top of the measured defaults.
///
/// The measured layout was taken off a photograph of a real GamePad and it is still wrong
/// on a real device - which says the approach was wrong, not that the measurement needed
/// another pass. Where a control belongs depends on the size of the screen and the size of
/// the hands holding it, and neither of those is knowable from a photo. So the defaults
/// stay as the starting point and every element can be moved and resized from there.
///
/// Stored as one JSON blob rather than a pair of @AppStorage keys per control, because the
/// control set is data - it changes with the skin and the ZL/ZR toggle - and @AppStorage
/// needs a key known at compile time.
struct ControlOverride: Codable, Equatable {
    /// Displacement from the control's default position, in POINTS.
    ///
    /// Points, not layout units, for the same reason the cluster offsets are: a drag is
    /// something a finger did at one particular size, and re-reading it against a
    /// different unit when the size slider moves would make everything wander.
    var dx: Double = 0
    var dy: Double = 0
    /// Multiplier on the control's default size. Clamped on the way in rather than at
    /// draw time, so a stored value can never be one a slider cannot get back to.
    var scale: Double = 1.0

    static let identity = ControlOverride()
    var isIdentity: Bool { self == ControlOverride.identity }
}

final class ControllerCustomLayout: ObservableObject {
    static let shared = ControllerCustomLayout()

    static let storageKey = "muffin.controls.elements"
    static let minScale: Double = 0.5
    static let maxScale: Double = 2.0

    @Published private(set) var overrides: [String: ControlOverride]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: ControlOverride].self, from: data) {
            overrides = decoded
        } else {
            overrides = [:]
        }
    }

    /// Which controls move together.
    ///
    /// L sits directly above ZL on the real GamePad and R above ZR - they are one physical
    /// shoulder each, split into two switches. Letting them be dragged apart would let you
    /// build a pad that no hand matches, so the pair moves as a unit and only their shared
    /// position is stored.
    static func groupID(for controlID: String) -> String {
        switch controlID {
        case "L", "ZL": return "shoulderL"
        case "R", "ZR": return "shoulderR"
        default: return controlID
        }
    }

    func override(for controlID: String) -> ControlOverride {
        overrides[Self.groupID(for: controlID)] ?? .identity
    }

    func move(_ controlID: String, to translation: CGSize, from origin: ControlOverride) {
        var next = origin
        next.dx = origin.dx + Double(translation.width)
        next.dy = origin.dy + Double(translation.height)
        write(next, for: controlID)
    }

    func setScale(_ scale: Double, for controlID: String) {
        var next = override(for: controlID)
        next.scale = min(max(scale, Self.minScale), Self.maxScale)
        write(next, for: controlID)
    }

    /// Clears one element back to its measured default, leaving the rest alone.
    func reset(_ controlID: String) {
        overrides.removeValue(forKey: Self.groupID(for: controlID))
        persist()
    }

    func resetAll() {
        overrides.removeAll()
        persist()
    }

    var hasCustomisations: Bool { !overrides.isEmpty }

    private func write(_ value: ControlOverride, for controlID: String) {
        let key = Self.groupID(for: controlID)
        // An override equal to the default is stored as nothing at all. Otherwise dragging
        // a control away and back would leave a record behind, and "reset everything"
        // would keep claiming there was something to reset.
        if value.isIdentity {
            overrides.removeValue(forKey: key)
        } else {
            overrides[key] = value
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
