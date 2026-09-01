//
//  GamePadGeometry.swift
//  Muffin - the on-screen pad, taken from the Wii U GamePad hardware.
//
//  NOT IN THE BUILD YET. `src/ios/project.yml` pulls `src/ios/App` in as a group, so
//  every .swift in that folder compiles; this file lives under docs/ so it cannot break
//  a build before anyone has read it. Moving it into `src/ios/App/` is the whole of
//  "wiring it in" - see WIRING at the bottom.
//
//  ---------------------------------------------------------------------------------
//  Where the numbers come from
//
//  The shipping `ControllerGeometry` is measured from IMG_3278.jpeg, a screenshot of an
//  on-screen pad. This one is measured from the GamePad itself: the official Wii U
//  controller illustration, at 0.425 mm per pixel. That scale is not assumed, it is
//  checked twice against the real hardware and agrees both times:
//
//      600 px body  x 0.425 = 255.0 mm   (Nintendo: 255 mm)
//      314 px body  x 0.425 = 133.5 mm   (Nintendo: 134 mm)
//      324 x 185 px screen  = 137.7 x 78.6 mm -> 158 mm diagonal (Nintendo: 6.2 in)
//
//  So every constant below is a real hardware dimension, and "life-size" is a claim
//  this file can actually make good on.
//
//  The unit is D, one face-button diameter = 10.625 mm, the same unit
//  `ControllerGeometry` already uses. Pleasingly, the body is exactly 24 D wide.
//
//  What is measured and what is not: everything on the front face is measured. The
//  shoulders are not - L/R/ZL/ZR are on the top edge and do not appear in a front view -
//  so their pill size is kept from the IMG_3278 measurement and their position is
//  placed, directly above their own stick, which is where they are on the hardware.
//  They are the only placed geometry here, and they are marked at their definition.
//

import CoreGraphics
import Foundation

// MARK: - The hardware, in face-button diameters

enum GamePadGeometry {

    /// One face-button diameter, in millimetres. The unit everything else is in, and
    /// the number that makes "life-size" mean something.
    static let unitMM: CGFloat = 10.625

    // Face buttons: A/B/X/Y, a diamond that very nearly touches.
    static let faceDiameter: CGFloat = 1.000      // 10.625 mm
    static let faceHalfX: CGFloat    = 0.960      // Y<->A half pitch, 10.20 mm
    static let faceHalfY: CGFloat    = 0.950      // X<->B half pitch, 10.09 mm

    // The d-pad is a solid cross, not four circles. This is the single biggest visual
    // difference from the screenshot-derived layout.
    static let dpadWidth: CGFloat  = 2.280        // 24.225 mm
    static let dpadHeight: CGFloat = 2.240        // 23.80 mm
    static let dpadArm: CGFloat    = 0.760        // 8.075 mm, the width of one arm

    // Sticks.
    static let stickBase: CGFloat = 1.960         // 20.825 mm dish
    static let stickKnob: CGFloat = 1.120         // 11.9 mm cap
    /// Stick centre -> cluster centre. Both halves agree on this to within 0.1 mm, which
    /// is the strongest evidence in the measurements that it is a designed relationship
    /// and not an accident: 29.65 mm at 69.87 degrees, up and outboard.
    static let stickArm: CGFloat = 2.79020        // 29.646 mm
    static let stickArmAngle: CGFloat = 69.8737 * .pi / 180

    // System buttons.
    static let systemDiameter: CGFloat = 0.680    // +/-, 7.225 mm
    static let homeDiameter: CGFloat   = 1.040    // 11.05 mm
    static let menuDiameter: CGFloat   = 0.640    // TV / POWER, 6.8 mm

    // The body, for the framed and shell modes that draw one.
    static let bodyWidth: CGFloat  = 24.000       // 255 mm - exactly 24 face buttons
    static let bodyHeight: CGFloat = 12.560       // 133.45 mm
    static let screenWidth: CGFloat  = 12.92235   // 137.3 mm, normalised to exactly 16:9
    static let screenHeight: CGFloat = 7.26588    // 77.2 mm
    static let screenCentreFromTop: CGFloat = 6.280

    /// Both clusters sit at the same height on the hardware - 60.14 mm from the body's
    /// top edge, measured independently on each side and agreeing to 0.02 mm. Keeping
    /// the d-pad and A/B/X/Y level with each other is the layout's signature, and it is
    /// why the anchors below share one y.
    static let clusterFromBodyTop: CGFloat = 5.660
    static let dpadFromBodyLeft: CGFloat   = 3.160    // 33.575 mm
    static let abxyFromBodyRight: CGFloat  = 3.040    // 32.30 mm
    static let homeFromBodyTop: CGFloat    = 11.320   // 120.275 mm
    static let tvFromHome: CGFloat         = 5.08047  // 53.98 mm
    static let powerFromHome: CGFloat      = 6.28047  // 66.73 mm

