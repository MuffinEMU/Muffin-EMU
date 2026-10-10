// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import UIKit

/// Keys and defaults for the on-screen pad's adjustable values, shared by the settings
/// sheet, the emulator view and the pad.
///
/// Offsets are stored in points, not layout units, so a cluster doesn't move when the
/// size slider changes.
enum ControllerLayoutSettings {
    static let scaleKey = "muffin.controls.scale"
    static let opacityKey = "muffin.controls.opacity"
    static let leftOffsetXKey = "muffin.controls.left.dx"
    static let leftOffsetYKey = "muffin.controls.left.dy"
    static let rightOffsetXKey = "muffin.controls.right.dx"
    static let rightOffsetYKey = "muffin.controls.right.dy"
    /// Whether the analog sticks are shown alongside the d-pad and face buttons. Off by default.
    static let joystickKey = "muffin.controls.joystick"
    /// Whether L/ZL/minus and R/ZR/plus are anchored to the analog sticks instead. Only
    /// applies while `joystickKey` is on. Off by default.
    static let comfortControlsKey = "muffin.pad.comfortControls"
    static let defaultComfortControls = false
    /// Where the camera stick has been dragged to (its own cluster, stored separately).
    static let rightStickOffsetXKey = "muffin.controls.rstick.dx"
    static let rightStickOffsetYKey = "muffin.controls.rstick.dy"
    /// Same, for the left stick.
    static let leftStickOffsetXKey = "muffin.controls.lstick.dx"
    static let leftStickOffsetYKey = "muffin.controls.lstick.dy"
    /// Stick feel settings: deadzone, response curve and gate. Not reset by `reset()`.
    static let deadzoneKey = "muffin.controls.stick.deadzone"
    static let stickCurveKey = "muffin.controls.stick.curve"
    static let stickGateKey = "muffin.controls.stick.gate"

    /// Grouped (false): dragging a cluster's dashed box moves the whole cluster.
    /// Individual (true): each button has its own drag and pinch, and the cluster handle
    /// is not attached.
    static let individualEditModeKey = "muffin.controls.individualEditMode"
    static let defaultIndividualEditMode = false

    /// Whether a press fires a light haptic tap. On by default.
    static let hapticsKey = "muffin.pad.haptics"
    static let defaultHaptics = true

    /// Hide the on-screen pad while a physical controller is connected, and bring it back when the
    /// last one goes. Off by default. Not reset by `reset()`: it is a preference, not a layout.
    static let autoHideWithControllerKey = "muffin.controls.autoHideWithController"
    static let defaultAutoHideWithController = false

    static let defaultJoystick = false

    /// Fraction of full travel that reads as centred.
    ///
    /// Small, because the knob goes where the finger is and glass has no drift to filter.
    static let defaultDeadzone: Double = 0.06
    static let minDeadzone: Double = 0.0
    static let maxDeadzone: Double = 0.30

    /// The exponent applied to the stick's magnitude after the deadzone. 1.0 is linear;
    /// higher values make small movements gentler. 0 and 1 map to themselves.
    static let defaultStickCurve: Double = 1.0
    static let minStickCurve: Double = 1.0
    static let maxStickCurve: Double = 2.5

    /// The gate the stick reaches by default (octagonal, like the hardware). Stored as its
    /// raw string so the key survives a case being added or reordered.
    static let defaultStickGate = ControllerGeometry.StickGate.octagon
    static let defaultStickGateRaw = ControllerGeometry.StickGate.octagon.rawValue
    static let defaultScale: Double = 1.0
    static let defaultOpacity: Double = 0.85
    static let minScale: Double = 0.6
    static let maxScale: Double = 1.6

    /// How far each stick moves sideways from its starting place, in button widths, so it
    /// follows the size slider: positive toward its screen edge, negative toward the
    /// middle. A hand-size setting. The TouchLab styles with fixed sticks (Zone, Adaptive)
    /// read the same key.
    static let stickSpacingKey = "muffin.controls.stickSpacing"
    static let defaultStickSpacing: Double = 0
    static let minStickSpacing: Double = -3.0
    static let maxStickSpacing: Double = 1.5
    /// Quarter-button steps, so the slider can land back on exactly zero.
    static let stickSpacingStep: Double = 0.25

    /// The readout beside the stick-spacing slider.
    static func stickSpacingLabel(_ value: Double) -> String {
        abs(value) < 0.01 ? "default" : (value < 0 ? "closer" : "wider")
    }

