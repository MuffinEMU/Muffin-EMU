import SwiftUI
import Combine

/// Per-element placement, on top of the measured defaults.
///
/// Stored as one JSON blob rather than @AppStorage keys per control, because the control
/// set changes with the skin and the ZL/ZR toggle.
struct ControlOverride: Codable, Equatable {
    /// Displacement from the default position, in points (not layout units, so it doesn't
    /// wander when the size slider moves).
    var dx: Double = 0
    var dy: Double = 0
    /// Multiplier on the default size, clamped on the way in.
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

    /// Re-reads the stored layout, for a settings import that rewrote it.
    func reloadFromDefaults() {
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: ControlOverride].self, from: data) {
            overrides = decoded
        } else {
            overrides = [:]
        }
    }

    var hasCustomisations: Bool { !overrides.isEmpty }

    /// Call when a drag or pinch ends, to write to disk what `write(_:for:)` only kept in
    /// `overrides` while the gesture was live.
    /// Writes a change still waiting on the short coalescing delay; no-op when nothing is pending.
    func flushPending() {
        guard pendingPersist != nil else { return }
        pendingPersist?.cancel()
        pendingPersist = nil
        persist()
    }

    func commit() {
        pendingPersist?.cancel()
        persist()
    }

    private func write(_ value: ControlOverride, for controlID: String) {
        let key = Self.groupID(for: controlID)
        // An override equal to the default is stored as nothing.
        if value.isIdentity {
            overrides.removeValue(forKey: key)
        } else {
            overrides[key] = value
        }
        // Not written per tick: coalesced to one write shortly after the last change, so a force-quit
        // mid-drag keeps the layout. `commit()` writes at once when the gesture ends.
        schedulePersist()
    }

    private var pendingPersist: DispatchWorkItem?

    private func schedulePersist() {
        pendingPersist?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persist() }
        pendingPersist = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