    /// Where + and - really live: both on the right, stacked under A/B/X/Y, + above -.
    /// Not one per side. That is a convention on-screen pads invented; the hardware
    /// never did it.
    static let plusFromABXY  = CGPoint(x: -1.080, y: 2.420)
    static let minusFromABXY = CGPoint(x: -1.080, y: 3.660)

    /// Where + and - go when 3.66 D of room below the face buttons does not exist - the
    /// diagonal between the stick and the cluster, which the hardware leaves empty and a
    /// thumb already sweeps across. One per side at that point, because a phone that put
    /// both on the right would push the right cluster far enough inboard to cover the
    /// middle of the picture.
    static let systemElbow = CGPoint(x: 1.414, y: -1.414)

    // PLACED, NOT MEASURED - the shoulders are on the top edge, not the front face.
    // The pill size is the one real measurement available (IMG_3278, via the shipping
    // layout); the position is "centred above its own stick", as on the hardware.
    static let shoulderSize = CGSize(width: 1.151, height: 0.874)
    static let shoulderCorner: CGFloat = 0.235
    static let shoulderSpread: CGFloat = 0.675    // half the L<->ZL centre distance
    static let shoulderGap: CGFloat    = 0.200    // clearance above the stick dish
    static var shoulderDY: CGFloat { -(stickBase / 2 + shoulderGap + shoulderSize.height / 2) }

    // MARK: Derived extents

    /// How far the cluster reaches above its centre: the stick arm, plus the stick, plus
    /// the shoulder stacked above it.
    static var fixedTopExtent: CGFloat { -shoulderDY + shoulderSize.height / 2 }   // 2.054
    static func topExtent(armAngle: CGFloat) -> CGFloat {
        stickArm * sin(armAngle) + fixedTopExtent
    }
    static func outboardExtent(armAngle: CGFloat) -> CGFloat {
        max(dpadWidth / 2, stickArm * cos(armAngle) + max(stickBase / 2,
                                                          shoulderSpread + shoulderSize.width / 2))
    }
    /// What hangs below the centre, which depends entirely on where +/- ended up.
    static let bottomExtentHardware: CGFloat = 4.000   // minus, at 3.66 + its own radius
    static let bottomExtentElbow: CGFloat    = 1.450   // B, at 0.95 + its own radius

    static func verticalNeed(armAngle: CGFloat, hardwareSystem: Bool) -> CGFloat {
        topExtent(armAngle: armAngle)
            + (hardwareSystem ? bottomExtentHardware : bottomExtentElbow)
            + 2 * PadLayout.edgeMargin
    }

    /// Outboard reach, the inboard reach of each half, and the total width - all in D.
    static func extents(armAngle: CGFloat, hardwareSystem: Bool)
        -> (outboard: CGFloat, inboardL: CGFloat, inboardR: CGFloat, total: CGFloat) {
        let inL = hardwareSystem ? dpadWidth / 2 : systemElbow.x + systemDiameter / 2
        let inR = max(faceHalfX + 0.5, inL)
        let out = outboardExtent(armAngle: armAngle)
        return (out, inL, inR, (out + inL) + (out + inR))
    }

    /// The largest D at which both clusters fit side by side and still clear each other.
    ///
    /// The two edge margins belong in this denominator. Leaving them out is not a rounding
    /// error - it prescribes a *negative* gap, so the clusters get placed overlapping by
    /// construction. That is exactly what happened in Slide Over and in portrait, where Y
    /// was drawn on top of the d-pad's right arm.
    static func widthFit(armAngle: CGFloat, hardwareSystem: Bool, width: CGFloat) -> CGFloat {
        width / (extents(armAngle: armAngle, hardwareSystem: hardwareSystem).total
                 + 2 * PadLayout.edgeMargin + PadLayout.minimumClusterGap)
    }
}

// MARK: - Resolving it onto a screen

struct PadLayout {

    /// How the pad and the picture share the glass.
    enum Mode: String {
        /// The GamePad, drawn: bezel and all, picture in the LCD's place, nothing
        /// overlapping. Chosen when the framed picture would be at least as big as the
        /// hardware's own 6.2 in screen - below that the shell is nostalgia bought with a
        /// smaller picture than the real thing had, which is the wrong trade.
        case framed
        /// Picture full-bleed, controls floating over its outer thirds.
        case overlay
        /// Picture on an external display; the iPad is nothing but a GamePad.
        case shell
        /// Portrait: picture along the top, both clusters on the bottom corners.
        case stacked
    }