    /// How far the whole shoulder cluster (L, R, ZL, ZR) moves up or down, in button widths
    /// so it follows the size slider: positive is down, negative is up, zero is where the
    /// layout puts them. A hand-size setting, limited at draw time to the room the
    /// device has (see `shoulderRange`).
    /// MuffinEMU's own pad and the TouchLab styles with fixed shoulders (Zone, Adaptive) read
    /// the same key. Those TouchLab styles start with the shoulders against the top edge, so
    /// for them only the downward half does anything.
    static let shoulderOffsetKey = "muffin.controls.shoulderOffset"
    static let defaultShoulderOffset: Double = 0
    static let minShoulderOffset: Double = -4.0
    static let maxShoulderOffset: Double = 1.5
    /// Twentieths of a button, so the slider lands back on exactly zero and every saved quarter-button
    /// value (the old steps) is on the grid.
    static let shoulderOffsetStep: Double = 0.05

    /// The same setting while the pad is taller than it is wide (an iPad held upright). The
    /// landscape value is on `shoulderOffsetKey` unchanged. Until this key has been written,
    /// upright reads that shared value too, exactly as it did before the two were split.
    static let shoulderOffsetPortraitKey = "muffin.controls.shoulderOffset.portrait"

    /// Whether a container is taller than it is wide.
    static func isUpright(_ size: CGSize) -> Bool { size.height > size.width }

    /// How far the shoulders can move in each direction on this container, in button widths:
    /// the limits the pad applies when it draws them (the top edge, and just above the d-pad /
    /// stick in the same half), taken at the pad's resting place and size. Never narrower than
    /// the range the slider and the clamp have always had, so every saved value draws where
    /// it always did and only values beyond the old limits are new. Falls back to the old range
    /// whenever anything about the container or the maths is not a usable number.
    static func shoulderRange(in size: CGSize) -> ClosedRange<Double> {
        let fallback = minShoulderOffset...maxShoulderOffset
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return fallback }
        let defaults = UserDefaults.standard
        let scale = defaults.object(forKey: scaleKey) as? Double ?? defaultScale
        guard scale.isFinite else { return fallback }
        let phoneUpright = UIDevice.current.userInterfaceIdiom == .phone && isUpright(size)
        let unit = phoneUpright
            ? ControllerGeometry.Portrait.diameter(in: size, joystick: defaults.bool(forKey: joystickKey)) * CGFloat(min(scale, 1))
            : ControllerGeometry.automaticDiameter(in: size) * CGFloat(scale)
        guard unit.isFinite, unit > 0 else { return fallback }
        let fromBottom = phoneUpright ? ControllerGeometry.Portrait.centreFromBottom : ControllerGeometry.centreFromBottom
        let controls = phoneUpright ? ControllerGeometry.Portrait.cluster(ControllerGeometry.leftCluster) : ControllerGeometry.leftCluster
        let wide = -1000.0...1000.0
        func reach(_ request: Double) -> Double {
            Double(ControllerGeometry.shoulderShift(offset: request, centreY: size.height - fromBottom * unit,
                                                    containerHeight: size.height, unit: unit,
                                                    controls: controls, range: wide))
        }
        let upReach = reach(-1000), downReach = reach(1000)
        guard upReach.isFinite, downReach.isFinite else { return fallback }
        let up = (upReach / shoulderOffsetStep).rounded(.up) * shoulderOffsetStep
        let down = (downReach / shoulderOffsetStep).rounded(.down) * shoulderOffsetStep
        guard up.isFinite, down.isFinite else { return fallback }
        return min(up, minShoulderOffset)...max(down, maxShoulderOffset)
    }

    /// The slider's range for a container this size. Always contains the range it had before.
    static func shoulderOffsetRange(touchLab: Bool, in size: CGSize) -> ClosedRange<Double> {
        if touchLab { return defaultShoulderOffset...TouchLabSettings.maxShoulderDrop(in: size) }
        return shoulderRange(in: size)
    }

    /// The slider's range: the TouchLab styles can only move the shoulders down from the
    /// top edge, so their slider starts at the default instead of offering a dead half.
    static func shoulderOffsetRange(touchLab: Bool) -> ClosedRange<Double> {
        (touchLab ? defaultShoulderOffset : minShoulderOffset)...maxShoulderOffset
    }

    /// The readout beside the shoulder slider.
    static func shoulderOffsetLabel(_ value: Double) -> String {
        abs(value) < 0.01 ? "default" : (value < 0 ? "higher" : "lower")
    }

    /// Every device gets the shoulder slider.
    static var supportsShoulderOffset: Bool { true }

    /// An iPhone keeps its own copies of the shoulder setting (below), so a value that arrives
    /// some other way (an iCloud-synced default, a backup restored from an iPad) still can't
    /// move an iPhone's shoulders: only a value set on that phone is ever read there.
    static let shoulderOffsetPhoneKey = "muffin.controls.shoulderOffset.phone"
    static let shoulderOffsetPhonePortraitKey = "muffin.controls.shoulderOffset.phone.portrait"
    static var usesPadShoulderKeys: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// The key a half's saved move is stored under while the phone is held upright. Separate
    /// from the landscape one: the two layouts have different room, so a drag made in one
    /// would land somewhere meaningless in the other.
    static func portraitKey(_ key: String) -> String { key + ".portrait" }

    /// Puts every adjustment back to the measured layout by removing the keys, so each
    /// `@AppStorage` falls back to its own declared default. `joystickKey` is not reset:
    /// that is the control scheme, not the layout.
    static func reset() {
        let defaults = UserDefaults.standard
        for key in [scaleKey, opacityKey, stickSpacingKey, shoulderOffsetKey, shoulderOffsetPhoneKey, rightStickOffsetXKey, rightStickOffsetYKey,
                    leftStickOffsetXKey, leftStickOffsetYKey,
                    leftOffsetXKey, leftOffsetYKey,
                    rightOffsetXKey, rightOffsetYKey] {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: portraitKey(key))
        }
        // Per-element placement is layout too.
        ControllerCustomLayout.shared.resetAll()
    }
}

