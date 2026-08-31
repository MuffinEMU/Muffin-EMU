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
        /// Picture full-bleed, controls floating over its outer thirds. Every iPhone, and
        /// the iPad mini.
        case overlay
        /// Picture on an external display; the iPad is nothing but a GamePad.
        case shell
        /// Portrait: picture along the top, both clusters on the bottom corners.
        case stacked
    }

    enum SystemPlacement: String { case hardware, elbow }

    enum Placement {
        case circle(centre: CGPoint, diameter: CGFloat)
        case pill(centre: CGPoint, size: CGSize, corner: CGFloat)
        case cross(centre: CGPoint, size: CGSize, arm: CGFloat)

        var centre: CGPoint {
            switch self {
            case .circle(let c, _), .pill(let c, _, _), .cross(let c, _, _): return c
            }
        }
    }

    /// Screen-edge margin and video clearance, in D - so spacing grows with the buttons
    /// rather than with the display, which is the rule the shipping layout already uses.
    static let edgeMargin: CGFloat = 0.35
    static let clearance: CGFloat  = 0.35
    /// The GamePad's own screen. The framed/overlay switch is decided against this.
    static let realScreenMM: CGFloat = 137.3
    /// Apple's minimum touch target. The floor no amount of shrinking may cross.
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

    /// How close to the real hardware this came out, 1.0 being life-size.
    var lifeSizeFraction: CGFloat { unit / lifeSizeUnit }

    // MARK: The four laws

    /// - Parameters:
    ///   - container: the pad's own bounds (a GeometryReader's size).
    ///   - safeArea: the safe rectangle inside it. The shipping pad anchors to the raw
    ///     container instead, which puts the outer controls under the Dynamic Island in
    ///     landscape on every notched iPhone.
    ///   - pointsPerInch: points, not pixels, per inch - `DeviceMetrics.pointsPerInch`.
    ///     This is the whole reason the layout can be life-size: a point is 0.166 mm on
    ///     an iPhone and 0.192 mm on an iPad, so the same point size is a different
    ///     physical button on the two, and only this converts between them.
    static func resolve(container: CGSize,
                        safeArea: CGRect,
                        pointsPerInch: CGFloat,
                        userScale: CGFloat = 1.0,
                        hasExternalDisplay: Bool = false) -> PadLayout {

        let G = GamePadGeometry.self
        let sx = safeArea.minX, sy = safeArea.minY
        let sw = safeArea.width, sh = safeArea.height
        let portrait = sh > sw
        var notes: [String] = []

        // LAW 1 - size. Life-size unless the height cannot hold it, and the hardware's
        // own arm angle is preserved in preference to keeping the buttons big: bending
        // the geometry is a worse loss than 15% off the button, because the geometry is
        // the part a thumb remembers.
        let lifeUnit = G.unitMM * pointsPerInch / 25.4
        let wanted = lifeUnit * userScale
        var armAngle = G.stickArmAngle
        var unit: CGFloat
        var hardwareSystem: Bool

        if wanted <= sh / G.verticalNeed(armAngle: armAngle, hardwareSystem: true) {
            hardwareSystem = true
            unit = wanted
        } else {
            hardwareSystem = false
            unit = min(wanted, sh / G.verticalNeed(armAngle: armAngle, hardwareSystem: false))
            if unit < touchFloor {
                // LAW 2 - rake, and only now. Rotating the stick arm outboard buys height
                // at no cost to the distance between the stick and the cluster, which is
                // the relationship a thumb actually learns. It is a last resort because
                // it is the only law here that changes the shape of the pad.
                let need = (sh / touchFloor - G.bottomExtentElbow - 2 * edgeMargin - G.fixedTopExtent)
                    / G.stickArm
                armAngle = max(rakeFloor, asin(min(max(need, -1), 1)))
                unit = min(wanted, sh / G.verticalNeed(armAngle: armAngle, hardwareSystem: false))
                notes.append(String(format: "raked to %.0f deg to fit the height",
                                    armAngle * 180 / .pi))
                if unit < touchFloor {
                    unit = touchFloor
                    notes.append("below the 44 pt floor even raked - the pad will overhang")
                }
            }
        }
        if wanted > unit + 0.01 {
            notes.append(String(format: "%.0f%% of life-size; the height could not hold more",
                                100 * unit / lifeUnit))
        }

        // LAW 3 - placement. Clusters are rigid and pinned to the safe edges; the bezel
        // between them is the only thing that stretches. Nothing is ever squeezed.
        let bottomExtent = hardwareSystem ? G.bottomExtentHardware : G.bottomExtentElbow
        let inboardL = hardwareSystem ? G.dpadWidth / 2 : G.systemElbow.x + G.systemDiameter / 2
        let inboardR = max(G.faceHalfX + 0.5, inboardL)
        let outboard = G.outboardExtent(armAngle: armAngle)

        var lx = sx + (edgeMargin + outboard) * unit
        var rx = sx + sw - (edgeMargin + outboard) * unit
        let gap0 = lx + (inboardL + clearance) * unit
        let gap1 = rx - (inboardR + clearance) * unit
        let gapWidth = max(0, gap1 - gap0)
        let gapCentreX = (gap0 + gap1) / 2

        // LAW 4 - mode.
        let framedWidth = min(gapWidth, (sh - 2 * clearance * unit) * 16 / 9)
        let framedMM = framedWidth / pointsPerInch * 25.4
        var mode: Mode = hasExternalDisplay ? .shell : (framedMM >= realScreenMM ? .framed : .overlay)
        if portrait { mode = .stacked }

        // Vertical placement. When the real bezel fits, use it, so the pad sits where the
        // hardware puts it rather than wherever the arithmetic lands.
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

        // The picture.
        var video: CGRect
        switch mode {
        case .stacked:
            var vw = sw, vh = sw * 9 / 16
            if vh > sh * 0.62 { vh = sh * 0.62; vw = vh * 16 / 9 }
            video = CGRect(x: sx + (sw - vw) / 2, y: sy, width: vw, height: vh)
            let band = sy + sh - video.maxY
            // Both clamps matter. The height one alone lets the two clusters size
            // themselves past the width they have to share, which on a Slide Over pane
            // puts them straight through each other.
            let clustersWide = (outboard + inboardL) + (outboard + inboardR)
            unit = min(unit,
                       band / G.verticalNeed(armAngle: armAngle, hardwareSystem: hardwareSystem),
                       sw / (clustersWide + 0.6))
            let out = G.outboardExtent(armAngle: armAngle)
            lx = sx + (edgeMargin + out) * unit
            rx = sx + sw - (edgeMargin + out) * unit
            cy = sy + sh - (bottomExtent + edgeMargin) * unit
            notes.append("portrait: picture along the top, clusters on the bottom corners")
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
        // clusters is wider than the GamePad's bezel - so it has to be pushed clear of
        // the picture rather than trusted to the hardware offset. Where nothing clears,
        // HOME joins TV and POWER in the pause menu instead of being drawn on top of
        // something: a button you cannot tell apart from the one under it is worse than
        // a button that is somewhere else.
        let hr = G.homeDiameter / 2 * unit
        func collides(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Bool {
            for (id, p) in c where !id.hasPrefix("knob") {
                var w: CGFloat, h: CGFloat
                switch p {
                case .circle(_, let d):     w = d; h = d
                case .pill(_, let s, _):    w = s.width; h = s.height
                case .cross(_, let s, _):   w = s.width; h = s.height
                }
                if abs(x - p.centre.x) < (r + w / 2) - 0.5,
                   abs(y - p.centre.y) < (r + h / 2) - 0.5 { return true }
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

    /// The touch radius for a round control: never below 22 pt, never past half the way
    /// to its nearest neighbour, so enlarging a target can never steal a neighbour's
    /// touches. A/B/X/Y are 1.35 D apart centre to centre, so at life-size on an iPhone
    /// they get the full 22 pt and still do not overlap.
    static func hitRadius(visualDiameter d: CGFloat, nearestNeighbourDistance n: CGFloat) -> CGFloat {
        min(max(d / 2, 22), n / 2)
    }
}

// MARK: - Points per inch

#if canImport(UIKit)
import UIKit

/// Points per inch for the current device, which UIKit does not expose.
///
/// It has to be a table: `UIScreen.scale` gives points per pixel, not pixels per inch,
/// and there is no API for the second. The values are the only three that matter -
/// 132 for every iPad but the mini, 163 for the mini and the older iPhones, 153.33 for
/// every iPhone since the X. An unknown model falls back by idiom, which is right for
/// every device Apple has shipped so far and cannot be worse than a guess.
enum DeviceMetrics {
    static var pointsPerInch: CGFloat {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let id = String(cString: machine)

        if id.hasPrefix("iPad") {
            // iPad mini 6 and 7 are iPad14,1 / iPad14,2 and iPad16,1 / iPad16,2.
            if ["iPad14,1", "iPad14,2", "iPad16,1", "iPad16,2"].contains(id) { return 163 }
            return 132
        }
        if id.hasPrefix("iPhone") {
            // 476 ppi at 3x - the 12 mini and 13 mini only.
            if ["iPhone13,1", "iPhone14,4"].contains(id) { return 158.67 }
            // 326 ppi at 2x - SE and the last of the 4.7 in bodies.
            if ["iPhone12,8", "iPhone14,6", "iPhone8,4", "iPhone9,1", "iPhone9,3",
                "iPhone10,1", "iPhone10,4"].contains(id) { return 163 }
            return 153.33
        }
        #if targetEnvironment(simulator)
        return UIDevice.current.userInterfaceIdiom == .pad ? 132 : 153.33
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? 132 : 153.33
        #endif
    }
}
#endif

//  ---------------------------------------------------------------------------------
//  WIRING
//
//  1. Move this file to src/ios/App/. project.yml pulls that folder in as a group, so
//     nothing else needs editing to compile it.
//
//  2. In ControllerPad.body, replace
//         let unit = ControllerGeometry.automaticDiameter(in: proxy.size) * CGFloat(userScale)
//     with
//         let layout = PadLayout.resolve(container: proxy.size,
//                                        safeArea: proxy.frame(in: .local)
//                                            .inset(by: proxy.safeAreaInsets),
//                                        pointsPerInch: DeviceMetrics.pointsPerInch,
//                                        userScale: CGFloat(userScale))
//     and position each control at layout.controls[id]!.centre. The user's drag offsets
//     and ControllerCustomLayout's per-element overrides apply on top exactly as they do
//     now - this only changes where "unmoved" is.
//
//  3. ControllerLayoutSettings.reset() should stay as it is. Everything here is a
//     starting point; the drag handles remain the last word.
//
//  4. Two visible changes to expect, both of them the hardware being right:
//     the d-pad becomes a cross rather than four circles, and + and - are both on the
//     right on iPads. Worth a settings toggle if either turns out to be unpopular.
