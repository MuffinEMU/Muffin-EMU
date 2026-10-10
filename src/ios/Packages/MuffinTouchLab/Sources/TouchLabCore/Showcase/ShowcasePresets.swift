// Ported from MuffinEMU's showcase pad (src/ios/App/MuffinPadCustomisation.swift).
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import CoreGraphics
import Foundation

// MARK: - The nine groups

/// What a user can pick up and move as one thing.
///
/// The grain matters. A/B/X/Y dragged as four separate circles is not a feature, it is a
/// way to build a diamond that is not a diamond - and the diamond is the part that came
/// off the hardware. So the cluster moves, and the relationships inside it are kept.
public enum ShowcaseGroup: String, CaseIterable, Codable, Identifiable {
    case shoulderL, shoulderR, stickL, stickR, dpad, face, start, select, home

    public var id: String { rawValue }

    /// Which control ids travel with this group.
    public var controlIDs: [String] {
        switch self {
        case .shoulderL: return ["L", "ZL"]
        case .shoulderR: return ["R", "ZR"]
        case .stickL:    return ["stickL", "knobL"]
        case .stickR:    return ["stickR", "knobR"]
        // L3 and R3 are the stick *clicks* and are drawn as the dot at their cluster's
        // centre, so they move with the cluster they sit in, not with the sticks.
        case .dpad:      return ["dpad", "up", "down", "left", "right", "L3"]
        case .face:      return ["X", "Y", "A", "B", "R3"]
        case .start:     return ["plus"]
        case .select:    return ["minus"]
        case .home:      return ["HOME", "TV", "POWER"]
        }
    }

    /// The control whose centre defines the group's position.
    public var anchorControl: String {
        switch self {
        case .shoulderL: return "L"
        case .shoulderR: return "R"
        case .stickL:    return "stickL"
        case .stickR:    return "stickR"
        case .dpad:      return "dpad"
        case .face:      return "R3"
        case .start:     return "plus"
        case .select:    return "minus"
        case .home:      return "HOME"
        }
    }

    public var title: String {
        switch self {
        case .shoulderL: return "L and ZL"
        case .shoulderR: return "R and ZR"
        case .stickL:    return "Left stick"
        case .stickR:    return "Right stick"
        case .dpad:      return "D-pad"
        case .face:      return "A B X Y"
        case .start:     return "Start"
        case .select:    return "Select"
        case .home:      return "HOME"
        }
    }

    /// Printed under the button, as it is on the hardware: the illustration has START
    /// under the + and SELECT under the -, because each one is both things at once and
    /// the glyph alone does not say so.
    public var caption: String? {
        switch self {
        case .start:  return "START"
        case .select: return "SELECT"
        case .home:   return "HOME"
        default:      return nil
        }
    }

    /// Which corner of the safe area this group's offset is measured from.
    ///
    /// Corners rather than fractions, because a fraction of the width means something
    /// different on a 4:3 iPad and a 19.5:9 phone, and "3.16 D in from the left edge"
    /// means the same thing on both. This is what makes a layout file portable at all.
    public enum Anchor: String, Codable { case bottomLeading, bottomTrailing, bottomCentre }

    public var anchor: Anchor {
        switch self {
        case .shoulderL, .stickL, .dpad:            return .bottomLeading
        case .shoulderR, .stickR, .face, .start, .select: return .bottomTrailing
        case .home:                                 return .bottomCentre
        }
    }

    public func anchorPoint(in safeArea: CGRect) -> CGPoint {
        switch anchor {
        case .bottomLeading:  return CGPoint(x: safeArea.minX, y: safeArea.maxY)
        case .bottomTrailing: return CGPoint(x: safeArea.maxX, y: safeArea.maxY)
        case .bottomCentre:   return CGPoint(x: safeArea.midX, y: safeArea.maxY)
        }
    }