/// The on-screen pad's arrangement, measured from a reference photo of the real GamePad.
///
/// Measured button centres (face-button diameter 59.5 px):
///
///     ZL(126,175)   L(245.5,175)            R(833.5,175)   ZR(953.5,175)
///        up(186,273.5)   -(326,282)           +(753,282)     X(893.5,273.5)
///     left(112,342.5) o(186,343) right(259.5,342.5)
///                                          Y(819.5,342.5) o(894,343) A(967.5,342.5)
///        down(186,411.5)                                    B(893.5,411.5)
///
/// The right-hand half is an exact mirror of the left about x = 540, so only one half is
/// written out below and the other is that one with x negated. Face buttons are
/// X-top / Y-left / A-right / B-bottom, and the d-pad is a diamond of circles.
///
/// Every number is in units of one face-button diameter, so changing the unit scales the
/// whole arrangement.
enum ControllerGeometry {
    /// Small grey centre circle, 42/59.5.
    static let stickDiameter: CGFloat = 0.706
    /// Plus and minus, 46/59.5.
    static let systemDiameter: CGFloat = 0.773
    /// Shoulders are rounded rects, not circles: 68.5 x 52, over 59.5.
    static let shoulderSize = CGSize(width: 1.151, height: 0.874)
    static let shoulderCornerRadius: CGFloat = 0.235

    /// Where the cluster's centre dot sits when nothing has been dragged: 186 px in from
    /// the near edge and 155 px up from the bottom, both over 59.5. Margins in units of
    /// the button size rather than fractions of the screen, so spacing grows with the
    /// buttons instead of with the display.
    static let centreFromNearEdge: CGFloat = 3.126
    static let centreFromBottom: CGFloat = 2.605

    /// Picks the face-button diameter, in points, for a container of this size.
    ///
    /// The screenshot is a phone, where the cluster covers 59% of the screen height.
    /// Holding that fraction on a 1024-point iPad would ask for 600 points of buttons, so
    /// the proportion is not what carries across form factors - the button size is. This
    /// tracks the short side (the one that changes least between a phone and a tablet in
    /// landscape) and clamps it into a range that stays thumb-sized on both ends.
    static func automaticDiameter(in size: CGSize) -> CGFloat {
        let shortSide = min(size.width, size.height)
        return min(max(shortSide * 0.115, 46), 72)
    }

    enum Style: Equatable {
        case dpad       // the skin's d-pad colour
        case face       // the skin's per-letter A/B/X/Y colour
        case shoulder   // neutral, as in the screenshot
        case system     // neutral, as in the screenshot
        case stick      // neutral, as in the screenshot
        case joystick   // the analog stick: a base and a knob, not a button
    }

    enum Shape {
        case circle(CGFloat)              // diameter, in layout units
        case roundedRect(CGSize, CGFloat) // size and corner radius, in layout units
    }

    /// One control: what it is called on the wire, what it draws, and where it sits
    /// relative to its cluster's centre dot. +x is right, +y is down.
    struct Control: Identifiable {
        let id: String        // the label the bridge translation switches on
        let glyph: String
        let offset: CGPoint
        let shape: Shape
        let style: Style
    }

