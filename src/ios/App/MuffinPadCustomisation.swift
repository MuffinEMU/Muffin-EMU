// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

//
//  MuffinPadCustomisation.swift
//  Muffin - movable/resizable button groups, colour presets, and the two file formats.
//
//  Three things live here:
//
//  1. `PadGroup` - the nine things a user can pick up and move. The shipping
//     `ControllerCustomLayout` already stores {dx, dy, scale} per element and already
//     groups L+ZL and R+ZR; this is the same idea at a coarser grain, so the
//     storage does not change, only `groupID(for:)` gets coarser.
//
//  2. `.muffinlyt` and `.muffinclr` - a layout and a colour scheme as files, so either can
//     be shared, versioned or shipped as a preset.
//
//  3. `PadPresetFitter` - what happens when a layout authored on one device is opened on
//     another. It fits, and then fixes ONLY what is actually broken.
//

import CoreGraphics
import Foundation

// MARK: - Colour

/// Straight RGBA, 0...1, Codable as a hex string plus alpha so a `.muffinclr` stays
/// readable and hand-editable rather than turning into a wall of floats.
struct MuffinRGBA: Codable, Equatable {
    var r: Double, g: Double, b: Double, a: Double

    init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    init(_ hex: String, _ alpha: Double = 1) {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt32(s, radix: 16) ?? 0
        self.init(r: Double((v >> 16) & 0xFF) / 255,
                  g: Double((v >> 8) & 0xFF) / 255,
                  b: Double(v & 0xFF) / 255, a: alpha)
    }

    var hex: String { String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255)) }

    enum CodingKeys: String, CodingKey { case hex, alpha }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.init(try c.decode(String.self, forKey: .hex),
                  try c.decodeIfPresent(Double.self, forKey: .alpha) ?? 1)
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(hex, forKey: .hex)
        if a != 1 { try c.encode(a, forKey: .alpha) }
    }
}

// MARK: - The nine groups

/// What a user can pick up and move as one thing.
///
/// The grain matters. A/B/X/Y dragged as four separate circles is not a feature, it is a
/// way to build a diamond that is not a diamond - and the diamond is the part that came
/// off the hardware. So the cluster moves, and the relationships inside it are kept.
enum PadGroup: String, CaseIterable, Codable, Identifiable {
    case shoulderL, shoulderR, stickL, stickR, dpad, face, start, select, home

    var id: String { rawValue }