    /// Positive x is always *inboard*, positive y is always *up*. Mirroring the sign for
    /// the trailing side means a left-hand offset and its right-hand twin are the same
    /// numbers, so a symmetric layout reads as symmetric in the file.
    public var inboardSign: CGFloat { anchor == .bottomTrailing ? -1 : 1 }

    public static func group(containing controlID: String) -> ShowcaseGroup? {
        allCases.first { $0.controlIDs.contains(controlID) }
    }
}

/// Where one group sits, in units of D from its anchor corner, plus its own size.
public struct ShowcaseGroupPlacement: Codable, Equatable {
    /// Inboard from the anchor corner, in D.
    public var dx: Double
    /// Up from the anchor corner, in D.
    public var dy: Double
    /// Uniform. Wider than the shipping 0.5...2.0 for more freedom,
    /// and uniform because a d-pad stretched on one axis stops being the shape that was
    /// measured.
    public var scale: Double = 1.0

    public static let minScale = 0.4
    public static let maxScale = 2.5
    public var clamped: ShowcaseGroupPlacement { ShowcaseGroupPlacement(dx: dx, dy: dy, scale: min(max(scale, Self.minScale), Self.maxScale)) }
}

// MARK: - The files

/// `.muffinlyt` - a controller layout.
public struct ShowcaseLayoutFile: Codable, Equatable {
    public static let fileExtension = "muffinlyt"
    public static let currentVersion = 1

    public var version: Int = currentVersion
    public var name: String
    /// What it was made on. Not used to place anything - kept so the app can say "this was
    /// made for an iPad Pro" when it has to adapt it, instead of adapting silently.
    public var authoredWidth: Double
    public var authoredHeight: Double
    public var authoredPointsPerInch: Double
    /// The author's D, and the life-size D of the device they authored on. The ratio is
    /// the intent: "I wanted buttons at 85% of the real thing."
    public var unit: Double
    public var lifeUnit: Double
    public var groups: [String: ShowcaseGroupPlacement]

    public var lifeSizeFraction: Double { lifeUnit > 0 ? unit / lifeUnit : 1 }

    public func encoded() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }
    public static func decode(_ data: Data) throws -> ShowcaseLayoutFile {
        let f = try JSONDecoder().decode(ShowcaseLayoutFile.self, from: data)
        guard f.version <= currentVersion else { throw CocoaError(.fileReadCorruptFile) }
        return f
    }

    /// Capture the layout currently on screen.
    public static func capture(name: String, from layout: ShowcaseLayout, safeArea: CGRect,
                        pointsPerInch: CGFloat, scales: [ShowcaseGroup: Double] = [:]) -> ShowcaseLayoutFile {
        var groups: [String: ShowcaseGroupPlacement] = [:]
        for g in ShowcaseGroup.allCases {
            guard let c = layout.controls[g.anchorControl]?.centre else { continue }
            let a = g.anchorPoint(in: safeArea)
            groups[g.rawValue] = ShowcaseGroupPlacement(
                dx: Double((c.x - a.x) * g.inboardSign / layout.unit),
                dy: Double((a.y - c.y) / layout.unit),
                scale: scales[g] ?? 1.0)
        }
        return ShowcaseLayoutFile(name: name,
                                authoredWidth: Double(safeArea.width),
                                authoredHeight: Double(safeArea.height),
                                authoredPointsPerInch: Double(pointsPerInch),
                                unit: Double(layout.unit),
                                lifeUnit: Double(layout.lifeSizeUnit),
                                groups: groups)
    }
}


// MARK: - Opening a layout that was made for something else

/// Fit a layout to a device it was not authored on, then fix only what is actually broken.
///
/// Pure fit alone can scale buttons below the touch floor (an iPad Pro layout on an
/// iPhone becomes unplayably small); a full re-solve ignores the preset. So: fit, then
/// intervene only where a rule is broken, and report what was changed.
public enum ShowcaseFitter {