    enum SystemPlacement: String { case hardware, elbow }

    /// A plain user setting, not something the app auto-picks: which of the two ways the
    /// picture and the pad can share the glass. FIT fills the screen and floats the
    /// controls on top of it. NATIVE sizes the picture to whatever the clusters leave
    /// room for and never lets a control cover it - which on a device where that room is
    /// small (a phone) means a small, letterboxed picture. That is the accepted cost of
    /// choosing NATIVE, not a bug to route around.
    enum DisplayMode: String, Codable, CaseIterable {
        case fit, native
        var title: String { self == .fit ? "Fit" : "Native" }
    }

    enum Placement {
        case circle(centre: CGPoint, diameter: CGFloat)
        case pill(centre: CGPoint, size: CGSize, corner: CGFloat)
        case cross(centre: CGPoint, size: CGSize, arm: CGFloat)

        var centre: CGPoint {
            switch self {
            case .circle(let c, _), .pill(let c, _, _), .cross(let c, _, _): return c
            }
        }
        var boundingSize: CGSize {
            switch self {
            case .circle(_, let d):   return CGSize(width: d, height: d)
            case .pill(_, let s, _):  return s
            case .cross(_, let s, _): return s
            }
        }
    }

    /// Screen-edge margin and picture clearance, in D - so spacing grows with the buttons
    /// rather than with the display, which is the rule the shipping layout already uses.
    static let edgeMargin: CGFloat = 0.35
    static let clearance: CGFloat  = 0.35
    /// Clear space the two clusters must leave between them, in D. Non-negotiable: this
    /// is the invariant whose absence put Y on top of the d-pad.
    static let minimumClusterGap: CGFloat = 0.6
    /// The GamePad's own screen. The framed/overlay switch is decided against this.
    static let realScreenMM: CGFloat = 137.3
    /// Apple's minimum touch target.
    static let touchFloor: CGFloat = 44
    static let rakeFloor: CGFloat = 45 * .pi / 180

    var mode: Mode
    /// D, in points. The one number every position below is a multiple of.
    var unit: CGFloat
    var lifeSizeUnit: CGFloat
    var armAngle: CGFloat
    var systemPlacement: SystemPlacement
    var leftAnchor: CGPoint
    var rightAnchor: CGPoint
    var video: CGRect
    var controls: [String: Placement]
    var notes: [String]

    var lifeSizeFraction: CGFloat { unit / lifeSizeUnit }

    // MARK: The four laws