    // The cross is measurably wider than it is tall in the source (73.75 vs 68.75 px);
    // that asymmetry is in the screenshot, so it is kept rather than tidied away.
    private static let crossX: CGFloat = 1.240
    private static let crossY: CGFloat = 1.155
    private static let systemOffset = CGPoint(x: 2.353, y: -1.025)
    private static let shoulderSpreadX: CGFloat = 1.004
    private static let shoulderY: CGFloat = -2.824

    private static let button = Shape.circle(1.0)
    private static let stick = Shape.circle(stickDiameter)
    private static let system = Shape.circle(systemDiameter)
    private static let shoulder = Shape.roundedRect(shoulderSize, shoulderCornerRadius)

    /// D-pad, minus, L and ZL, around the left centre dot.
    static let leftCluster: [Control] = [
        Control(id: "up",    glyph: "\u{25B2}", offset: CGPoint(x: 0, y: -crossY), shape: button, style: .dpad),
        Control(id: "left",  glyph: "\u{25C0}", offset: CGPoint(x: -crossX, y: 0), shape: button, style: .dpad),
        Control(id: "right", glyph: "\u{25B6}", offset: CGPoint(x: crossX, y: 0),  shape: button, style: .dpad),
        Control(id: "down",  glyph: "\u{25BC}", offset: CGPoint(x: 0, y: crossY),  shape: button, style: .dpad),
        Control(id: "L3",    glyph: "",         offset: .zero,                     shape: stick,  style: .stick),
        Control(id: "minus", glyph: "\u{2212}", offset: systemOffset,              shape: system, style: .system),
        Control(id: "L",     glyph: "L",  offset: CGPoint(x: shoulderSpreadX, y: shoulderY),  shape: shoulder, style: .shoulder),
        Control(id: "ZL",    glyph: "ZL", offset: CGPoint(x: -shoulderSpreadX, y: shoulderY), shape: shoulder, style: .shoulder)
    ]

    /// Comfort controls: the d-pad half with L, ZL and minus taken back out of it - they
    /// move onto leftStickClusterComfort below instead. Everything that is left keeps the
    /// exact offsets leftCluster already uses, so the d-pad and its L3 dot do not shift by
    /// so much as a point when comfort mode turns on; only where the other three buttons
    /// live changes.
    static let leftClusterComfort: [Control] = [
        Control(id: "up",    glyph: "\u{25B2}", offset: CGPoint(x: 0, y: -crossY), shape: button, style: .dpad),
        Control(id: "left",  glyph: "\u{25C0}", offset: CGPoint(x: -crossX, y: 0), shape: button, style: .dpad),
        Control(id: "right", glyph: "\u{25B6}", offset: CGPoint(x: crossX, y: 0),  shape: button, style: .dpad),
        Control(id: "down",  glyph: "\u{25BC}", offset: CGPoint(x: 0, y: crossY),  shape: button, style: .dpad),
        Control(id: "L3",    glyph: "",         offset: .zero,                     shape: stick,  style: .stick)
    ]

    /// The left analog stick, for joystick mode: its own one-control cluster, added
    /// alongside the d-pad (which stays, along with its L3 dot) rather than replacing it.
    static let leftStickCluster: [Control] = [
        Control(id: "stickL", glyph: "", offset: .zero,
                shape: .circle(stickBaseDiameter), style: .joystick)
    ]

    /// Comfort controls: L, ZL and minus, re-anchored to the left stick's own centre
    /// instead of the d-pad's.
    ///
    /// The offsets are not new numbers - they are `leftCluster`'s own `shoulderSpreadX`/
    /// `shoulderY`/`systemOffset`, copied verbatim and given a different centre to sit
    /// around. That is the whole of what "comfort" changes here: which cluster a button's
    /// offset is measured from, never the offset itself or the button's size. Since this
    /// cluster's own footprint is a single circle only a little smaller than the d-pad's
    /// diamond-plus-cross, the same spacing that kept these three clear of the d-pad keeps
    /// them clear of the stick too - see the ControllerPad comfort-mode note for the
    /// worked distance that makes this provably non-overlapping at the default position.
    static let leftStickClusterComfort: [Control] = [
        Control(id: "stickL", glyph: "", offset: .zero,
                shape: .circle(stickBaseDiameter), style: .joystick),
        Control(id: "minus", glyph: "\u{2212}", offset: systemOffset, shape: system, style: .system),
        Control(id: "L",     glyph: "L",  offset: CGPoint(x: shoulderSpreadX, y: shoulderY),  shape: shoulder, style: .shoulder),
        Control(id: "ZL",    glyph: "ZL", offset: CGPoint(x: -shoulderSpreadX, y: shoulderY), shape: shoulder, style: .shoulder)
    ]

