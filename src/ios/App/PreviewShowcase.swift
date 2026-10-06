import SwiftUI
import UniformTypeIdentifiers

//  Preview showcase: the experimental new pad (geometry, colour and movable groups).
//  Off by default (PreviewSettings.enabledKey); the standard pad is unaffected until it
//  is turned on in Settings.

// MARK: - The three layout presets

/// The three layout presets. Each is a real .muffinlyt captured from PadLayout.resolve()
/// on a device profile, and PadPresetFitter places every preset on every device.
enum PreviewLayoutPreset: String, CaseIterable, Identifiable {
    case native, iPadPro2020, compact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .native:      return "Native (this device)"
        case .iPadPro2020: return "iPad Pro 12.9\" (2020)"
        case .compact:     return "Compact"
        }
    }

    var summary: String {
        switch self {
        case .native:
            return "This device's own layout."
        case .iPadPro2020:
            return "The layout from a 12.9-inch iPad Pro, fitted to your screen."
        case .compact:
            return "70% of life-size: smaller buttons, more of the picture."
        }
    }

    /// The reference device each non-native preset was captured on. `.native` has none -
    /// it is resolved fresh for the running device every time, never transplanted.
    private var reference: (container: CGSize, safeArea: CGRect, pointsPerInch: CGFloat, userScale: CGFloat)? {
        switch self {
        case .native:
            return nil
        case .iPadPro2020:
            // iPad Pro 12.9" (2020, A12Z): 1366x1024 pt container, 132 ppi, no notch.
            return (CGSize(width: 1366, height: 1024), CGRect(x: 0, y: 0, width: 1366, height: 1004), 132, 1.0)
        case .compact:
            // Captured on the same reference device at 70% scale, so "Compact" means
            // smaller buttons everywhere it lands, not just on the device it was made on.
            return (CGSize(width: 1366, height: 1024), CGRect(x: 0, y: 0, width: 1366, height: 1004), 132, 0.7)
        }
    }

    /// The captured file, or nil for `.native` (meaning: resolve fresh, no transplant).
    func layoutFile(displayMode: PadLayout.DisplayMode) -> MuffinLayoutFile? {
        guard let ref = reference else { return nil }
        let layout = PadLayout.resolve(container: ref.container, safeArea: ref.safeArea,
                                       pointsPerInch: ref.pointsPerInch, userScale: ref.userScale,
                                       displayMode: displayMode)
        return MuffinLayoutFile.capture(name: title, from: layout, safeArea: ref.safeArea,
                                        pointsPerInch: ref.pointsPerInch)
    }
}

// MARK: - The three colour presets

/// Exactly three: the measured white, the derived black, and one coloured option
/// (Super Famicom) - not all ten
/// MuffinColourPresets ships, because this preview is meant to show the idea working,
/// not stand in for the full picker.
enum PreviewColourPreset: String, CaseIterable, Identifiable {
    case wiiUWhite, wiiUBlack, superFamicom

    var id: String { rawValue }

    var file: MuffinColourFile {
        switch self {
        case .wiiUWhite:    return MuffinColourPresets.wiiUWhite
        case .wiiUBlack:    return MuffinColourPresets.wiiUBlack
        case .superFamicom: return MuffinColourPresets.superFamicom
        }
    }
}

// MARK: - Live state

/// Everything the preview pad needs, persisted the same way ControllerCustomLayout
/// persists per-element overrides: one JSON blob per kind of state, because the group set
/// is fixed here (nine, always) but the VALUES are user data that has to survive a
/// relaunch.
final class PreviewPadStore: ObservableObject {
    static let shared = PreviewPadStore()

    static let enabledKey = "muffin.preview.enabled"

    /// The single default for enabledKey, shared by every @AppStorage that reads it.
    /// Off: the experimental pad is opt-in.
    static let defaultEnabled = false
    static let layoutPresetKey = "muffin.preview.layoutPreset"
    static let colourPresetKey = "muffin.preview.colourPreset"
    static let customColoursKey = "muffin.preview.customColours"
    static let displayModeKey = "muffin.preview.displayMode"
    static let adjustmentsKey = "muffin.preview.groupAdjustments"