    /// - Parameters:
    ///   - container: the pad's own bounds (a GeometryReader's size).
    ///   - safeArea: the safe rectangle inside it. The shipping pad anchors to the raw
    ///     container instead, which puts the outer controls under the Dynamic Island in
    ///     landscape on every notched iPhone.
    ///   - pointsPerInch: points, not pixels, per inch - from `DeviceMetrics`. This is the
    ///     whole reason the layout can be life-size: a point is 0.166 mm on an iPhone and
    ///     0.192 mm on an iPad, so the same point size is a different physical button on
    ///     the two, and only this converts between them.
    static func resolve(container: CGSize,
                        safeArea: CGRect,
                        pointsPerInch: CGFloat,
                        userScale: CGFloat = 1.0,
                        hasExternalDisplay: Bool = false,
                        displayMode: DisplayMode = .fit) -> PadLayout {

        let G = GamePadGeometry.self
        let sx = safeArea.minX, sy = safeArea.minY
        let sw = safeArea.width, sh = safeArea.height
        let portrait = sh > sw
        var notes: [String] = []

        let lifeUnit = G.unitMM * pointsPerInch / 25.4
        let wanted = lifeUnit * userScale

        // NATIVE portrait reserves a top band for the picture and gives the clusters only
        // what is left below it, so that band has to be decided before the size law, not
        // after. FIT portrait has no reserved band - the picture floats full-bleed behind
        // the clusters, same as FIT landscape - so it costs the size law nothing.
        var video = CGRect.zero
        var availableHeight = sh
        if portrait, displayMode == .native {
            var vw = sw, vh = sw * 9 / 16
            if vh > sh * 0.62 { vh = sh * 0.62; vw = vh * 16 / 9 }
            video = CGRect(x: sx + (sw - vw) / 2, y: sy, width: vw, height: vh)
            availableHeight = sy + sh - video.maxY
        }

        // LAW 1 + 2 - size, then arrangement. The two candidates are evaluated whole
        // rather than one patched after the other: keeping +/- in their hardware slot
        // costs height but makes the clusters narrower, so height and width have to be
        // judged together or the answer depends on which was applied first.
        var armAngle = G.stickArmAngle
        var unit: CGFloat
        var hardwareSystem: Bool

        let hardwareUnit = min(wanted, G.widthFit(armAngle: armAngle, hardwareSystem: true, width: sw))
        if hardwareUnit <= availableHeight / G.verticalNeed(armAngle: armAngle, hardwareSystem: true) + 1e-9 {
            hardwareSystem = true
            unit = hardwareUnit
        } else {
            hardwareSystem = false
            unit = min(wanted,
                       availableHeight / G.verticalNeed(armAngle: armAngle, hardwareSystem: false),
                       G.widthFit(armAngle: armAngle, hardwareSystem: false, width: sw))
            if unit < touchFloor {
                // Raking buys height. It cannot buy width - it pushes the stick outboard -
                // so a width-bound pad is not helped by it and simply comes out small.
                let k = (availableHeight / touchFloor - G.bottomExtentElbow
                         - 2 * edgeMargin - G.fixedTopExtent) / G.stickArm
                armAngle = max(rakeFloor, asin(min(max(k, -1), 1)))
                unit = min(wanted,
                           availableHeight / G.verticalNeed(armAngle: armAngle, hardwareSystem: false),
                           G.widthFit(armAngle: armAngle, hardwareSystem: false, width: sw))
                notes.append(String(format: "raked to %.0f deg to fit the height",
                                    armAngle * 180 / .pi))
                if unit < touchFloor {
                    // Never forced back up to the floor. Buttons a little small are
                    // recoverable; two clusters drawn through each other are not.
                    notes.append(String(format: "%.0f pt buttons, under the 44 pt floor - the container is too small", unit))
                }
            }
        }
        if wanted > unit + 0.01 {
            notes.append(String(format: "%.0f%% of life-size to fit", 100 * unit / lifeUnit))
        }

        // LAW 3 - clusters rigid, pinned to the safe edges; the bezel is the only slack.
        let bottomExtent = hardwareSystem ? G.bottomExtentHardware : G.bottomExtentElbow
        let e = G.extents(armAngle: armAngle, hardwareSystem: hardwareSystem)
        var lx = sx + (edgeMargin + e.outboard) * unit
        var rx = sx + sw - (edgeMargin + e.outboard) * unit
        let gap0 = lx + (e.inboardL + clearance) * unit
        let gap1 = rx - (e.inboardR + clearance) * unit
        let gapWidth = max(0, gap1 - gap0)
        let gapCentreX = (gap0 + gap1) / 2

        // LAW 4 - mode. Two axes: orientation (decided already, from the container) and
        // displayMode (a plain user setting). External display always wins regardless of
        // displayMode - there is no local picture to place either way.
        var mode: Mode
        if hasExternalDisplay {
            mode = .shell
        } else if portrait {
            mode = displayMode == .fit ? .overlay : .stacked
            if mode == .stacked {
                notes.append("portrait, Native: picture along the top, clusters on the bottom corners")
            }
        } else {
            mode = displayMode == .fit ? .overlay : .framed
        }

        var bodyTop: CGFloat? = nil
        var cy: CGFloat
        if (mode == .framed || mode == .shell) && G.bodyHeight * unit <= sh {
            let top = sy + (sh - G.bodyHeight * unit) / 2
            bodyTop = top
            cy = top + G.clusterFromBodyTop * unit
        } else if mode == .framed || mode == .shell {
            let need = G.verticalNeed(armAngle: armAngle, hardwareSystem: hardwareSystem)
            cy = sy + (sh - need * unit) / 2 + (G.topExtent(armAngle: armAngle) + edgeMargin) * unit
        } else {
            cy = sy + sh - (bottomExtent + edgeMargin) * unit
        }

        switch mode {
        case .stacked:
            cy = sy + sh - (bottomExtent + edgeMargin) * unit
            lx = sx + (edgeMargin + e.outboard) * unit
            rx = sx + sw - (edgeMargin + e.outboard) * unit
        case .overlay:
            let vh = min(sh, sw * 9 / 16), vw = vh * 16 / 9
            video = CGRect(x: sx + (sw - vw) / 2, y: sy + (sh - vh) / 2, width: vw, height: vh)
        case .framed, .shell:
            let vw = min(gapWidth, (sh - 2 * clearance * unit) * 16 / 9), vh = vw * 9 / 16
            var vcy = bodyTop.map { $0 + G.screenCentreFromTop * unit } ?? (sy + sh / 2)
            vcy = min(max(vcy, sy + vh / 2 + clearance * unit), sy + sh - vh / 2 - clearance * unit)
            video = CGRect(x: gapCentreX - vw / 2, y: vcy - vh / 2, width: vw, height: vh)
        }

        // The controls.
        var c: [String: Placement] = [:]
        let armX = G.stickArm * cos(armAngle) * unit
        let armY = G.stickArm * sin(armAngle) * unit

        for (suffix, anchorX, sign) in [("L", lx, CGFloat(-1)), ("R", rx, CGFloat(1))] {
            let s = CGPoint(x: anchorX + sign * armX, y: cy - armY)
            c["stick\(suffix)"] = .circle(centre: s, diameter: G.stickBase * unit)
            c["knob\(suffix)"]  = .circle(centre: s, diameter: G.stickKnob * unit)
            c[suffix] = .pill(centre: CGPoint(x: s.x + sign * G.shoulderSpread * unit,
                                              y: s.y + G.shoulderDY * unit),
                              size: CGSize(width: G.shoulderSize.width * unit,
                                           height: G.shoulderSize.height * unit),
                              corner: G.shoulderCorner * unit)
            c["Z\(suffix)"] = .pill(centre: CGPoint(x: s.x - sign * G.shoulderSpread * unit,
                                                    y: s.y + G.shoulderDY * unit),
                                    size: CGSize(width: G.shoulderSize.width * unit,
                                                 height: G.shoulderSize.height * unit),
                                    corner: G.shoulderCorner * unit)
        }
        c["dpad"] = .cross(centre: CGPoint(x: lx, y: cy),
                           size: CGSize(width: G.dpadWidth * unit, height: G.dpadHeight * unit),
                           arm: G.dpadArm * unit)
        c["L3"] = .circle(centre: CGPoint(x: lx, y: cy), diameter: 0.706 * unit)
        c["R3"] = .circle(centre: CGPoint(x: rx, y: cy), diameter: 0.706 * unit)
        for (id, dx, dy) in [("X", CGFloat(0), -G.faceHalfY), ("Y", -G.faceHalfX, 0),
                             ("A", G.faceHalfX, 0), ("B", 0, G.faceHalfY)] {
            c[id] = .circle(centre: CGPoint(x: rx + dx * unit, y: cy + dy * unit),
                            diameter: G.faceDiameter * unit)
        }
        if hardwareSystem {
            c["plus"]  = .circle(centre: CGPoint(x: rx + G.plusFromABXY.x * unit,
                                                 y: cy + G.plusFromABXY.y * unit),
                                 diameter: G.systemDiameter * unit)
            c["minus"] = .circle(centre: CGPoint(x: rx + G.minusFromABXY.x * unit,
                                                 y: cy + G.minusFromABXY.y * unit),
                                 diameter: G.systemDiameter * unit)
        } else {
            c["plus"]  = .circle(centre: CGPoint(x: rx - G.systemElbow.x * unit,
                                                 y: cy + G.systemElbow.y * unit),
                                 diameter: G.systemDiameter * unit)
            c["minus"] = .circle(centre: CGPoint(x: lx + G.systemElbow.x * unit,
                                                 y: cy + G.systemElbow.y * unit),
                                 diameter: G.systemDiameter * unit)
            notes.append("+/- moved to the elbow: no room for their real place under A/B/X/Y")
        }

        // The menu rail. HOME keeps its hardware place where it fits, but the framed
        // picture is taller than the hardware's own LCD whenever the gap between the
        // clusters is wider than the GamePad's bezel, so it has to be pushed clear of the
        // picture rather than trusted to the hardware offset. Where nothing clears, HOME
        // joins TV and POWER in the pause menu instead of being drawn on top of something.
        let hr = G.homeDiameter / 2 * unit
        func collides(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Bool {
            for (id, p) in c where !id.hasPrefix("knob") {
                let s = p.boundingSize
                if abs(x - p.centre.x) < (r + s.width / 2) - 0.5,
                   abs(y - p.centre.y) < (r + s.height / 2) - 0.5 { return true }
            }
            return false
        }
        var placed = false
        if let top = bodyTop, mode == .framed || mode == .shell {
            let hy = max(top + G.homeFromBodyTop * unit, video.maxY + clearance * unit + hr)
            if hy + hr <= sy + sh - edgeMargin * unit, !collides(gapCentreX, hy, hr) {
                c["HOME"]  = .circle(centre: CGPoint(x: gapCentreX, y: hy),
                                     diameter: G.homeDiameter * unit)
                c["TV"]    = .circle(centre: CGPoint(x: gapCentreX + G.tvFromHome * unit, y: hy),
                                     diameter: G.menuDiameter * unit)
                c["POWER"] = .circle(centre: CGPoint(x: gapCentreX + G.powerFromHome * unit, y: hy),
                                     diameter: G.menuDiameter * unit)
                placed = true
            }
        }
        if !placed {
            let hx = mode == .overlay ? sx + sw / 2 : gapCentreX
            let hy = sy + sh - (edgeMargin + G.homeDiameter / 2) * unit
            if !collides(hx, hy, hr) {
                c["HOME"] = .circle(centre: CGPoint(x: hx, y: hy), diameter: G.homeDiameter * unit)
            } else {
                notes.append("HOME joins TV/POWER in the pause menu: nothing on the pad clears")
            }
            notes.append("TV/POWER belong to the pause menu at this size, not to the pad")
        }

        return PadLayout(mode: mode, unit: unit, lifeSizeUnit: lifeUnit, armAngle: armAngle,
                         systemPlacement: hardwareSystem ? .hardware : .elbow,
                         leftAnchor: CGPoint(x: lx, y: cy), rightAnchor: CGPoint(x: rx, y: cy),
                         video: video, controls: c, notes: notes)
    }

    // MARK: Hit testing

    /// Which d-pad directions a touch is pressing, eight-way, diagonals pressing both.
    ///
    /// The cross is one shape, so it is hit-tested by angle rather than by four separate
    /// button rects: four rects meeting at a corner have no diagonal, and a Wii U d-pad
    /// very much has diagonals. The dead centre reports nothing, which is what leaves the
    /// middle free to be L3's tap target.
    static func dpadDirections(at point: CGPoint, centre: CGPoint, size: CGSize) -> Set<String> {
        let dx = (point.x - centre.x) / (size.width / 2)
        let dy = (point.y - centre.y) / (size.height / 2)
        guard dx * dx + dy * dy > 0.18 * 0.18 else { return [] }
        let sector = Int(((atan2(dy, dx) + 2 * .pi + .pi / 8)
            .truncatingRemainder(dividingBy: 2 * .pi)) / (.pi / 4))
        switch sector {
        case 0: return ["right"]
        case 1: return ["right", "down"]
        case 2: return ["down"]
        case 3: return ["down", "left"]
        case 4: return ["left"]
        case 5: return ["left", "up"]
        case 6: return ["up"]
        default: return ["up", "right"]
        }
    }

    /// The touch radius for a round control: never below 22 pt, never past half the way to
    /// its nearest neighbour, so enlarging a target can never steal a neighbour's touches.
    static func hitRadius(visualDiameter d: CGFloat, nearestNeighbourDistance n: CGFloat) -> CGFloat {
        min(max(d / 2, 22), n / 2)
    }
}

// MARK: - Working out how big the screen physically is

/// Life-size means nothing without points-per-inch, and UIKit does not expose it:
/// `UIScreen.scale` is points per *pixel*, and there is no API for pixels per inch. So it
/// has to be worked out, and it has to keep working on a device that did not exist when
/// this was written - otherwise the first unknown iPad renders a pad 24% wrong with no
/// error anywhere.
///
/// Four sources, most authoritative first. The pure function below is deliberately free
/// of UIKit so it can be tested off-device; `current()` is the thin part that reads the
/// machine.
///
/// 1. **calibrated** - the user measured it against a bank card. Beats everything,
///    because it was measured on the actual glass.
/// 2. **model** - an exact `hw.machine` match. Authoritative for every device shipped so far.
/// 3. **panel** - the native pixel resolution matches a panel we know. Catches a new
///    model that reuses an existing display, which is the common case for a mid-cycle
///    refresh.
/// 4. **derived** - reasoned from idiom, native scale and pixel count. Apple has only ever
///    shipped a handful of native densities, and they separate cleanly. This is a guess,
///    it says so, and it is the point at which offering calibration is worthwhile.
enum DeviceMetrics {

