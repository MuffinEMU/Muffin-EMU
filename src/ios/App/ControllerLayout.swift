import SwiftUI

/// Where the on-screen pad's adjustable values live, so the settings sheet, the emulator
/// view and the pad itself agree on the keys without any of them importing the others -
/// the same arrangement `LaunchLogSettings` already uses for its one key.
///
/// Offsets are stored in POINTS, not in layout units. A drag is something the user did
/// with a finger at a particular size, and re-interpreting it against a different unit
/// when the size slider moves would make the cluster wander every time it was resized.
enum ControllerLayoutSettings {
    static let scaleKey = "muffin.controls.scale"
    static let opacityKey = "muffin.controls.opacity"
    static let leftOffsetXKey = "muffin.controls.left.dx"
    static let leftOffsetYKey = "muffin.controls.left.dy"
    static let rightOffsetXKey = "muffin.controls.right.dx"
    static let rightOffsetYKey = "muffin.controls.right.dy"
    /// Whether the left cluster's d-pad is replaced by an analog stick. Off by default:
    /// the measured layout is a d-pad, and a control scheme is not something to change
    /// under someone who did not ask for it.
    static let joystickKey = "muffin.controls.joystick"
    /// Whether L/ZL/minus and R/ZR/plus are anchored to the analog sticks instead of the
    /// d-pad/A-B-X-Y clusters. Only has anything to attach to while `joystickKey` is also
    /// on - see the comfortControls read site in ControllerPad for what happens when it
    /// isn't. Off by default, same reasoning as `joystickKey`: the measured layout puts
    /// these six buttons at the d-pad/face clusters, and a control scheme is not
    /// something to change under someone who did not ask for it.
    static let comfortControlsKey = "muffin.pad.comfortControls"
    static let defaultComfortControls = false
    /// Where the camera stick has been dragged to. Its own pair rather than sharing the
    /// right cluster's: it is a separate cluster, positioned separately, and the whole
    /// point of it is that it sits where the right thumb reaches without leaving A/B/X/Y
    /// - which is a different place on a phone than on an iPad.
    static let rightStickOffsetXKey = "muffin.controls.rstick.dx"
    static let rightStickOffsetYKey = "muffin.controls.rstick.dy"
    /// Same reasoning as the pair above, mirrored for the left stick: its own position,
    /// separate from the d-pad cluster it now sits alongside rather than replaces.
    static let leftStickOffsetXKey = "muffin.controls.lstick.dx"
    static let leftStickOffsetYKey = "muffin.controls.lstick.dy"
    /// How much of the stick's travel reads as centred, how the rest of it is shaped, and
    /// what shape it may reach. All three are feel rather than layout, which is why none
    /// of them is in `reset()` below.
    static let deadzoneKey = "muffin.controls.stick.deadzone"
    static let stickCurveKey = "muffin.controls.stick.curve"
    static let stickGateKey = "muffin.controls.stick.gate"

    /// Grouped (false): dragging anywhere on a cluster's dashed box moves the whole
    /// cluster, and each button's own drag/pinch only fires where it visibly overlaps
    /// that box - the two gestures were both always attached and left to sort out
    /// priority between themselves by touch position, which did not resolve the way it
    /// looked like it should on-device: a drag anywhere in a cluster moved the whole
    /// cluster, individual buttons included. Individual (true) makes that unambiguous
    /// instead of trying to fix the priority: the cluster's own drag handle is not
    /// attached at all, so every touch can only ever be a single button's own drag or
    /// pinch, with nothing left for it to compete against.
    static let individualEditModeKey = "muffin.controls.individualEditMode"
    static let defaultIndividualEditMode = false

    /// Whether a press fires a light haptic tap. On by default - a pad with no physical
    /// switches under the glass loses the one confirmation a real button gives for free,
    /// and the tap is the cheapest way to give some of it back. Left as a setting rather
    /// than unconditional because it is still a buzz against the hand on every single
    /// input, which is exactly the kind of thing that reads as delightful at first and
    /// grating by the tenth hour of play for some people.
    static let hapticsKey = "muffin.pad.haptics"
    static let defaultHaptics = true

    static let defaultJoystick = false

    /// Fraction of full travel that reads as centred.
    ///
    /// Small, because this stick is absolute: the knob goes where the finger is, so a
    /// thumb at rest is a thumb that was deliberately put there, and the drift a deadzone
    /// exists to swallow is only the tremor of a finger already on the glass. The large
    /// deadzones physical sticks need are for worn potentiometers that no longer return
    /// to zero, which is not a problem a piece of capacitive glass has.
    static let defaultDeadzone: Double = 0.06
    static let minDeadzone: Double = 0.0
    static let maxDeadzone: Double = 0.30

    /// The exponent applied to the stick's magnitude after the deadzone is rescaled out.
    ///
    /// 1.0 is linear: the number the title receives is the fraction of travel the thumb
    /// actually covered, and nothing in between reshapes it. Above 1.0 the early travel
    /// produces smaller values, so the same thumb movement near the centre buys finer
    /// control - which is what makes a light lean in Mario Kart a light lean instead of a
    /// quarter turn. 0 and 1 map to themselves at every setting, so raising it never
    /// costs the stick its top end nor gives it a false centre.
    static let defaultStickCurve: Double = 1.0
    static let minStickCurve: Double = 1.0
    static let maxStickCurve: Double = 2.5