    /// Where the left stick starts, mirrored from rightStickAnchorOffset (x negated,
    /// same y) - inboard of the d-pad and a little above it, clearing the minus button
    /// and sitting below the shoulders rather than beside them, for the same reasons
    /// rightStickAnchorOffset's own comment gives. Placed rather than measured, same
    /// caveat as that one: the source photograph has no room for a d-pad and a full
    /// stick at once.
    static let leftStickAnchorOffset = CGPoint(x: 5.0, y: -1.6)

    /// The stick's outer ring, in layout units: the d-pad cross's own measured width
    /// (2 x crossX + one button), reused here as a sensible stick size rather than a
    /// number picked by eye - both leftStickCluster and rightStickCluster share it.
    static let stickBaseDiameter: CGFloat = 2 * crossX + 1.0
    /// The thumb cap. Close to a face button, so it reads as something you push around
    /// rather than a dot that happens to move.
    static let stickKnobDiameter: CGFloat = 1.15
    /// How far the knob's centre may leave the base's centre before it is at full
    /// deflection, as a fraction of the ring's radius. The rule for every on-screen stick,
    /// in both pads.
    ///
    /// 1.0: the knob stays tethered to the centre, but its centre reaches the ring itself,
    /// so at full push half the knob hangs past the ring - the way the GamePad's cap tilts
    /// out over the edge of its dish. It used to stop with the knob's edge touching the
    /// ring, which left only (ring - knob) / 2 of travel: 1.17 D here, and just 0.43 D on
    /// the new pad's hardware-sized dish, too short to steer with.
    static let stickTravelFraction: CGFloat = 1.0

    /// Full-deflection travel for a stick whose ring has this diameter, in the same units.
    static func stickTravel(ringDiameter: CGFloat) -> CGFloat {
        ringDiameter / 2 * stickTravelFraction
    }

    /// The shape the knob may reach. The real GamePad's sticks sit in an octagonal gate:
    /// the eight cardinals and diagonals reach full travel, the flats between them stop
    /// about 8% short. Round reaches full travel in every direction.
    enum StickGate: String, CaseIterable, Identifiable {
        case octagon
        case round

        var id: String { rawValue }

        var title: String {
            switch self {
            case .octagon: return "Octagonal"
            case .round:   return "Round"
            }
        }

        /// For the settings screen: what picking this actually does, in one line.
        var summary: String {
            switch self {
            case .octagon:
                return "Matches the real GamePad: full push in the eight main directions, slightly less in between."
            case .round:
                return "Full push in every direction."
            }
        }

        /// How far the gate lies from the centre along `angle`, as a fraction of the
        /// stick's full travel. 1 at a vertex, `cos(22.5 deg)` on a flat.
        ///
        /// Standard regular-polygon inradius-over-cosine, folded into one 45-degree
        /// segment: a regular octagon is eight copies of the same wedge, so only the
        /// angle within a wedge matters. The fold is written as a remainder plus a
        /// correction rather than an `abs`, because `atan2` returns negative angles for
        /// the lower half of the screen and truncatingRemainder keeps their sign - the
        /// uncorrected value would put the whole bottom of the stick on the wrong side
        /// of the wedge and make its gate the mirror image of the top's.
        func radiusFraction(atAngle angle: CGFloat) -> CGFloat {
            switch self {
            case .round:
                return 1
            case .octagon:
                let wedge = CGFloat.pi / 4
                var offset = angle.truncatingRemainder(dividingBy: wedge)
                if offset < 0 { offset += wedge }
                return cos(wedge / 2) / cos(offset - wedge / 2)
            }
        }
    }

    /// The camera stick, for joystick mode: the right analog stick, drawn as its own
    /// one-control cluster rather than folded into the right half.
    ///
    /// It is a separate cluster because it cannot be the right half's centre dot the way
    /// the left stick is the left half's. The dot sits inside the ring of A/B/X/Y, and a
    /// stick the size of the one this needs would be drawn straight over all four of
    /// them. Its own cluster also means its own drag handle and its own stored offset, so
    /// where the camera sits is a decision made with a thumb on the glass instead of one
    /// inherited from where the face buttons happen to be.
    ///
    /// R3 is untouched. Unlike L3 it never lost its dot, so a tap here is not the click -
    /// the click is still the dot in the middle of A/B/X/Y where the measured layout
    /// draws it, in both modes.
    static let rightStickCluster: [Control] = [
        Control(id: "stickR", glyph: "", offset: .zero,
                shape: .circle(stickBaseDiameter), style: .joystick)
    ]