    enum Source: String { case calibrated, model, panel, derived }

    struct Measurement {
        let pointsPerInch: CGFloat
        let source: Source
        let identifier: String
        /// One line for the launch log, so a wrong pad is diagnosable from a log alone.
        let detail: String
    }

    static let calibrationKey = "muffin.controls.pointsPerInch"
    /// ISO/IEC 7810 ID-1: every bank card, driving licence and library card on earth is
    /// 85.60 mm wide, to a tolerance far tighter than a thumb cares about. That makes one
    /// reliably available ruler in the user's pocket.
    static let referenceCardWidthMM: CGFloat = 85.60

    /// Native densities Apple has actually shipped. Everything reduces to one of these.
    private static let padStandard: CGFloat = 264      // every iPad but the mini
    private static let padMini: CGFloat = 326          // iPad mini, and the old 2x phones
    private static let phoneOLED: CGFloat = 460        // 458 on the older ones; a 0.4% difference
    private static let phoneMini: CGFloat = 476        // 12 mini and 13 mini only
    private static let phoneLCD: CGFloat = 326

    private static let modelTable: [String: CGFloat] = [
        // The target device and its siblings.
        "iPad8,11": padStandard, "iPad8,12": padStandard,   // iPad Pro 12.9 in, 2020 (A12Z)
        "iPad8,9":  padStandard, "iPad8,10": padStandard,   // iPad Pro 11 in, 2020 (A12Z)
        // iPad mini is the only iPad that is not 264.
        "iPad14,1": padMini, "iPad14,2": padMini,           // mini 6
        "iPad16,1": padMini, "iPad16,2": padMini,           // mini 7
        "iPad5,1": padMini,  "iPad5,2": padMini,            // mini 4
        // The 3x phones that are not 460.
        "iPhone13,1": phoneMini, "iPhone14,4": phoneMini,   // 12 mini, 13 mini
        // The 2x phones.
        "iPhone14,6": phoneLCD, "iPhone12,8": phoneLCD,     // SE 3, SE 2
        "iPhone11,8": phoneLCD, "iPhone12,1": phoneLCD,     // XR, 11
    ]

