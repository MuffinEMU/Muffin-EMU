import SwiftUI
import Dispatch

/// The on-screen pad.
///
/// Previously this was an HStack of a d-pad column and an A/B/X/Y column, which put the
/// face buttons in the wrong places, had no shoulders, no plus/minus and no stick clicks,
/// and could not be moved or resized. It now draws the arrangement in
/// `ControllerGeometry` - measured from the layout Void sent - by absolute position,
/// which is what lets one unit scale the whole thing and lets a cluster be dragged.
///
/// Still no backing plate and no divider, for the reason the old version documented: an
/// opaque slab had to sit in the layout flow and stole a strip of height from the
/// emulator view for the sole purpose of being grey. Every control here is positioned
/// over the game, and the space between the two clusters is not hit-tested at all, so
/// taps in the middle still reach the game view.
///
/// `skin.backgroundColor` and `skin.borderColor` are still read by SkinPreview, so the
/// skin catalog is untouched; it is only the in-game pad that never painted them.
struct OptimizedControlPanel: View {
    let skin: WiiUControllerSkin
    // (label, pressed) - not (label). A tap has no way to express "still held", and
    // holding a direction is most of playing anything, so the whole panel reports state
    // changes rather than events. Every `true` is followed by exactly one `false`.
    let onInput: (String, Bool) -> Void
    /// Where the analog stick currently is, reported continuously while it is held and
    /// once more as (0, 0) when it is let go.
    ///
    /// Separate from `onInput` because a stick is not a button and the engine does not
    /// treat it as one: Cemu derives the sticks from get_axis(), skipping them in the
    /// button loop entirely, so a direction sent as a press is discarded rather than
    /// approximated. `stick` is 0 for the left stick; x is right-positive and y is
    /// UP-positive - the console's convention, converted from the screen's here rather
    /// than left for the call site to remember.
    let onStick: (Int, CGPoint) -> Void
    /// While this is on the clusters carry a drag handle and the buttons themselves stop
    /// responding - otherwise the first touch of a drag would also press whatever it
    /// landed on, and moving the pad would mean firing a button into the running title.
    @Binding var isEditingLayout: Bool

    @AppStorage(ControllerLayoutSettings.scaleKey)
    private var userScale = ControllerLayoutSettings.defaultScale
    @AppStorage(ControllerLayoutSettings.opacityKey)
    private var padOpacity = ControllerLayoutSettings.defaultOpacity
    @AppStorage(ControllerLayoutSettings.leftOffsetXKey) private var leftOffsetX = 0.0
    @AppStorage(ControllerLayoutSettings.leftOffsetYKey) private var leftOffsetY = 0.0
    @AppStorage(ControllerLayoutSettings.rightOffsetXKey) private var rightOffsetX = 0.0
    @AppStorage(ControllerLayoutSettings.rightOffsetYKey) private var rightOffsetY = 0.0
    @AppStorage(ControllerLayoutSettings.rightStickOffsetXKey) private var rightStickOffsetX = 0.0
    @AppStorage(ControllerLayoutSettings.rightStickOffsetYKey) private var rightStickOffsetY = 0.0
    // Must keep matching SettingsView's declaration of the same key: two @AppStorage
    // defaults for one key that disagree means the toggle and the pad disagree about
    // which control scheme is on.
    @AppStorage(ControllerLayoutSettings.joystickKey)
    private var joystickMode = ControllerLayoutSettings.defaultJoystick