    /// Comfort controls: R, ZR and plus, re-anchored to the camera stick's own centre
    /// instead of A/B/X/Y's - mirrors leftStickClusterComfort exactly, same reasoning and
    /// the same borrowed offsets (systemOffset mirrored the same way rightCluster's own
    /// plus already mirrors it, shoulderSpreadX/shoulderY unmirrored since they are
    /// already signed per side).
    static let rightStickClusterComfort: [Control] = [
        Control(id: "stickR", glyph: "", offset: .zero,
                shape: .circle(stickBaseDiameter), style: .joystick),
        Control(id: "plus", glyph: "\u{FF0B}", offset: CGPoint(x: -systemOffset.x, y: systemOffset.y), shape: system, style: .system),
        Control(id: "R",    glyph: "R",  offset: CGPoint(x: -shoulderSpreadX, y: shoulderY), shape: shoulder, style: .shoulder),
        Control(id: "ZR",   glyph: "ZR", offset: CGPoint(x: shoulderSpreadX, y: shoulderY),  shape: shoulder, style: .shoulder)
    ]

    /// Where the camera stick starts, as an offset in units from the right cluster's
    /// anchor: inboard of A/B/X/Y and a little above it.
    ///
    /// This one is placed rather than measured - the source layout is a photograph of a
    /// GamePad, which has its right stick above the face buttons in a space an on-screen
    /// pad does not have. So it is chosen to the one standard the measurements can still
    /// hold it to: it overlaps nothing. At this offset its right edge clears the plus
    /// button by more than half a button width, and it sits below the shoulders rather
    /// than beside them. Everything past that is thumb ergonomics, which is why it is a
    /// starting point with a drag handle rather than a fixed position.
    static let rightStickAnchorOffset = CGPoint(x: -5.0, y: -1.6)

    /// The sideways shift, in units, each stick cluster gets from the stick-spacing
    /// setting (ControllerLayoutSettings.stickSpacingKey). Positive is toward its own edge.
    /// Inward stops while the two clusters still have half a button between them, so on a
    /// narrow screen the setting runs out instead of crossing the sticks over. Outward
    /// tops out at 1.5, where a stick still clears its d-pad / A-B-X-Y diamond.
    static func stickShift(spacing: Double, containerWidth: CGFloat, unit: CGFloat,
                           left: [Control], right: [Control]) -> CGFloat {
        let requested = CGFloat(min(max(spacing, ControllerLayoutSettings.minStickSpacing),
                                    ControllerLayoutSettings.maxStickSpacing))
        guard requested < 0, unit > 0 else { return requested }
        let fromEdge = centreFromNearEdge + leftStickAnchorOffset.x
        let centreGap = containerWidth / unit - 2 * fromEdge
        let needed = bounds(of: left).maxX - bounds(of: right).minX + 0.5
        return max(requested, -max(0, (centreGap - needed) / 2))
    }

    /// The vertical shift, in units, a cluster's shoulder buttons (L/ZL or R/ZR) get from
    /// the shoulder-offset setting (ControllerLayoutSettings.shoulderOffsetKey). Positive is
    /// down. Every shoulder in the cluster gets the same shift, so they keep their layout
    /// relative to each other; the cluster's other controls do not move at all.
    ///
    /// Held to the room there actually is: up, the shoulders stop a quarter-button short of
    /// the top of the container; down, they stop a fifth of a button above the highest
    /// control in the same cluster that sits under them (the d-pad's up arrow, or the stick
    /// in comfort mode), so they never end up on top of it. `centreY` is where the cluster's
    /// centre actually is on screen, in points, after its own clamp.
    ///
    /// The shift is applied to where each shoulder is POSITIONED, not by padding or offsetting
    /// the control's view, so its hit area moves with it (see muffin-pad-hit-testing-trap).
    static func shoulderShift(offset: Double, centreY: CGFloat, containerHeight: CGFloat, unit: CGFloat,
                              controls: [Control], topInset: CGFloat = 0,
                              range: ClosedRange<Double> = ControllerLayoutSettings.minShoulderOffset...ControllerLayoutSettings.maxShoulderOffset) -> CGFloat {
        let requested = CGFloat(min(max(offset, range.lowerBound), range.upperBound))
        guard requested != 0, unit > 0 else { return 0 }
        let shoulders = controls.filter { $0.style == .shoulder }
        guard !shoulders.isEmpty else { return 0 }

        func extent(_ c: Control) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
            let size: CGSize
            switch c.shape {
            case .circle(let diameter):    size = CGSize(width: diameter, height: diameter)
            case .roundedRect(let box, _): size = box
            }
            return (c.offset.x - size.width / 2, c.offset.x + size.width / 2,
                    c.offset.y - size.height / 2, c.offset.y + size.height / 2)
        }
        let shoulderBox = shoulders.map(extent)
        let top = shoulderBox.map { $0.minY }.min() ?? 0
        let bottom = shoulderBox.map { $0.maxY }.max() ?? 0
        let left = shoulderBox.map { $0.minX }.min() ?? 0
        let right = shoulderBox.map { $0.maxX }.max() ?? 0