    public struct Intervention: Equatable {
        public enum Kind: String { case scaledToFit, raisedToTouchFloor, movedInsideSafeArea, separatedOverlap, fellBackToNative }
        public var kind: Kind
        public var group: ShowcaseGroup?
        public var detail: String
    }

    public struct Fitted {
        public var unit: CGFloat
        public var centres: [ShowcaseGroup: CGPoint]
        public var controls: [String: ShowcaseLayout.Placement]
        public var interventions: [Intervention]
        /// True when nothing had to be touched - the layout transferred as authored.
        public var isFaithful: Bool { interventions.isEmpty }
    }

    public static func fit(_ file: ShowcaseLayoutFile,
                    container: CGSize,
                    safeArea: CGRect,
                    pointsPerInch: CGFloat) -> Fitted {

        // The native layout for this device supplies every control's shape and its offset
        // within its own group. Only the group *positions* come from the file.
        let native = ShowcaseLayout.resolve(container: container, safeArea: safeArea,
                                       pointsPerInch: pointsPerInch)
        var log: [Intervention] = []

        // The author's intent is a fraction of life-size, not a number of points: they
        // chose "85% of a real GamePad", and 85% is what should survive the trip.
        var unit = native.lifeSizeUnit * CGFloat(file.lifeSizeFraction)

        func centres(at u: CGFloat) -> [ShowcaseGroup: CGPoint] {
            var out: [ShowcaseGroup: CGPoint] = [:]
            for g in ShowcaseGroup.allCases {
                guard let p = file.groups[g.rawValue] else { continue }
                let a = g.anchorPoint(in: safeArea)
                out[g] = CGPoint(x: a.x + CGFloat(p.dx) * u * g.inboardSign,
                                 y: a.y - CGFloat(p.dy) * u)
            }
            return out
        }

        // 1. Scale to fit. A group's position is anchor-corner-relative, so it can never
        //    run off the LEFT/RIGHT/BOTTOM edge on its own - shrinking u only pulls it
        //    closer to its own corner. The one direction that can genuinely fail is UP:
        //    a group authored on a tall device can be asked to reach higher, in points,
        //    than a short device's safe area has room for. That failure is linear and
        //    solvable directly, once each group's own half-height is expressed as a
        //    multiple of D rather than of points - which is what makes it scale-free and
        //    lets it be solved without already knowing the answer it is solving for.
        var heightLimit = CGFloat.greatestFiniteMagnitude
        for g in ShowcaseGroup.allCases {
            guard let p = file.groups[g.rawValue] else { continue }
            let halfHeightInD = groupExtentInD(g, native: native, scale: p.scale).height / 2
            let neededInD = CGFloat(p.dy) + halfHeightInD
            guard neededInD > 0 else { continue }
            heightLimit = min(heightLimit, safeArea.height / neededInD)
        }
        if heightLimit < unit {
            log.append(.init(kind: .scaledToFit, group: nil,
                             detail: String(format: "%.1f -> %.1f pt: the tallest reach needs more height than this screen has",
                                            unit, heightLimit)))
            unit = heightLimit
        }

        // 2. The touch floor. A layout is allowed to be small; it is not allowed to be
        //    unusable. Raising the unit can push things off the edge, which pass 3 catches.
        if unit < ShowcaseLayout.touchFloor {
            log.append(.init(kind: .raisedToTouchFloor, group: nil,
                             detail: String(format: "%.1f -> %.0f pt, the 44 pt minimum", unit, ShowcaseLayout.touchFloor)))
            unit = ShowcaseLayout.touchFloor
        }

        // 3. Anything hanging off the safe area comes back in - per group, silently, so
        //    it can be re-applied after every later shrink without spamming the log; the
        //    log entries below are written once, from the position the pad actually ends
        //    up at.
        @discardableResult
        func clampToSafeArea(_ p: inout [ShowcaseGroup: CGPoint], at u: CGFloat) -> Set<ShowcaseGroup> {
            var moved: Set<ShowcaseGroup> = []
            for g in ShowcaseGroup.allCases {
                guard var c = p[g], let b = groupBounds(g, native: native, unit: u,
                                                        scale: file.groups[g.rawValue]?.scale ?? 1) else { continue }
                let before = c
                let xRange = (safeArea.minX - b.minX, safeArea.maxX - b.maxX)
                let yRange = (safeArea.minY - b.minY, safeArea.maxY - b.maxY)
                c.x = xRange.0 <= xRange.1 ? min(max(c.x, xRange.0), xRange.1) : (xRange.0 + xRange.1) / 2
                c.y = yRange.0 <= yRange.1 ? min(max(c.y, yRange.0), yRange.1) : (yRange.0 + yRange.1) / 2
                if abs(c.x - before.x) > 0.5 || abs(c.y - before.y) > 0.5 { p[g] = c; moved.insert(g) }
            }
            return moved
        }

        // 4. Overlaps. Shrinking is tried first because it preserves the arrangement; only
        //    a layout that still collides at 90% of the touch floor gives up and takes
        //    this device's own position for the groups that are fighting.
        //
        //    The clamp runs again after every shrink, because `centres(at:)` rebuilds raw
        //    positions with no memory of earlier clamping.
        var placed = centres(at: unit)
        clampToSafeArea(&placed, at: unit)
        var shrinkSteps = 0, fellBack: Set<ShowcaseGroup> = []
        // Terminates: each pass either shrinks (bounded by the touch floor) or permanently
        // resolves one pair by falling back to native (at most one per group).
        while let clash = firstOverlap(placed, file: file, native: native, unit: unit) {
            let next = unit * 0.97
            if next < ShowcaseLayout.touchFloor * 0.9 || (fellBack.contains(clash.0) && fellBack.contains(clash.1)) {
                for g in [clash.0, clash.1] where !fellBack.contains(g) {
                    if let n = native.controls[g.anchorControl]?.centre {
                        placed[g] = n
                        fellBack.insert(g)
                        log.append(.init(kind: .fellBackToNative, group: g,
                                         detail: "\(g.title) could not be made to fit; using this device's own position"))
                    }
                }
                clampToSafeArea(&placed, at: unit)
                if fellBack.count >= ShowcaseGroup.allCases.count { break }   // nothing left to fall back
                continue
            }
            shrinkSteps += 1
            unit = next
            placed = centres(at: unit)
            for g in fellBack {
                if let n = native.controls[g.anchorControl]?.centre { placed[g] = n }
            }
            clampToSafeArea(&placed, at: unit)
        }
        if shrinkSteps > 0 {
            log.append(.init(kind: .separatedOverlap, group: nil,
                             detail: String(format: "shrunk %d%% to stop groups overlapping", Int((1 - pow(0.97, Double(shrinkSteps))) * 100))))
        }
        // What actually moved, for the log: the raw (unclamped) position the settled
        // unit would give each group, versus where the clamp actually put it. Comparing
        // against the raw position - not against wherever an earlier loop iteration left
        // it - is what makes this an honest "here is what safe-area clamping cost you"
        // rather than a number that depends on how many shrink iterations happened to run.
        let raw = centres(at: unit)
        for g in ShowcaseGroup.allCases {
            guard let c = placed[g], let r = raw[g], abs(c.x - r.x) > 0.5 || abs(c.y - r.y) > 0.5 else { continue }
            log.append(.init(kind: .movedInsideSafeArea, group: g,
                             detail: String(format: "%@ moved %.0f, %.0f pt back on screen",
                                            g.title, c.x - r.x, c.y - r.y)))
        }

        // The controls: each keeps its offset within its own group, from the native
        // layout, so the inside of a cluster is never disturbed by any of the above.
        let controls = buildControls(placed, unit: unit, file: file, native: native)
        return Fitted(unit: unit, centres: placed, controls: controls, interventions: log)
    }