    var body: some View {
        // The automatic half of "adjustable + automatic sizing": GeometryReader re-runs
        // on every size change the pad can experience - rotation, a resized scene, an
        // external display being attached - so the unit, both anchors and the drag
        // clamps are all recomputed from the size that is actually on screen rather
        // than from anything cached at launch.
        GeometryReader { proxy in
            let unit = ControllerGeometry.automaticDiameter(in: proxy.size) * CGFloat(userScale)

            ZStack(alignment: .topLeading) {
                ControlCluster(
                    // The only difference between the two schemes. The right cluster,
                    // both anchors and every offset are shared, so switching modes
                    // swaps the d-pad for a stick and disturbs nothing else.
                    controls: joystickMode
                        ? ControllerGeometry.leftClusterJoystick
                        : ControllerGeometry.leftCluster,
                    edge: .leading,
                    skin: skin,
                    unit: unit,
                    container: proxy.size,
                    isEditingLayout: isEditingLayout,
                    offsetX: $leftOffsetX,
                    offsetY: $leftOffsetY,
                    onInput: onInput,
                    onStick: { onStick(0, $0) }
                )

                ControlCluster(
                    controls: ControllerGeometry.rightCluster,
                    edge: .trailing,
                    skin: skin,
                    unit: unit,
                    container: proxy.size,
                    isEditingLayout: isEditingLayout,
                    offsetX: $rightOffsetX,
                    offsetY: $rightOffsetY,
                    onInput: onInput,
                    // The right half itself has no stick: its centre dot is R3, as the
                    // measured layout draws it, and the camera stick below is its own
                    // cluster. Nothing in this one can report an axis, so this closure is
                    // never called - wired rather than omitted because a cluster that
                    // silently could not carry a stick is a trap for the next person to
                    // put one in it.
                    onStick: { onStick(1, $0) }
                )

                // The camera stick, in joystick mode only. A separate cluster, so it has
                // its own drag handle and its own stored position: the right half stays
                // exactly where the measurements put it, and turning the mode on adds a
                // control rather than rearranging the ones already there.
                if joystickMode {
                    ControlCluster(
                        controls: ControllerGeometry.rightStickCluster,
                        edge: .trailing,
                        anchorOffset: ControllerGeometry.rightStickAnchorOffset,
                        skin: skin,
                        unit: unit,
                        container: proxy.size,
                        isEditingLayout: isEditingLayout,
                        offsetX: $rightStickOffsetX,
                        offsetY: $rightStickOffsetY,
                        onInput: onInput,
                        onStick: { onStick(1, $0) }
                    )
                }
            }
            // Editing is a mode you want to see clearly, so it ignores the opacity
            // setting rather than making someone turn the pad back up to reposition it.
            .opacity(isEditingLayout ? 1.0 : max(padOpacity, 0.15))
        }
    }
}

/// One half of the pad, laid out around a single centre point.
private struct ControlCluster: View {
    let controls: [ControllerGeometry.Control]
    let edge: HorizontalEdge
    /// Shifts this cluster's unmoved position, in units, away from the standard anchor -
    /// for a cluster the measured layout has no anchor for. Applied before the user's
    /// drag and before the clamp, so it is genuinely a different starting point rather
    /// than a drag nobody made: "Reset layout" returns here, not to the shared anchor.
    var anchorOffset: CGPoint = .zero
    let skin: WiiUControllerSkin
    let unit: CGFloat
    let container: CGSize
    let isEditingLayout: Bool
    @Binding var offsetX: Double
    @Binding var offsetY: Double
    let onInput: (String, Bool) -> Void
    let onStick: (CGPoint) -> Void

    enum HorizontalEdge { case leading, trailing }

    /// Where the drag started, so a drag applies to the offset the cluster had when the
    /// finger went down. Reading the live offset each frame instead would compound the
    /// translation, which DragGesture reports cumulatively, and send the cluster off the
    /// screen on the first slow drag.
    @State private var dragOrigin: CGSize?

    private var box: CGRect { ControllerGeometry.bounds(of: controls) }

    /// The unmoved position from the measured layout: a fixed number of button-widths in
    /// from the near edge and up from the bottom.
    private var anchor: CGPoint {
        let inset = ControllerGeometry.centreFromNearEdge * unit
        return CGPoint(
            x: (edge == .leading ? inset : container.width - inset) + anchorOffset.x * unit,
            y: container.height - ControllerGeometry.centreFromBottom * unit + anchorOffset.y * unit
        )
    }