        // Most the shoulders can move up: their top edge to a quarter-button below the top
        // (below the top bar, when the caller says one covers it).
        let up = -((centreY - topInset) / unit + top - 0.25)
        // Most they can move down: until their bottom edge is a fifth of a button above the
        // nearest control beneath them, if there is one.
        let gap: CGFloat = 0.2
        var down = (containerHeight - centreY) / unit - bottom
        for other in controls where other.style != .shoulder {
            let e = extent(other)
            guard e.maxX > left - gap, e.minX < right + gap, e.minY >= top else { continue }
            down = min(down, e.minY - gap - bottom)
        }
        // A cluster with less room than that (a very short container) simply stays put.
        return min(max(requested, min(up, 0)), max(down, 0))
    }

    /// The deflection below which a gesture counts as a tap rather than a push, for the
    /// tap-is-L3 rule.
    ///
    /// Deliberately not the deadzone. The deadzone is a feel setting and can be turned
    /// all the way down to nothing, and if the click threshold went with it then at zero
    /// deadzone every press of the stick - however still the thumb - would be a movement
    /// and L3 would become unreachable. This is the separate, fixed answer to a separate
    /// question: did the finger mean to move the stick at all.
    static let stickClickThreshold: CGFloat = 0.14

    /// A/B/X/Y, plus, R and ZR, around the right centre dot. Mirroring the left half is
    /// not a shortcut - it is what the measurements say the layout is - but the ids and
    /// glyphs differ, so the positions are mirrored and the identities written out.
    static let rightCluster: [Control] = [
        Control(id: "X", glyph: "X", offset: CGPoint(x: 0, y: -crossY), shape: button, style: .face),
        Control(id: "Y", glyph: "Y", offset: CGPoint(x: -crossX, y: 0), shape: button, style: .face),
        Control(id: "A", glyph: "A", offset: CGPoint(x: crossX, y: 0),  shape: button, style: .face),
        Control(id: "B", glyph: "B", offset: CGPoint(x: 0, y: crossY),  shape: button, style: .face),
        Control(id: "R3",   glyph: "",        offset: .zero, shape: stick, style: .stick),
        Control(id: "plus", glyph: "\u{FF0B}", offset: CGPoint(x: -systemOffset.x, y: systemOffset.y), shape: system, style: .system),
        Control(id: "R",    glyph: "R",  offset: CGPoint(x: -shoulderSpreadX, y: shoulderY), shape: shoulder, style: .shoulder),
        Control(id: "ZR",   glyph: "ZR", offset: CGPoint(x: shoulderSpreadX, y: shoulderY),  shape: shoulder, style: .shoulder)
    ]

    /// Comfort controls: the A/B/X/Y half with R, ZR and plus taken back out of it -
    /// mirrors leftClusterComfort exactly, same reasoning.
    static let rightClusterComfort: [Control] = [
        Control(id: "X", glyph: "X", offset: CGPoint(x: 0, y: -crossY), shape: button, style: .face),
        Control(id: "Y", glyph: "Y", offset: CGPoint(x: -crossX, y: 0), shape: button, style: .face),
        Control(id: "A", glyph: "A", offset: CGPoint(x: crossX, y: 0),  shape: button, style: .face),
        Control(id: "B", glyph: "B", offset: CGPoint(x: 0, y: crossY),  shape: button, style: .face),
        Control(id: "R3", glyph: "", offset: .zero, shape: stick, style: .stick)
    ]

    /// One control's width and height, in layout units.
    static func size(of control: Control) -> CGSize {
        switch control.shape {
        case .circle(let diameter):    return CGSize(width: diameter, height: diameter)
        case .roundedRect(let box, _): return box
        }
    }

    /// The rectangle a cluster actually covers, in layout units, relative to its centre
    /// dot. Derived from the control list rather than written down, so it cannot drift out
    /// of step with it - it is what the drag handle is sized to and what keeps a dragged
    /// cluster from being pushed off the edge and lost.
    static func bounds(of cluster: [Control]) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for control in cluster {
            let size: CGSize
            switch control.shape {
            case .circle(let diameter):    size = CGSize(width: diameter, height: diameter)
            case .roundedRect(let box, _): size = box
            }
            minX = min(minX, control.offset.x - size.width / 2)
            maxX = max(maxX, control.offset.x + size.width / 2)
            minY = min(minY, control.offset.y - size.height / 2)
            maxY = max(maxY, control.offset.y + size.height / 2)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// The size of the window the pad is drawn in, kept current across rotation so the settings
/// sliders can offer the range for the orientation the iPad is in right now.
@MainActor
final class ControlsWindowSize: ObservableObject {
    static let shared = ControlsWindowSize()
    @Published private(set) var size: CGSize = ControlsWindowSize.measure()

    private init() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        for name in [UIDevice.orientationDidChangeNotification, UIApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // The window's bounds settle a moment after the notification.
                for delay in [0.05, 0.5] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.refresh() }
                }
            }
        }
    }

    func refresh() {
        let now = Self.measure()
        if now != size { size = now }
    }

    private static func measure() -> CGSize {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        return window?.bounds.size ?? UIScreen.main.bounds.size
    }

    /// The size of the pad itself while one is on screen, reported by the pad. The pad and the
    /// settings sliders both pick the orientation's stored value from this one size.
    @Published private(set) var padSize: CGSize?

    func reportPad(_ size: CGSize?) {
        if padSize != size { padSize = size }
    }

    /// The size the orientation is taken from: the pad's own, else the window's.
    var effectiveSize: CGSize { padSize ?? size }
}