    /// Which control ids travel with this group.
    var controlIDs: [String] {
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
    var anchorControl: String {
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

    var title: String {
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
    var caption: String? {
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
    enum Anchor: String, Codable { case bottomLeading, bottomTrailing, bottomCentre }

    var anchor: Anchor {
        switch self {
        case .shoulderL, .stickL, .dpad:            return .bottomLeading
        case .shoulderR, .stickR, .face, .start, .select: return .bottomTrailing
        case .home:                                 return .bottomCentre
        }
    }

    func anchorPoint(in safeArea: CGRect) -> CGPoint {
        switch anchor {
        case .bottomLeading:  return CGPoint(x: safeArea.minX, y: safeArea.maxY)
        case .bottomTrailing: return CGPoint(x: safeArea.maxX, y: safeArea.maxY)
        case .bottomCentre:   return CGPoint(x: safeArea.midX, y: safeArea.maxY)
        }
    }

    /// Positive x is always *inboard*, positive y is always *up*. Mirroring the sign for
    /// the trailing side means a left-hand offset and its right-hand twin are the same
    /// numbers, so a symmetric layout reads as symmetric in the file.
    var inboardSign: CGFloat { anchor == .bottomTrailing ? -1 : 1 }

    static func group(containing controlID: String) -> PadGroup? {
        allCases.first { $0.controlIDs.contains(controlID) }
    }
}

/// Where one group sits, in units of D from its anchor corner, plus its own size.
struct GroupPlacement: Codable, Equatable {
    /// Inboard from the anchor corner, in D.
    var dx: Double
    /// Up from the anchor corner, in D.
    var dy: Double
    /// Uniform. Wider than the shipping 0.5...2.0 for more freedom,
    /// and uniform because a d-pad stretched on one axis stops being the shape that was
    /// measured.
    var scale: Double = 1.0

    static let minScale = 0.4
    static let maxScale = 2.5
    var clamped: GroupPlacement { GroupPlacement(dx: dx, dy: dy, scale: min(max(scale, Self.minScale), Self.maxScale)) }
}

// MARK: - The files

/// `.muffinlyt` - a controller layout.
struct MuffinLayoutFile: Codable, Equatable {
    static let fileExtension = "muffinlyt"
    static let currentVersion = 1

    var version: Int = currentVersion
    var name: String
    /// What it was made on. Not used to place anything - kept so the app can say "this was
    /// made for an iPad Pro" when it has to adapt it, instead of adapting silently.
    var authoredWidth: Double
    var authoredHeight: Double
    var authoredPointsPerInch: Double
    /// The author's D, and the life-size D of the device they authored on. The ratio is
    /// the intent: "I wanted buttons at 85% of the real thing."
    var unit: Double
    var lifeUnit: Double
    var groups: [String: GroupPlacement]

    var lifeSizeFraction: Double { lifeUnit > 0 ? unit / lifeUnit : 1 }

    func encoded() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }
    static func decode(_ data: Data) throws -> MuffinLayoutFile {
        let f = try JSONDecoder().decode(MuffinLayoutFile.self, from: data)
        guard f.version <= currentVersion else { throw CocoaError(.fileReadCorruptFile) }
        return f
    }

    /// Capture the layout currently on screen.
    static func capture(name: String, from layout: PadLayout, safeArea: CGRect,
                        pointsPerInch: CGFloat, scales: [PadGroup: Double] = [:]) -> MuffinLayoutFile {
        var groups: [String: GroupPlacement] = [:]
        for g in PadGroup.allCases {
            guard let c = layout.controls[g.anchorControl]?.centre else { continue }
            let a = g.anchorPoint(in: safeArea)
            groups[g.rawValue] = GroupPlacement(
                dx: Double((c.x - a.x) * g.inboardSign / layout.unit),
                dy: Double((a.y - c.y) / layout.unit),
                scale: scales[g] ?? 1.0)
        }
        return MuffinLayoutFile(name: name,
                                authoredWidth: Double(safeArea.width),
                                authoredHeight: Double(safeArea.height),
                                authoredPointsPerInch: Double(pointsPerInch),
                                unit: Double(layout.unit),
                                lifeUnit: Double(layout.lifeSizeUnit),
                                groups: groups)
    }
}

/// `.muffinclr` - a colour scheme.
///
/// Keyed by control id, not by group, because A/B/X/Y want four different colours and
/// everything else usually wants one. `fills["default"]` catches anything unlisted, so a
/// three-line file is a valid scheme.
struct MuffinColourFile: Codable, Equatable {
    static let fileExtension = "muffinclr"
    static let currentVersion = 1

    var version: Int = currentVersion
    var name: String
    var fills: [String: MuffinRGBA]
    var glyphs: [String: MuffinRGBA]
    var outline: MuffinRGBA
    /// How much more opaque a control goes while held. The shipping pad does this by
    /// jumping fill alpha from 0.88 to 1.0; expressing it as a boost keeps that behaviour
    /// for a translucent scheme, where jumping straight to 1.0 would look like a flash.
    var pressedAlphaBoost: Double = 0.12
    /// Painted behind the pad in framed and shell modes, where there is a bezel to paint.
    var shell: MuffinRGBA?

    func fill(_ controlID: String) -> MuffinRGBA {
        fills[controlID] ?? fills[PadGroup.group(containing: controlID)?.rawValue ?? ""]
            ?? fills["default"] ?? MuffinRGBA("#CDCDCD")
    }
    func glyph(_ controlID: String) -> MuffinRGBA {
        glyphs[controlID] ?? glyphs[PadGroup.group(containing: controlID)?.rawValue ?? ""]
            ?? glyphs["default"] ?? MuffinRGBA("#333333")
    }
    /// The alpha a control is actually painted at, given whether it is held.
    func alpha(_ controlID: String, pressed: Bool) -> Double {
        min(1, fill(controlID).a + (pressed ? pressedAlphaBoost : 0))
    }

    func encoded() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }
    static func decode(_ data: Data) throws -> MuffinColourFile {
        let f = try JSONDecoder().decode(MuffinColourFile.self, from: data)
        guard f.version <= currentVersion else { throw CocoaError(.fileReadCorruptFile) }
        return f
    }
}

// MARK: - Opening a layout that was made for something else

/// Fit a layout to a device it was not authored on, then fix only what is actually broken.
///
/// Pure fit alone can scale buttons below the touch floor (an iPad Pro layout on an
/// iPhone becomes unplayably small); a full re-solve ignores the preset. So: fit, then
/// intervene only where a rule is broken, and report what was changed.
enum PadPresetFitter {

    struct Intervention: Equatable {
        enum Kind: String { case scaledToFit, raisedToTouchFloor, movedInsideSafeArea, separatedOverlap, fellBackToNative }
        var kind: Kind
        var group: PadGroup?
        var detail: String
    }

    struct Fitted {
        var unit: CGFloat
        var centres: [PadGroup: CGPoint]
        var controls: [String: PadLayout.Placement]
        var interventions: [Intervention]
        /// True when nothing had to be touched - the layout transferred as authored.
        var isFaithful: Bool { interventions.isEmpty }
    }

    static func fit(_ file: MuffinLayoutFile,
                    container: CGSize,
                    safeArea: CGRect,
                    pointsPerInch: CGFloat) -> Fitted {

        // The native layout for this device supplies every control's shape and its offset
        // within its own group. Only the group *positions* come from the file.
        let native = PadLayout.resolve(container: container, safeArea: safeArea,
                                       pointsPerInch: pointsPerInch)
        var log: [Intervention] = []

        // The author's intent is a fraction of life-size, not a number of points: they
        // chose "85% of a real GamePad", and 85% is what should survive the trip.
        var unit = native.lifeSizeUnit * CGFloat(file.lifeSizeFraction)

        func centres(at u: CGFloat) -> [PadGroup: CGPoint] {
            var out: [PadGroup: CGPoint] = [:]
            for g in PadGroup.allCases {
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
        for g in PadGroup.allCases {
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
        if unit < PadLayout.touchFloor {
            log.append(.init(kind: .raisedToTouchFloor, group: nil,
                             detail: String(format: "%.1f -> %.0f pt, the 44 pt minimum", unit, PadLayout.touchFloor)))
            unit = PadLayout.touchFloor
        }

        // 3. Anything hanging off the safe area comes back in - per group, silently, so
        //    it can be re-applied after every later shrink without spamming the log; the
        //    log entries below are written once, from the position the pad actually ends
        //    up at.
        @discardableResult
        func clampToSafeArea(_ p: inout [PadGroup: CGPoint], at u: CGFloat) -> Set<PadGroup> {
            var moved: Set<PadGroup> = []
            for g in PadGroup.allCases {
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
        var shrinkSteps = 0, fellBack: Set<PadGroup> = []
        // Terminates: each pass either shrinks (bounded by the touch floor) or permanently
        // resolves one pair by falling back to native (at most one per group).
        while let clash = firstOverlap(placed, file: file, native: native, unit: unit) {
            let next = unit * 0.97
            if next < PadLayout.touchFloor * 0.9 || (fellBack.contains(clash.0) && fellBack.contains(clash.1)) {
                for g in [clash.0, clash.1] where !fellBack.contains(g) {
                    if let n = native.controls[g.anchorControl]?.centre {
                        placed[g] = n
                        fellBack.insert(g)
                        log.append(.init(kind: .fellBackToNative, group: g,
                                         detail: "\(g.title) could not be made to fit; using this device's own position"))
                    }
                }
                clampToSafeArea(&placed, at: unit)
                if fellBack.count >= PadGroup.allCases.count { break }   // nothing left to fall back
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
        for g in PadGroup.allCases {
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
    static func buildControls(_ placed: [PadGroup: CGPoint], unit: CGFloat,
                                      file: MuffinLayoutFile, native: PadLayout) -> [String: PadLayout.Placement] {
        var controls: [String: PadLayout.Placement] = [:]
        for g in PadGroup.allCases {
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
    private static func groupExtentInD(_ g: PadGroup, native: PadLayout, scale: Double) -> CGSize {
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
    private static func groupBounds(_ g: PadGroup, native: PadLayout, unit: CGFloat, scale: Double)
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
    private static func groupExtent(_ g: PadGroup, native: PadLayout, unit: CGFloat, scale: Double) -> CGSize {
        guard let b = groupBounds(g, native: native, unit: unit, scale: scale) else { return .zero }
        return CGSize(width: b.maxX - b.minX, height: b.maxY - b.minY)
    }

    /// A control's shape as axis-aligned or circular primitives. A cross is two rectangles,
    /// not its bounding square: +/- in elbow mode sits in the d-pad's empty corner, which
    /// a bounding-box test would report as a false overlap.
    private enum Primitive { case circle(CGPoint, CGFloat); case rect(CGPoint, CGFloat, CGFloat) }

    private static func primitives(for p: PadLayout.Placement) -> [Primitive] {
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

    private static func firstOverlap(_ placed: [PadGroup: CGPoint], file: MuffinLayoutFile,
                                     native: PadLayout, unit: CGFloat) -> (PadGroup, PadGroup)? {
        let controls = buildControls(placed, unit: unit, file: file, native: native)
        let gs = PadGroup.allCases.filter { placed[$0] != nil }
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