    /// The anchor plus the user's drag, held inside the container so a cluster cannot be
    /// pushed off an edge and become unreachable - including on a rotation that makes the
    /// screen smaller than the offset assumed.
    private var centre: CGPoint {
        clamped(CGPoint(x: anchor.x + CGFloat(offsetX), y: anchor.y + CGFloat(offsetY)))
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        let minX = -box.minX * unit
        let maxX = container.width - box.maxX * unit
        let minY = -box.minY * unit
        let maxY = container.height - box.maxY * unit
        // A cluster wider or taller than the container has no valid range at all; centre
        // it rather than letting min > max produce a nonsense clamp.
        return CGPoint(
            x: minX <= maxX ? min(max(point.x, minX), maxX) : (minX + maxX) / 2,
            y: minY <= maxY ? min(max(point.y, minY), maxY) : (minY + maxY) / 2
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Gives the stack the full proposed size, which is what makes every
            // .position() below an absolute coordinate rather than one relative to
            // whatever the controls happened to add up to.
            //
            // allowsHitTesting(false) is not optional. A SwiftUI Color is hit-testable
            // even when it is clear - unlike a clear UIView - so without this the pad
            // would answer for every touch on the screen and the game underneath would
            // stop receiving any, which is the one property the old stack-based pad had
            // that was worth keeping.
            Color.clear
                .allowsHitTesting(false)

            if isEditingLayout {
                dragHandle
            }

            // Drawn after the cluster's drag handle, so where an element overlaps the
            // handle the element takes the touch. That is what lets one editing mode do
            // both jobs: drag an element to move that element, drag the empty part of the
            // dashed box to move the whole cluster.
            ForEach(controls) { control in
                EditableControl(
                    control: control,
                    skin: skin,
                    unit: unit,
                    base: CGPoint(
                        x: centre.x + control.offset.x * unit,
                        y: centre.y + control.offset.y * unit
                    ),
                    isEditingLayout: isEditingLayout,
                    onStick: onStick,
                    onInput: onInput
                )
            }
        }
    }

    private var dragHandle: some View {
        let width = box.width * unit
        let height = box.height * unit
        let midX = centre.x + box.midX * unit
        let midY = centre.y + box.midY * unit

        return RoundedRectangle(cornerRadius: unit * 0.3, style: .continuous)
            .fill(Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: unit * 0.3, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(0.65),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
            )
            .frame(width: width, height: height)
            .position(x: midX, y: midY)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let origin = dragOrigin ?? CGSize(width: offsetX, height: offsetY)
                        if dragOrigin == nil { dragOrigin = origin }
                        offsetX = origin.width + value.translation.width
                        offsetY = origin.height + value.translation.height
                    }
                    .onEnded { _ in
                        dragOrigin = nil
                        // Write the clamp back into the stored offset. Clamping only at
                        // draw time would let the number keep growing past the edge, and
                        // the next drag would then have to undo all of that slack before
                        // the cluster appeared to move at all.
                        let settled = centre
                        offsetX = Double(settled.x - anchor.x)
                        offsetY = Double(settled.y - anchor.y)
                    }
            )
    }
}

/// One control, placed where the user put it.
///
/// Its own view rather than a modifier chain inside the ForEach because each element needs
/// its own drag origin: reading the live offset every frame would compound DragGesture's
/// cumulative translation and throw the control off the screen on the first slow drag,
/// which is the same trap the cluster handle documents.
private struct EditableControl: View {
    let control: ControllerGeometry.Control
    let skin: WiiUControllerSkin
    let unit: CGFloat
    /// Where this control sits with no customisation - the measured default.
    let base: CGPoint
    let isEditingLayout: Bool
    let onStick: (CGPoint) -> Void
    let onInput: (String, Bool) -> Void