    // MARK: helpers

    /// Every control at a candidate placement and unit - the same transform the final
    /// return value uses, pulled out so the overlap check can test it on real shapes
    /// instead of guessing from a group's bounding box.
    public static func buildControls(_ placed: [ShowcaseGroup: CGPoint], unit: CGFloat,
                                      file: ShowcaseLayoutFile, native: ShowcaseLayout) -> [String: ShowcaseLayout.Placement] {
        var controls: [String: ShowcaseLayout.Placement] = [:]
        for g in ShowcaseGroup.allCases {
            guard let centre = placed[g], let anchor = native.controls[g.anchorControl]?.centre else { continue }
            let s = CGFloat(file.groups[g.rawValue]?.scale ?? 1) * unit / native.unit
            for id in g.controlIDs {
                guard let p = native.controls[id] else { continue }
                let rel = CGPoint(x: (p.centre.x - anchor.x) * s, y: (p.centre.y - anchor.y) * s)
                let at = CGPoint(x: centre.x + rel.x, y: centre.y + rel.y)
                switch p {
                case .circle(_, let d):
                    controls[id] = .circle(centre: at, diameter: d * s)
                case .pill(_, let sz, let r):
                    controls[id] = .pill(centre: at, size: CGSize(width: sz.width * s, height: sz.height * s), corner: r * s)
                case .cross(_, let sz, let arm):
                    controls[id] = .cross(centre: at, size: CGSize(width: sz.width * s, height: sz.height * s), arm: arm * s)
                }
            }
        }
        return controls
    }