    @Published var layoutPreset: PreviewLayoutPreset {
        didSet { defaults.set(layoutPreset.rawValue, forKey: Self.layoutPresetKey) }
    }
    @Published var colourPreset: PreviewColourPreset {
        // Picking a preset, even the one already picked, drops an imported colour file.
        didSet {
            defaults.set(colourPreset.rawValue, forKey: Self.colourPresetKey)
            customColours = nil
        }
    }
    /// A .muffinclr the person imported. Wins over `colourPreset` until they pick a preset again.
    @Published private(set) var customColours: MuffinColourFile? {
        didSet { persistCustomColours() }
    }
    /// The colours actually in effect: the imported file if there is one, else the picked preset.
    var colourFile: MuffinColourFile { customColours ?? colourPreset.file }
    @Published var displayMode: PadLayout.DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Self.displayModeKey) }
    }
    /// Live drag/resize nudges on top of whichever preset is active - the "movable and
    /// resizable" part. Keyed by group, in the SAME units (D-relative dx/dy/scale) a
    /// .muffinlyt itself uses, which is what makes "export what I dragged into place" a
    /// real, meaningful file rather than a screen-specific dump of points.
    @Published var adjustments: [String: GroupPlacement] {
        didSet { persistAdjustments() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        layoutPreset = PreviewLayoutPreset(rawValue: defaults.string(forKey: Self.layoutPresetKey) ?? "") ?? .iPadPro2020
        colourPreset = PreviewColourPreset(rawValue: defaults.string(forKey: Self.colourPresetKey) ?? "") ?? .wiiUWhite
        displayMode = PadLayout.DisplayMode(rawValue: defaults.string(forKey: Self.displayModeKey) ?? "") ?? .fit
        customColours = Self.loadCustomColours(defaults)
        if let data = defaults.data(forKey: Self.adjustmentsKey),
           let decoded = try? JSONDecoder().decode([String: GroupPlacement].self, from: data) {
            adjustments = decoded
        } else {
            adjustments = [:]
        }
    }

    /// Re-reads everything from UserDefaults, for after the keys were removed behind this
    /// store's back (Settings > Reset settings to defaults).
    func reloadFromDefaults() {
        // Read first: setting colourPreset below clears the imported colours.
        let custom = Self.loadCustomColours(defaults)
        layoutPreset = PreviewLayoutPreset(rawValue: defaults.string(forKey: Self.layoutPresetKey) ?? "") ?? .iPadPro2020
        colourPreset = PreviewColourPreset(rawValue: defaults.string(forKey: Self.colourPresetKey) ?? "") ?? .wiiUWhite
        displayMode = PadLayout.DisplayMode(rawValue: defaults.string(forKey: Self.displayModeKey) ?? "") ?? .fit
        customColours = custom
        if let data = defaults.data(forKey: Self.adjustmentsKey),
           let decoded = try? JSONDecoder().decode([String: GroupPlacement].self, from: data) {
            adjustments = decoded
        } else {
            adjustments = [:]
        }
    }

    func adjustment(for group: PadGroup) -> GroupPlacement {
        adjustments[group.rawValue] ?? GroupPlacement(dx: 0, dy: 0, scale: 1)
    }

    func setAdjustment(_ placement: GroupPlacement, for group: PadGroup) {
        adjustments[group.rawValue] = placement.clamped
    }

    func resetAdjustments() {
        adjustments = [:]
    }

    /// Importing a .muffinlyt means "use exactly this arrangement" - switching to
    /// `.native` as the base (so nothing but the import itself shapes it) and replacing
    /// every adjustment wholesale, not layering the import on top of whatever was there.
    func applyImportedLayout(_ file: MuffinLayoutFile) {
        layoutPreset = .native
        adjustments = file.groups
    }

    /// Importing a .muffinclr means "use exactly these colours" - the file is kept whole, so
    /// exporting it again gives back the same file.
    func applyImportedColours(_ file: MuffinColourFile) {
        customColours = file
    }

    /// The arrangement actually in effect right now - the active preset's own groups
    /// with the live drag/resize adjustments already folded in - so exporting captures
    /// what is genuinely on screen, not just the preset or just the deltas.
    func effectiveLayoutFile(container: CGSize, safeArea: CGRect, pointsPerInch: CGFloat) -> MuffinLayoutFile {
        let base = layoutPreset.layoutFile(displayMode: displayMode)
            ?? {
                let native = PadLayout.resolve(container: container, safeArea: safeArea,
                                               pointsPerInch: pointsPerInch, displayMode: displayMode)
                return MuffinLayoutFile.capture(name: "native", from: native, safeArea: safeArea,
                                                pointsPerInch: pointsPerInch)
            }()
        var merged = base
        merged.name = "\(layoutPreset.title) (edited)"
        for g in PadGroup.allCases {
            let a = adjustment(for: g)
            guard !a.dx.isZero || !a.dy.isZero || a.scale != 1 else { continue }
            var v = merged.groups[g.rawValue] ?? GroupPlacement(dx: 0, dy: 0, scale: 1)
            v.dx += a.dx; v.dy += a.dy; v.scale *= a.scale
            merged.groups[g.rawValue] = v.clamped
        }
        return merged
    }

    private static func loadCustomColours(_ defaults: UserDefaults) -> MuffinColourFile? {
        guard let data = defaults.data(forKey: customColoursKey) else { return nil }
        return try? MuffinColourFile.decode(data)
    }

    private func persistCustomColours() {
        if let customColours, let data = try? customColours.encoded() {
            defaults.set(data, forKey: Self.customColoursKey)
        } else {
            defaults.removeObject(forKey: Self.customColoursKey)
        }
    }

    private func persistAdjustments() {
        guard let data = try? JSONEncoder().encode(adjustments) else { return }
        defaults.set(data, forKey: Self.adjustmentsKey)
    }

    // MARK: Resolving the actual layout for a container

    /// The display mode in force for a container. An iPhone held upright is always Native: Fit
    /// would leave the picture mid-screen with the controls floating over it, and upright the
    /// picture belongs along the top with the controls below (Native's portrait layout).
    func effectiveDisplayMode(container: CGSize) -> PadLayout.DisplayMode {
        if UIDevice.current.userInterfaceIdiom == .phone, container.height > container.width { return .native }
        return displayMode
    }

    /// The current preset, fitted (or resolved fresh, for `.native`) onto this container,
    /// with the live per-group drag/resize adjustments layered on top. This is the one
    /// call site EmulatorViewOptimized and PreviewControllerPad both need.
    func resolve(container: CGSize, safeArea: CGRect, pointsPerInch: CGFloat) -> PreviewResolved {
        let displayMode = effectiveDisplayMode(container: container)
        if let file = layoutPreset.layoutFile(displayMode: displayMode) {
            var adjustedFile = file
            for g in PadGroup.allCases {
                let a = adjustment(for: g)
                guard !a.dx.isZero || !a.dy.isZero || a.scale != 1 else { continue }
                var base = adjustedFile.groups[g.rawValue] ?? GroupPlacement(dx: 0, dy: 0, scale: 1)
                base.dx += a.dx; base.dy += a.dy; base.scale *= a.scale
                adjustedFile.groups[g.rawValue] = base.clamped
            }
            let fitted = PadPresetFitter.fit(adjustedFile, container: container, safeArea: safeArea,
                                             pointsPerInch: pointsPerInch)
            // The picture is not part of a .muffinlyt - only button placement transplants.
            // What the video should look like on THIS device follows the four laws fresh,
            // exactly as if no preset were loaded at all, which is why this is a second,
            // independent resolve rather than something PadPresetFitter hands back.
            let nativeForVideo = PadLayout.resolve(container: container, safeArea: safeArea,
                                                   pointsPerInch: pointsPerInch, displayMode: displayMode)
            return PreviewResolved(video: nativeForVideo.video, controls: fitted.controls, unit: fitted.unit,
                                   notes: fitted.interventions.map(\.detail))
        }

        // .native: resolve fresh for this device, then apply adjustments the same way
        // PadPresetFitter would - capture the native layout as a one-shot "file" with
        // identity placements, layer the live nudges on, and fit it right back onto the
        // same container. Fitting a layout onto the exact device it was captured from is
        // a verified no-op when nothing has been dragged (see the round-trip fix), so
        // this reduces to "just the adjustments" whenever nothing has been moved.
        let base = PadLayout.resolve(container: container, safeArea: safeArea,
                                     pointsPerInch: pointsPerInch, displayMode: displayMode)
        guard !adjustments.isEmpty else {
            return PreviewResolved(video: base.video, controls: base.controls, unit: base.unit, notes: base.notes)
        }
        var file = MuffinLayoutFile.capture(name: "native", from: base, safeArea: safeArea,
                                            pointsPerInch: pointsPerInch)
        for g in PadGroup.allCases {
            let a = adjustment(for: g)
            guard !a.dx.isZero || !a.dy.isZero || a.scale != 1 else { continue }
            var v = file.groups[g.rawValue] ?? GroupPlacement(dx: 0, dy: 0, scale: 1)
            v.dx += a.dx; v.dy += a.dy; v.scale *= a.scale
            file.groups[g.rawValue] = v.clamped
        }
        let fitted = PadPresetFitter.fit(file, container: container, safeArea: safeArea, pointsPerInch: pointsPerInch)
        return PreviewResolved(video: base.video, controls: fitted.controls, unit: fitted.unit,
                               notes: base.notes + fitted.interventions.map(\.detail))
    }
}

/// What PreviewControllerPad and EmulatorViewOptimized both need out of a resolve: the
/// controls to draw and the video rect to constrain the render surface to. `video` always
/// comes from a fresh four-laws resolve for the actual running device - a .muffinlyt only
/// ever transplants button placement, never the picture.
struct PreviewResolved {
    var video: CGRect
    var controls: [String: PadLayout.Placement]
    var unit: CGFloat
    var notes: [String]
}