    @ObservedObject private var custom = ControllerCustomLayout.shared
    @State private var dragOrigin: ControlOverride?
    @State private var scaleOrigin: Double?

    private var settings: ControlOverride { custom.override(for: control.id) }

    var body: some View {
        Group {
            if control.style == .joystick {
                JoystickControl(
                    control: control,
                    skin: skin,
                    unit: unit * CGFloat(settings.scale),
                    isInteractive: !isEditingLayout,
                    onStick: onStick,
                    onInput: onInput
                )
            } else {
                ControlButton(
                    control: control,
                    skin: skin,
                    unit: unit * CGFloat(settings.scale),
                    isInteractive: !isEditingLayout,
                    onInput: onInput
                )
            }
        }
        .position(x: base.x + CGFloat(settings.dx), y: base.y + CGFloat(settings.dy))
        // A dashed ring while editing, so it is obvious which things can be moved and
        // that L/ZL and R/ZR answer as one.
        .overlay(
            Group {
                if isEditingLayout {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: unit * CGFloat(settings.scale) * 1.25, height: unit * CGFloat(settings.scale) * 1.25)
                        .position(x: base.x + CGFloat(settings.dx), y: base.y + CGFloat(settings.dy))
                        .allowsHitTesting(false)
                }
            }
        )
        .gesture(isEditingLayout ? editGesture : nil)
    }

    private var editGesture: some Gesture {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = dragOrigin ?? settings
                if dragOrigin == nil { dragOrigin = origin }
                custom.move(control.id, to: value.translation, from: origin)
            }
            .onEnded { _ in dragOrigin = nil }

        let pinch = MagnificationGesture()
            .onChanged { value in
                let origin = scaleOrigin ?? settings.scale
                if scaleOrigin == nil { scaleOrigin = origin }
                custom.setScale(origin * Double(value), for: control.id)
            }
            .onEnded { _ in scaleOrigin = nil }

        // Simultaneous rather than exclusive: a pinch is two fingers moving, and an
        // exclusive pair would let the first finger's travel be read as a drag and shove
        // the control across the screen while it was being resized.
        return SimultaneousGesture(drag, pinch)
    }
}

/// One control, drawn and held.
private struct ControlButton: View {
    let control: ControllerGeometry.Control
    let skin: WiiUControllerSkin
    let unit: CGFloat
    let isInteractive: Bool
    let onInput: (String, Bool) -> Void

    /// The screenshot draws every button light grey with a dark outline. The coloured
    /// skins are an existing feature with a whole selector behind them, so the skin still
    /// colours the d-pad and the four face buttons; the controls the skins have never had
    /// an opinion about - shoulders, plus/minus, stick clicks - take the screenshot's
    /// neutral instead of an invented colour.
    private static let neutralFill = Color(white: 0.85)
    private static let neutralLabel = Color(white: 0.22)