    /// Keyed on native pixels, long side first, so orientation cannot change the answer.
    private static let panelTable: [String: CGFloat] = [
        "2732x2048": padStandard,   // 12.9 in iPad Pro, every generation
        "2388x1668": padStandard,   // 11 in iPad Pro
        "2420x1668": padStandard,   // 11 in iPad Pro M4
        "2752x2064": padStandard,   // 13 in iPad Pro M4
        "2360x1640": padStandard,   // iPad Air 11 in, iPad 10th/11th
        "2160x1620": padStandard,   // iPad 10.2 in
        "2266x1488": padMini,       // iPad mini 6 and 7
        "2796x1290": phoneOLED, "2868x1320": phoneOLED, "2778x1284": phoneOLED,
        "2556x1179": phoneOLED, "2622x1206": phoneOLED, "2532x1170": phoneOLED,
        "2436x1125": phoneOLED, "2688x1242": phoneOLED,
        "2340x1080": phoneMini,
        "1792x828": phoneLCD, "1334x750": phoneLCD, "1920x1080": phoneLCD,
    ]

    /// The whole decision, with nothing platform-specific in it.
    static func measurement(identifier: String,
                            nativePixels: CGSize,
                            scale: CGFloat,
                            isPad: Bool,
                            calibrated: CGFloat?) -> Measurement {
        if let c = calibrated, isPlausible(c) {
            return Measurement(pointsPerInch: c, source: .calibrated, identifier: identifier,
                               detail: String(format: "measured against a bank card: %.1f pt/in", c))
        }
        let safeScale = scale > 0 ? scale : 2
        if let native = modelTable[identifier] {
            return Measurement(pointsPerInch: native / safeScale, source: .model,
                               identifier: identifier,
                               detail: String(format: "%@ is a known model: %.0f ppi at %.0fx", identifier, native, safeScale))
        }
        let long = max(nativePixels.width, nativePixels.height)
        let short = min(nativePixels.width, nativePixels.height)
        let key = "\(Int(long))x\(Int(short))"
        if let native = panelTable[key] {
            return Measurement(pointsPerInch: native / safeScale, source: .panel,
                               identifier: identifier,
                               detail: "\(identifier) is unknown, but its \(key) panel is: \(Int(native)) ppi")
        }
        // Derived. iPads are 264 unless they are a mini, and a mini is the only iPad whose
        // short side comes in under 1536 px. Phones at 3x are 460 unless they are 1080 px
        // wide, which only the minis are; phones at 2x are 326.
        let native: CGFloat
        let why: String
        if isPad {
            if short <= 1536 { native = padMini; why = "iPad, short side \(Int(short)) px - mini class" }
            else { native = padStandard; why = "iPad, short side \(Int(short)) px - standard class" }
        } else if safeScale >= 3 {
            if short <= 1080 { native = phoneMini; why = "3x phone, \(Int(short)) px wide - mini class" }
            else { native = phoneOLED; why = "3x phone, \(Int(short)) px wide" }
        } else {
            native = phoneLCD; why = "2x phone"
        }
        return Measurement(pointsPerInch: native / safeScale, source: .derived, identifier: identifier,
                           detail: "\(identifier) unrecognised - derived from \(why); offer calibration")
    }