    /// The gate the stick reaches by default.
    ///
    /// Octagonal, because that is what the hardware this is imitating does, and the
    /// difference is not cosmetic - see `StickGate` for what it changes about the numbers
    /// a title receives.
    /// Stored as its raw string, so the key survives a case being added or reordered.
    static let defaultStickGate = ControllerGeometry.StickGate.octagon
    static let defaultStickGateRaw = ControllerGeometry.StickGate.octagon.rawValue
    static let defaultScale: Double = 1.0
    static let defaultOpacity: Double = 0.85
    static let minScale: Double = 0.6
    static let maxScale: Double = 1.6

    /// Puts every adjustment back where the measured layout says it goes. Removing the
    /// keys rather than writing the defaults into them is deliberate: `@AppStorage` falls
    /// back to its declared default for a missing key, so one list here cannot drift out
    /// of step with the defaults declared at each use site.
    /// `joystickKey` is deliberately not in this list. "Reset layout" is about where the
    /// controls are and how big they are; which control scheme you play with is a
    /// different question, and silently switching someone back to the d-pad because they
    /// nudged a cluster too far would be a surprise, not a reset.
    static func reset() {
        let defaults = UserDefaults.standard
        for key in [scaleKey, opacityKey, rightStickOffsetXKey, rightStickOffsetYKey,
                    leftStickOffsetXKey, leftStickOffsetYKey,
                    leftOffsetXKey, leftOffsetYKey,
                    rightOffsetXKey, rightOffsetYKey] {
            defaults.removeObject(forKey: key)
        }
        // Per-element placement is layout too. Leaving it behind would make this button
        // look broken: the clusters would snap back while every control inside them
        // stayed where it had been dragged.
        ControllerCustomLayout.shared.resetAll()
    }
}

/// The on-screen pad's arrangement, taken by measurement from the layout Void sent
/// (bward-dev1/Wiiuios, IMG_3278.jpeg) rather than re-invented, because the last version
/// of this file re-invented it and the result was unusable.
///
/// Measured button centres in that screenshot (1080x498 px, face-button diameter 59.5 px):
///
///     ZL(126,175)   L(245.5,175)            R(833.5,175)   ZR(953.5,175)
///        up(186,273.5)   -(326,282)           +(753,282)     X(893.5,273.5)
///     left(112,342.5) o(186,343) right(259.5,342.5)
///                                          Y(819.5,342.5) o(894,343) A(967.5,342.5)
///        down(186,411.5)                                    B(893.5,411.5)
///
/// The right-hand half is an exact mirror of the left about x = 540 (every measured pair
/// agrees to within a pixel), so only one half is written out below and the other is that
/// one with x negated. Note the two things the previous layout got wrong and this one
/// does not: the face buttons are X-top / Y-left / A-right / B-bottom, and the d-pad is a
/// diamond of circles, not a column of squares.
///
/// Every number is expressed in units of one face-button diameter, so the arrangement
/// survives being drawn at any size: change the unit and the whole cluster scales without
/// a single relationship between two buttons shifting. That is what makes the automatic
/// sizing below safe - it only ever chooses the unit.
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

    /// The left analog stick, for joystick mode: drawn as its own one-control cluster,
    /// exactly mirroring rightStickCluster below - both are "joystick mode adds a stick
    /// alongside the measured cluster," never "joystick mode replaces it."
    ///
    /// This used to replace the d-pad's own four circles + centre dot outright
    /// (leftClusterJoystick, now gone) - a different, inconsistent behaviour from the
    /// right side, where joystick mode has only ever ADDED a separate camera stick
    /// without ever removing A/B/X/Y. Void's ask ("no longer one or the other, make
    /// them both be there") is exactly that inconsistency: the d-pad now never leaves,
    /// on either side, in either mode - only whether a stick is ALSO present changes.
    ///
    /// L3 is unaffected, same reasoning as R3: it stays the dot in the d-pad's own
    /// centre in both modes, since this cluster no longer touches it.
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
    /// deflection - the knob stays inside its own ring at the extremes, as a real stick's
    /// cap does.
    static var stickTravel: CGFloat { (stickBaseDiameter - stickKnobDiameter) / 2 }

    /// The shape the knob may reach, which is a fidelity question and not a cosmetic one.
    ///
    /// The GamePad's sticks sit in an octagonal gate, and that gate is why a Wii U stick
    /// does not behave like a circle. On a circle the magnitude is 1 in every direction,
    /// so a diagonal is as strong as a cardinal and there is nothing under the thumb to
    /// say where the diagonals are. In the gate the eight vertices - the four cardinals
    /// and the four diagonals - are the only directions that reach full travel, and the
    /// flats between them stop about 8% short. That is what a title tuned on the console
    /// was tuned against: Mario Kart's drift, and the eight-way feel of walking in Zelda
    /// and 3D World, are both read off a stick whose corners were cut this way.
    ///
    /// Round is kept because it is what every other on-screen stick does and because the
    /// gate is a real constraint - it takes about 8% off the top of every direction that
    /// is not one of the eight, and someone who wants the maximum number in every
    /// direction should be able to have it.
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
                return "The GamePad's own gate. Full travel at the four cardinals and the four diagonals, a little short of it in between - the shape the games were tuned against."
            case .round:
                return "Full travel in every direction. Stronger off the eight, and with nothing marking where the diagonals are."
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