    var body: some View {
        HeldControl(onPressChange: { onInput(control.id, $0) }) { isPressed in
            ZStack {
                shape(isPressed: isPressed)
                Text(control.glyph)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundColor(labelColor)
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(isPressed ? 0.94 : 1.0)
            .animation(.easeInOut(duration: 0.05), value: isPressed)
        }
        .allowsHitTesting(isInteractive)
    }

    private var size: CGSize {
        switch control.shape {
        case .circle(let diameter):
            return CGSize(width: diameter * unit, height: diameter * unit)
        case .roundedRect(let box, _):
            return CGSize(width: box.width * unit, height: box.height * unit)
        }
    }

    @ViewBuilder
    private func shape(isPressed: Bool) -> some View {
        let fill = fillColor.opacity(isPressed ? 1.0 : 0.88)
        let line = max(1, unit * 0.05)

        switch control.shape {
        case .circle:
            Circle()
                .fill(fill)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: line))
        case .roundedRect(_, let radius):
            RoundedRectangle(cornerRadius: radius * unit, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: radius * unit, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.45), lineWidth: line)
                )
        }
    }

    private var fillColor: Color {
        switch control.style {
        case .dpad:
            return skin.dpadColor
        case .face:
            return skin.buttonColors[control.id] ?? Color.gray
        // .joystick never reaches here - ControlCluster routes it to JoystickControl -
        // but Style is exhaustive, and a `default` would silently swallow the next case
        // somebody adds instead of pointing at the three switches that need it.
        case .shoulder, .system, .stick, .joystick:
            return Self.neutralFill
        }
    }

    private var labelColor: Color {
        switch control.style {
        case .dpad, .face:
            return .white
        case .shoulder, .system, .stick, .joystick:
            return Self.neutralLabel
        }
    }

    private var fontSize: CGFloat {
        switch control.style {
        case .dpad:     return unit * 0.32   // filled triangles, not letters
        case .face:     return unit * 0.42
        case .system:   return unit * 0.46   // the glyph is small inside its own advance
        case .stick, .joystick: return unit * 0.30
        case .shoulder: return unit * (control.glyph.count > 1 ? 0.30 : 0.38)
        }
    }
}

/// A control that is held for as long as a finger is on it.
///
/// The pad used to be built out of `Button` + `onLongPressGesture`, which is a tap: it
/// fires once, on release, and there is no way to ask it whether the finger is still
/// down. It also serialises - UIKit's button machinery claims the interaction, so a
/// second finger arriving on a different button while the first is held was simply
/// dropped, and "hold left while pressing A" was not expressible at all.
///
/// `DragGesture(minimumDistance: 0)` fixes both. onChanged arrives on touch-down and
/// onEnded on lift, including a lift that happens outside the view's own bounds, so a
/// press cannot get stuck by sliding a thumb off the edge of a button.
///
/// Attached with `.gesture`, not `.simultaneousGesture`: sibling buttons are not
/// ancestors of one another, so they arbitrate independently and two fingers on two
/// different controls both register.
struct HeldControl<Content: View>: View {
    let onPressChange: (Bool) -> Void
    let content: (Bool) -> Content

    @State private var isPressed = false

    var body: some View {
        content(isPressed)
            // Without this the hit area is whatever the label happens to paint, so a
            // finger landing on the transparent corner of a circular button hits the
            // view behind it instead.
            .contentShape(Rectangle())
            .accessibilityAddTraits(.isButton)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in setPressed(true) }
                    .onEnded { _ in setPressed(false) }
            )
            // A gesture the system cancels (backgrounding, an incoming call) or a view
            // removed mid-press never delivers onEnded, and a button stuck down is a
            // title stuck walking into a wall.
            .onDisappear { setPressed(false) }
    }

    // onChanged repeats for every touch-move, so guard - both to keep the highlight from
    // re-animating and to keep the bridge call one per actual state change.
    private func setPressed(_ value: Bool) {
        guard isPressed != value else { return }
        isPressed = value
        onPressChange(value)
    }
}

/// The stick's gate, as a shape.
///
/// `InsettableShape` rather than plain `Shape` so `.strokeBorder` works on it, which is
/// what the rest of this file uses for outlines: `.stroke` centres the line on the path
/// and spills half its width outside the frame, so an octagon drawn that way would be
/// wider than the circle it is meant to be inscribed in and would not line up with the
/// circular hit area.
///
/// The vertices are at every 45 degrees starting at 0, which puts one on each cardinal
/// and one on each diagonal - the eight directions `StickGate.radiusFraction` returns 1
/// for. Drawing it any other way round would show flats where the full-travel directions
/// are, which is exactly backwards.
private struct StickGateShape: InsettableShape {
    let gate: ControllerGeometry.StickGate
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2 - inset
        guard radius > 0 else { return Path() }