    /// Sanity bounds. Every Apple display in points lands between 132 and 163; anything
    /// far outside that is a bad calibration rather than an exotic screen, and taking it
    /// would be worse than ignoring it.
    static func isPlausible(_ pointsPerInch: CGFloat) -> Bool { pointsPerInch > 90 && pointsPerInch < 240 }

    /// Turn a card the user has sized against a real one into points-per-inch.
    static func calibration(fromCardWidthInPoints width: CGFloat) -> CGFloat {
        width / (referenceCardWidthMM / 25.4)
    }
}

#if canImport(UIKit)
import UIKit

extension DeviceMetrics {
    /// Read the machine. Call once at launch, log `detail`, and keep the value.
    static func current(defaults: UserDefaults = .standard) -> Measurement {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let identifier = String(cString: machine)

        let screen = UIScreen.main
        let stored = defaults.object(forKey: calibrationKey) as? Double
        return measurement(identifier: identifier,
                           nativePixels: screen.nativeBounds.size,
                           scale: screen.nativeScale,
                           isPad: UIDevice.current.userInterfaceIdiom == .pad,
                           calibrated: stored.map(CGFloat.init))
    }

    static func storeCalibration(cardWidthInPoints width: CGFloat, defaults: UserDefaults = .standard) {
        let ppi = calibration(fromCardWidthInPoints: width)
        guard isPlausible(ppi) else { return }
        defaults.set(Double(ppi), forKey: calibrationKey)
    }