extension View {
    /// Reports this view's size as the pad's, for as long as it is on screen. A background, so
    /// it takes no part in the layout.
    @MainActor
    func reportsPadSize(_ onSize: @escaping (CGSize) -> Void = { _ in }) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { ControlsWindowSize.shared.reportPad(proxy.size); onSize(proxy.size) }
                    .onChange(of: proxy.size) { newSize in ControlsWindowSize.shared.reportPad(newSize); onSize(newSize) }
            }
            .allowsHitTesting(false)
        )
        .onDisappear { ControlsWindowSize.shared.reportPad(nil) }
    }
}

/// The shoulder-height setting as stored, whichever device and way up.
///
/// iPad: landscape is `shoulderOffsetKey`, as it always was. Upright reads the same shared
/// value until the upright key has been written (the first time the slider is moved upright),
/// so nobody's shoulders move when the two are split. iPhone: its own keys, never the iPad's.
struct ShoulderOffsetStorage: DynamicProperty {
    @AppStorage(ControllerLayoutSettings.shoulderOffsetKey) private var padLandscape = ControllerLayoutSettings.defaultShoulderOffset
    @AppStorage(ControllerLayoutSettings.shoulderOffsetPortraitKey) private var padPortrait = ControllerLayoutSettings.defaultShoulderOffset
    @AppStorage(ControllerLayoutSettings.shoulderOffsetPhoneKey) private var phoneLandscape = ControllerLayoutSettings.defaultShoulderOffset
    @AppStorage(ControllerLayoutSettings.shoulderOffsetPhonePortraitKey) private var phonePortrait = ControllerLayoutSettings.defaultShoulderOffset

    func value(upright: Bool) -> Double {
        if ControllerLayoutSettings.usesPadShoulderKeys {
            guard upright else { return padLandscape }
            let written = UserDefaults.standard.object(forKey: ControllerLayoutSettings.shoulderOffsetPortraitKey) != nil
            return written ? padPortrait : padLandscape
        }
        return upright ? phonePortrait : phoneLandscape
    }

    func set(_ newValue: Double, upright: Bool) {
        if ControllerLayoutSettings.usesPadShoulderKeys {
            if upright { padPortrait = newValue } else { padLandscape = newValue }
        } else {
            if upright { phonePortrait = newValue } else { phoneLandscape = newValue }
        }
    }

    func binding(upright: Bool) -> Binding<Double> {
        Binding(get: { value(upright: upright) }, set: { set($0, upright: upright) })
    }

    func reset() {
        let zero = ControllerLayoutSettings.defaultShoulderOffset
        set(zero, upright: false)
        set(zero, upright: true)
    }
}