        switch gate {
        case .round:
            return Circle().path(in: CGRect(x: rect.midX - radius, y: rect.midY - radius,
                                            width: radius * 2, height: radius * 2))
        case .octagon:
            var path = Path()
            for corner in 0..<8 {
                let angle = CGFloat(corner) * .pi / 4
                let point = CGPoint(x: rect.midX + cos(angle) * radius,
                                    y: rect.midY + sin(angle) * radius)
                if corner == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
            return path
        }
    }

    func inset(by amount: CGFloat) -> StickGateShape {
        StickGateShape(gate: gate, inset: inset + amount)
    }
}

/// The analog stick, for joystick mode.
///
/// Not a `ControlButton` with extra behaviour: a button reports one bit and a stick
/// reports a position, and the engine keeps the two just as separate. Cemu's VPADRead
/// skips the eight `kButtonId_Stick*_` mappings in its button loop and derives the sticks
/// from `get_axis()` instead, so a direction delivered as a press is not a coarse stick -
/// it is discarded. This is the only control on the pad that talks to
/// `cemu_bridge_set_stick_axis()`.
///
/// Absolute, not relative. The knob goes where the finger is rather than tracking how far
/// it has moved since it landed, so a thumb dropped on the top edge of the ring is full
/// forward immediately - which is how the stick on the real GamePad behaves, and it is
/// also the only version where what is drawn and what the title receives are the same
/// thing. A floating stick that re-centres itself under the finger would show a knob at
/// rest while reporting deflection.
private struct JoystickControl: View {
    let control: ControllerGeometry.Control
    let skin: WiiUControllerSkin
    let unit: CGFloat
    let isInteractive: Bool
    /// Console convention: +x right, +y UP, magnitude at most 1.
    let onStick: (CGPoint) -> Void
    /// L3, for the tap case below.
    let onInput: (String, Bool) -> Void

    // Same keys SettingsView and the move-controls panel write. Read here rather than
    // passed down because they are settings, not layout: a value threaded through
    // OptimizedControlPanel and ControlCluster would be two more places for the default
    // to be restated and disagree.
    @AppStorage(ControllerLayoutSettings.deadzoneKey)
    private var deadzoneSetting = ControllerLayoutSettings.defaultDeadzone
    @AppStorage(ControllerLayoutSettings.stickCurveKey)
    private var curveSetting = ControllerLayoutSettings.defaultStickCurve
    @AppStorage(ControllerLayoutSettings.stickGateKey)
    private var gateSetting = ControllerLayoutSettings.defaultStickGateRaw

    /// Where the knob is drawn, in points from the ring's centre. Already clamped to the
    /// travel radius, so this is also what the axis is derived from - one number, not a
    /// visual one and a reported one that could disagree.
    @State private var knobOffset: CGSize = .zero
    /// Whether this gesture ever pushed the stick, as opposed to resting on it. What
    /// separates a click from a movement, and it is deflection that decides it rather than
    /// distance travelled: a finger that lands directly on the edge of the ring has moved
    /// nowhere and is nonetheless asking for full deflection, so it is not a tap.
    @State private var pushed = false
    /// The pending release of a tap-click, so the view going away cannot leave L3 held.
    @State private var clickRelease: DispatchWorkItem?

    /// Which button a tap on this stick presses, if any.
    ///
    /// Only the left one has a click to give. L3 lost its dot when the knob took the
    /// centre of the left cluster; R3 still has its own, in the middle of A/B/X/Y, so a
    /// tap on the camera stick has nothing to mean and is better off meaning nothing than
    /// firing a second control that is already on screen.
    private var clickButton: String? { control.id == "stickL" ? "L3" : nil }