    static func clearCalibration(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: calibrationKey)
    }
}

/// The calibration itself, for when `measurement(...).source == .derived` - an unknown
/// device where the derived answer is a reasoned guess rather than a fact.
///
/// One draggable rectangle and one instruction. The user holds any bank card against the
/// screen and sizes the rectangle to match it; that is a direct physical measurement of
/// the display, and it is exact on hardware nobody has seen yet.
struct PadCalibrationView: View {
    var onDone: (CGFloat) -> Void
    @State private var width: CGFloat = 320

    var body: some View {
        VStack(spacing: 24) {
            Text("Hold a bank card against the screen")
                .font(.headline)
            Text("Drag until the outline matches the card exactly. Any card will do - they are all the same size.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)

            RoundedRectangle(cornerRadius: width * 0.0374)      // the card's own corner radius
                .strokeBorder(.tint, lineWidth: 2)
                .frame(width: width, height: width / 1.5858)    // ID-1 is 85.60 x 53.98 mm
                .gesture(DragGesture()
                    .onChanged { width = max(120, min(700, width + $0.translation.width / 12)) })

            Slider(value: $width, in: 120...700)
                .frame(maxWidth: 420)
                .accessibilityLabel("Card width")

            Button("That matches") { onDone(width) }
                .buttonStyle(.borderedProminent)
                .disabled(!DeviceMetrics.isPlausible(DeviceMetrics.calibration(fromCardWidthInPoints: width)))
        }
        .padding()
    }
}
#endif

//  ---------------------------------------------------------------------------------
//  WIRING
//
//  1. Move this file to src/ios/App/. project.yml pulls that folder in as a group, so
//     nothing else needs editing to compile it.
//
//  2. Once at launch, and again on a size change:
//
//         let metrics = DeviceMetrics.current()
//         logger.info("pad metrics: \(metrics.detail)")
//
//     Keep `metrics.pointsPerInch`. If `metrics.source == .derived`, the device is one
//     nobody has taught this app about yet - the layout will still be close, and
//     PadCalibrationView will make it exact if the user wants to spend ten seconds on it.
//
//  3. In ControllerPad.body, replace
//         let unit = ControllerGeometry.automaticDiameter(in: proxy.size) * CGFloat(userScale)
//     with
//         let layout = PadLayout.resolve(container: proxy.size,
//                                        safeArea: proxy.frame(in: .local)
//                                            .inset(by: proxy.safeAreaInsets),
//                                        pointsPerInch: metrics.pointsPerInch,
//                                        userScale: CGFloat(userScale))
//     and position each control at layout.controls[id]!.centre. The user's drag offsets
//     and ControllerCustomLayout's per-element overrides apply on top exactly as they do
//     now - this only changes where "unmoved" is.
//
//  4. The d-pad is a .cross, not four circles. Hit-test it with
//     PadLayout.dpadDirections(at:centre:size:), which is eight-way and presses two ids
//     on a diagonal. Four separate rects meeting at a corner have no diagonals at all.