    /// A group's own footprint, in multiples of D rather than points - a ratio taken
    /// against the device it was actually resolved for, so it carries across devices
    /// undistorted. This is what makes the height precheck solvable in one step instead
    /// of needing to already know the unit it is trying to find.
    private static func groupExtentInD(_ g: ShowcaseGroup, native: ShowcaseLayout, scale: Double) -> CGSize {
        let full = groupExtent(g, native: native, unit: native.unit, scale: scale)
        return CGSize(width: full.width / native.unit, height: full.height / native.unit)
    }

    /// A group's true bounding box at a candidate unit, as offsets from its own anchor
    /// control's centre - NOT assumed symmetric, because most groups are not. ZL sits
    /// entirely to one side of L; TV and POWER sit entirely to one side of HOME. Treating
    /// either as "half the total width, to each side of centre" clamps the narrow side
    /// too hard and lets the wide side hang off the screen - which is exactly what put
    /// L, ZL and the menu row off the edge on a big-iPad-to-phone transplant before this
    /// was measured honestly instead of assumed.
    private static func groupBounds(_ g: ShowcaseGroup, native: ShowcaseLayout, unit: CGFloat, scale: Double)
        -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)? {
        guard let anchor = native.controls[g.anchorControl]?.centre else { return nil }
        let s = CGFloat(scale) * unit / native.unit
        var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        for id in g.controlIDs {
            guard let p = native.controls[id] else { continue }
            let sz = p.boundingSize
            let cx = (p.centre.x - anchor.x) * s, cy = (p.centre.y - anchor.y) * s
            minX = min(minX, cx - sz.width * s / 2);  maxX = max(maxX, cx + sz.width * s / 2)
            minY = min(minY, cy - sz.height * s / 2); maxY = max(maxY, cy + sz.height * s / 2)
        }
        guard minX <= maxX else { return nil }
        return (minX, maxX, minY, maxY)
    }

    /// Total span only - safe for the height precheck, where every group in this control
    /// set (checked once, by hand: dpad+L3, face+R3, both sticks, both shoulders, HOME's
    /// row) happens to keep all of its members at the same y as the anchor. Horizontal
    /// asymmetry exists (shoulders, the HOME row); vertical does not.
    private static func groupExtent(_ g: ShowcaseGroup, native: ShowcaseLayout, unit: CGFloat, scale: Double) -> CGSize {
        guard let b = groupBounds(g, native: native, unit: unit, scale: scale) else { return .zero }
        return CGSize(width: b.maxX - b.minX, height: b.maxY - b.minY)
    }

    /// A control's shape as axis-aligned or circular primitives. A cross is two rectangles,
    /// not its bounding square: +/- in elbow mode sits in the d-pad's empty corner, which
    /// a bounding-box test would report as a false overlap.
    private enum Primitive { case circle(CGPoint, CGFloat); case rect(CGPoint, CGFloat, CGFloat) }

    private static func primitives(for p: ShowcaseLayout.Placement) -> [Primitive] {
        switch p {
        case .circle(let c, let d): return [.circle(c, d / 2)]
        case .pill(let c, let s, _): return [.rect(c, s.width / 2, s.height / 2)]
        case .cross(let c, let s, let arm):
            return [.rect(c, s.width / 2, arm / 2), .rect(c, arm / 2, s.height / 2)]
        }
    }

    /// Separation between two primitives; negative means they overlap, by that much.
    private static func separation(_ a: Primitive, _ b: Primitive) -> CGFloat {
        switch (a, b) {
        case (.circle(let ca, let ra), .circle(let cb, let rb)):
            return hypot(ca.x - cb.x, ca.y - cb.y) - (ra + rb)
        case (.rect(let ca, let hwA, let hhA), .rect(let cb, let hwB, let hhB)):
            return max(abs(ca.x - cb.x) - (hwA + hwB), abs(ca.y - cb.y) - (hhA + hhB))
        case (.circle(let cc, let r), .rect(let rc, let hw, let hh)),
             (.rect(let rc, let hw, let hh), .circle(let cc, let r)):
            let dx = max(0, abs(cc.x - rc.x) - hw), dy = max(0, abs(cc.y - rc.y) - hh)
            return hypot(dx, dy) - r
        }
    }

    private static func firstOverlap(_ placed: [ShowcaseGroup: CGPoint], file: ShowcaseLayoutFile,
                                     native: ShowcaseLayout, unit: CGFloat) -> (ShowcaseGroup, ShowcaseGroup)? {
        let controls = buildControls(placed, unit: unit, file: file, native: native)
        let gs = ShowcaseGroup.allCases.filter { placed[$0] != nil }
        for i in 0..<gs.count {
            for j in (i + 1)..<gs.count {
                let a = gs[i], b = gs[j]
                for idA in a.controlIDs {
                    guard let pa = controls[idA] else { continue }
                    for idB in b.controlIDs {
                        guard let pb = controls[idB] else { continue }
                        for sa in primitives(for: pa) {
                            for sb in primitives(for: pb) where separation(sa, sb) < -0.5 {
                                return (a, b)
                            }
                        }
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - The three layout presets, and resolving one onto a screen

/// The three layout presets of the showcase pad (PreviewShowcase.swift). The two that are
/// not `.native` are .muffinlyt files captured on a reference iPad Pro and then transplanted
/// onto whatever device is running by `ShowcaseFitter`.
public enum ShowcaseLayoutPreset: String, CaseIterable, Identifiable {
    case native, iPadPro2020, compact

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .native:      return "Native (this device)"
        case .iPadPro2020: return "iPad Pro 12.9\" (2020)"
        case .compact:     return "Compact"
        }
    }

    public var summary: String {
        switch self {
        case .native:
            return "This device's own layout."
        case .iPadPro2020:
            return "The layout from a 12.9-inch iPad Pro, fitted to your screen."
        case .compact:
            return "70% of life-size: smaller buttons, more of the picture."
        }
    }

    /// The reference device each non-native preset was captured on. `.native` has none.
    private var reference: (container: CGSize, safeArea: CGRect, pointsPerInch: CGFloat, userScale: CGFloat)? {
        switch self {
        case .native:
            return nil
        case .iPadPro2020:
            // iPad Pro 12.9" (2020): 1366x1024 pt container, 132 ppi, no notch.
            return (CGSize(width: 1366, height: 1024), CGRect(x: 0, y: 0, width: 1366, height: 1004), 132, 1.0)
        case .compact:
            // Same reference device at 70% scale.
            return (CGSize(width: 1366, height: 1024), CGRect(x: 0, y: 0, width: 1366, height: 1004), 132, 0.7)
        }
    }

    /// The captured file, or nil for `.native` (resolve fresh, no transplant).
    public func layoutFile(displayMode: ShowcaseLayout.DisplayMode) -> ShowcaseLayoutFile? {
        guard let ref = reference else { return nil }
        let layout = ShowcaseLayout.resolve(container: ref.container, safeArea: ref.safeArea,
                                            pointsPerInch: ref.pointsPerInch, userScale: ref.userScale,
                                            displayMode: displayMode)
        return ShowcaseLayoutFile.capture(name: title, from: layout, safeArea: ref.safeArea,
                                          pointsPerInch: ref.pointsPerInch)
    }
}

/// What the pad needs out of a resolve: the controls, the picture rect the layout leaves
/// (or, in Fit, the full-bleed one), and the button size.
public struct ShowcaseResolved {
    public var video: CGRect
    public var controls: [String: ShowcaseLayout.Placement]
    public var unit: CGFloat
    public var notes: [String]
    public var mode: ShowcaseLayout.Mode
}

public enum ShowcaseResolver {
    /// An iPhone held upright is always Native (PreviewPadStore.effectiveDisplayMode): Fit
    /// would leave the picture mid-screen with the controls floating over it.
    public static func effectiveDisplayMode(_ requested: ShowcaseLayout.DisplayMode, container: CGSize,
                                            isPhone: Bool) -> ShowcaseLayout.DisplayMode {
        if isPhone, container.height > container.width { return .native }
        return requested
    }

    /// PreviewPadStore.resolve without the drag/resize adjustments (TouchLab does not expose
    /// them): the preset, fitted (or resolved fresh, for `.native`) onto this container.
    /// `userScale` is a size multiplier on top of life-size; it scales the resolved unit and,
    /// for a transplanted preset, the captured file's intended fraction of life-size.
    public static func resolve(preset: ShowcaseLayoutPreset,
                               displayMode requested: ShowcaseLayout.DisplayMode,
                               container: CGSize, safeArea: CGRect, pointsPerInch: CGFloat,
                               isPhone: Bool, userScale: CGFloat = 1) -> ShowcaseResolved {
        let displayMode = effectiveDisplayMode(requested, container: container, isPhone: isPhone)
        if var file = preset.layoutFile(displayMode: displayMode) {
            file.unit *= Double(userScale)
            let fitted = ShowcaseFitter.fit(file, container: container, safeArea: safeArea,
                                            pointsPerInch: pointsPerInch)
            // The picture is not part of a .muffinlyt: what it looks like here follows the
            // four laws fresh, as if no preset were loaded.
            let nativeForVideo = ShowcaseLayout.resolve(container: container, safeArea: safeArea,
                                                        pointsPerInch: pointsPerInch, userScale: userScale,
                                                        displayMode: displayMode)
            return ShowcaseResolved(video: nativeForVideo.video, controls: fitted.controls, unit: fitted.unit,
                                    notes: fitted.interventions.map(\.detail), mode: nativeForVideo.mode)
        }
        let base = ShowcaseLayout.resolve(container: container, safeArea: safeArea,
                                          pointsPerInch: pointsPerInch, userScale: userScale,
                                          displayMode: displayMode)
        return ShowcaseResolved(video: base.video, controls: base.controls, unit: base.unit,
                                notes: base.notes, mode: base.mode)
    }
}