    /// The settings, held to their declared ranges. UserDefaults is writable by anything
    /// on the device and survives a downgrade, so a value from outside the range the
    /// sliders offer is not impossible - and a deadzone above 1 would be a stick that
    /// never reports anything at all.
    private var deadzone: CGFloat {
        CGFloat(min(max(deadzoneSetting, ControllerLayoutSettings.minDeadzone),
                    ControllerLayoutSettings.maxDeadzone))
    }
    private var curve: CGFloat {
        CGFloat(min(max(curveSetting, ControllerLayoutSettings.minStickCurve),
                    ControllerLayoutSettings.maxStickCurve))
    }
    /// Same defensive read as the two above, for the same reason: a raw string from a
    /// UserDefaults nobody here wrote may name a case that does not exist.
    private var gate: ControllerGeometry.StickGate {
        ControllerGeometry.StickGate(rawValue: gateSetting) ?? ControllerLayoutSettings.defaultStickGate
    }

    /// How long a tap holds L3 before releasing it.
    ///
    /// A press and release in the same instant is not observable: the title polls VPADRead
    /// from its own thread, on its own schedule, and under the forced interpreter that can
    /// be a long way apart. Holding for a few display frames gives the poll somewhere to
    /// land. It is not a guarantee - no transient press on this pad is - which is why the
    /// stick's own axis is held for as long as the finger is down rather than pulsed.
    private static let clickHoldSeconds = 0.12

    private var base: CGFloat { ControllerGeometry.stickBaseDiameter * unit }
    private var knob: CGFloat { ControllerGeometry.stickKnobDiameter * unit }
    private var travel: CGFloat { ControllerGeometry.stickTravel * unit }

    var body: some View {
        ZStack {
            // The gate, drawn as the shape the knob can actually reach. Neutral, like the
            // shoulders and plus/minus: it is not a control the skins have ever had an
            // opinion about.
            //
            // Drawn rather than left as a circle because the flats are the only thing on
            // screen that says where the eight directions are, which on the real GamePad
            // is something the thumb is told by the gate itself. A round ring over an
            // octagonal clamp would also be the one place in this file where what is
            // drawn and what the title receives disagree.
            StickGateShape(gate: gate)
                .fill(Color(white: 0.85).opacity(0.55))
                .overlay(
                    StickGateShape(gate: gate)
                        .strokeBorder(Color.black.opacity(0.45), lineWidth: max(1, unit * 0.05))
                )

            // The cap takes the skin's d-pad colour, because it is what the d-pad became.
            Circle()
                .fill(skin.dpadColor.opacity(pushed ? 1.0 : 0.9))
                .overlay(
                    Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: max(1, unit * 0.05))
                )
                .frame(width: knob, height: knob)
                .offset(knobOffset)
        }
        .frame(width: base, height: base)
        // Circle, not Rectangle, and deliberately the circle rather than the gate. The
        // corners of the frame are outside anything drawn and the d-pad this replaces did
        // not claim them either, so a touch that misses the stick still reaches the game
        // underneath - but the sliver between an octagonal gate and its circumcircle is a
        // thumb aiming at a diagonal and overshooting by a couple of points, and the
        // clamp above already turns that into full deflection at the vertex. Hit-testing
        // the octagon would drop it on the floor instead.
        .contentShape(Circle())
        .accessibilityLabel(clickButton == nil ? "Camera stick" : "Left stick")
        .allowsHitTesting(isInteractive)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // .local by default, so the ring's own centre is half its frame.
                    let dx = value.location.x - base / 2
                    let dy = value.location.y - base / 2
                    let distance = (dx * dx + dy * dy).squareRoot()

                    // How far the gate is in the direction the thumb is holding. Round
                    // returns 1 everywhere and this is the old circular clamp; the
                    // octagon returns less than 1 between its vertices, which is the
                    // whole of what the gate does.
                    let reach = travel * gate.radiusFraction(atAngle: atan2(dy, dx))

                    // Clamped by magnitude along that direction, so the reachable area is
                    // the shape that is drawn rather than the square it is inscribed in -
                    // and so the knob cannot be drawn somewhere the gate does not go.
                    let scale = distance > reach ? reach / distance : 1
                    knobOffset = CGSize(width: dx * scale, height: dy * scale)

                    // Over `travel`, not over `reach`. Dividing by the gate's own radius
                    // would renormalise every direction back to 1 at the flats and undo
                    // the gate entirely - the point of it is that the flats stop short.
                    let deflection = travel > 0 ? min(distance, reach) / travel : 0
                    // The click threshold, not the deadzone. The deadzone is a setting
                    // and can be turned down to nothing, and if this went with it then
                    // every press of the stick would count as a push and L3 would become
                    // unreachable at the setting people who want precision will pick.
                    if deflection > ControllerGeometry.stickClickThreshold {
                        pushed = true
                    }
                    report(deflection: deflection, dx: dx, dy: dy, distance: distance)
                }
                .onEnded { _ in
                    // A press that never deflected the stick is the click. It is the one
                    // gesture a stick has spare, and L3 would otherwise be lost in this
                    // mode - the centre dot it used to live on is where the knob is now.
                    if !pushed { click() }
                    recentre()
                }
        )
        // A gesture the system cancels - backgrounding, an incoming call, the mode being
        // switched off mid-press - never delivers onEnded, and a stick left deflected is
        // worse than a stuck button: the title keeps walking and nothing on screen is lit
        // up to explain why.
        .onDisappear {
            clickRelease?.cancel()
            clickRelease = nil
            if let clickButton { onInput(clickButton, false) }
            recentre()
        }
    }

    private func report(deflection: CGFloat, dx: CGFloat, dy: CGFloat, distance: CGFloat) {
        let dead = deadzone
        // `distance > 0` is not the same test as the deadzone one and does not fold into
        // it: it is what makes the division below safe, and at a deadzone of zero a
        // finger exactly on the centre pixel would otherwise reach it.
        guard deflection > dead, distance > 0 else {
            onStick(.zero)
            return
        }

        // Rescaled across the full range rather than passed through: without this the
        // deadzone would cost the stick its top end as well as its bottom, and a title
        // that expects 1.0 at the rim would never see it. `dead < 1` is guaranteed by the
        // clamp on the setting, so the divisor cannot be zero.
        var magnitude = (deflection - dead) / (1 - dead)

        // The response curve, applied to the magnitude alone and never to the direction.
        // Shaping x and y separately would bend the diagonals - a stick pushed exactly
        // north-east would come back out pointing somewhere else - so the angle the thumb
        // is holding survives untouched and only how hard it is holding it changes.
        // pow() is skipped rather than called with 1.0 because linear is the default and
        // this runs on every touch-move; it is also the exactness the setting promises,
        // and 0.5 raised to the power of exactly 1 is not guaranteed to be 0.5 back.
        if curve != 1 {
            // Through Double rather than relying on a CGFloat overload of pow(). CGFloat
            // is a different width on a 32-bit slice, and this file otherwise only ever
            // uses maths the standard library defines on the protocol.
            magnitude = CGFloat(pow(Double(magnitude), Double(curve)))
        }

        // y is negated exactly here, once. The screen counts downwards and the console
        // counts upwards, and the bridge's contract is the console's.
        onStick(CGPoint(x: dx / distance * magnitude, y: -dy / distance * magnitude))
    }

    private func click() {
        guard let clickButton else { return }
        clickRelease?.cancel()
        onInput(clickButton, true)
        let release = DispatchWorkItem { onInput(clickButton, false) }
        clickRelease = release
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clickHoldSeconds, execute: release)
    }

    private func recentre() {
        pushed = false
        // The axis first, then the animation. A spring is for the person holding the
        // iPad; the title should be told the stick is centred the moment the finger
        // leaves it, not a quarter of a second later once the cap has finished moving.
        onStick(.zero)
        withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) {
            knobOffset = .zero
        }
    }
}
