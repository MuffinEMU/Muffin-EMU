import SwiftUI
import Dispatch
#if canImport(UIKit)
import UIKit
#endif

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
    /// True whenever the app is not in .active scenePhase - see EmulatorViewOptimized's
    /// .onChange(of: scenePhase). Threaded down to DpadTouchSurface's own isInteractive,
    /// which is the one thing that reliably clears its held-direction state: a touch in
    /// progress when the app resigns active is cancelled by UIKit without a guaranteed
    /// .onEnded (the same fact cemu_bridge_release_all_buttons()'s call site documents),
    /// so without this, a direction held at the moment of an interruption - a phone call,
    /// a notification banner, Control Center, a screen lock - stays stuck in the SwiftUI
    /// pressed-state (and keeps being reported to the game) even though the bridge's own
    /// button bits were correctly zeroed. Every other button on the pad has its own
    /// per-control HeldControl safety net for the same case; the d-pad's shared touch
    /// surface needed this one explicitly since it owns all four directions' state itself.
    let isPaused: Bool

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
    @AppStorage(ControllerLayoutSettings.leftStickOffsetXKey) private var leftStickOffsetX = 0.0
    @AppStorage(ControllerLayoutSettings.leftStickOffsetYKey) private var leftStickOffsetY = 0.0
    // Must keep matching SettingsView's declaration of the same key: two @AppStorage
    // defaults for one key that disagree means the toggle and the pad disagree about
    // which control scheme is on.
    @AppStorage(ControllerLayoutSettings.joystickKey)
    private var joystickMode = ControllerLayoutSettings.defaultJoystick
    @AppStorage(ControllerLayoutSettings.comfortControlsKey)
    private var comfortControls = ControllerLayoutSettings.defaultComfortControls
    @AppStorage(ControllerLayoutSettings.individualEditModeKey)
    private var individualEditMode = ControllerLayoutSettings.defaultIndividualEditMode

    var body: some View {
        // The automatic half of "adjustable + automatic sizing": GeometryReader re-runs
        // on every size change the pad can experience - rotation, a resized scene, an
        // external display being attached - so the unit, both anchors and the drag
        // clamps are all recomputed from the size that is actually on screen rather
        // than from anything cached at launch.
        GeometryReader { proxy in
            let unit = ControllerGeometry.automaticDiameter(in: proxy.size) * CGFloat(userScale)

            // Anchors and clamps below used to be built from proxy.size alone, which is the
            // full bounds of the view including the unsafe strip - so in landscape a cluster
            // anchored "in from the near edge" of that raw rect sat partly under the Dynamic
            // Island, and on a notched iPhone the bottom anchor crowded the home indicator.
            // GamePadGeometry's PadLayout.resolve hits the same problem and solves it the
            // same way: inset the rect the layout is measured against, once, before anything
            // downstream reads it. CGRect has no .inset(by:) that takes SwiftUI's own
            // EdgeInsets (only UIKit's UIEdgeInsets, a different type), so it is built by
            // hand rather than reached for an extension that does not apply here.
            let insets = proxy.safeAreaInsets
            let safeArea = CGRect(x: insets.leading, y: insets.top,
                                  width: proxy.size.width - insets.leading - insets.trailing,
                                  height: proxy.size.height - insets.top - insets.bottom)

            // Comfort controls only has somewhere to send L/ZL/minus and R/ZR/plus while
            // the sticks they are moving to are actually on screen - with joystick mode
            // off there is no stick cluster here for them to join, so this only takes
            // effect with both settings on rather than making the toggle silently do
            // nothing (or worse, dropping three buttons) whenever joystick mode is off.
            let comfortActive = comfortControls && joystickMode

            ZStack(alignment: .topLeading) {
                ControlCluster(
                    // Always the d-pad now, in both modes - see leftStickCluster's
                    // comment for why this changed from swapping to adding. Comfort
                    // controls trims L/ZL/minus back out of it; see leftClusterComfort.
                    controls: comfortActive ? ControllerGeometry.leftClusterComfort : ControllerGeometry.leftCluster,
                    edge: .leading,
                    skin: skin,
                    unit: unit,
                    container: safeArea,
                    isEditingLayout: isEditingLayout,
                    isPaused: isPaused,
                    individualEditMode: individualEditMode,
                    offsetX: $leftOffsetX,
                    offsetY: $leftOffsetY,
                    onInput: onInput,
                    // The left half itself has no stick: its centre dot is L3, as the
                    // measured layout draws it, and the left stick below is its own
                    // cluster - same reasoning as the right half's onStick below.
                    onStick: { onStick(0, $0) }
                )

                // The left stick, in joystick mode only - mirrors the camera stick
                // below exactly. A separate cluster, so it has its own drag handle and
                // its own stored position: the left half (d-pad, minus, L, ZL) stays
                // exactly where the measurements put it, and turning the mode on adds
                // a control rather than rearranging the ones already there.
                if joystickMode {
                    ControlCluster(
                        // Comfort controls adds L/ZL/minus onto this cluster - see
                        // leftStickClusterComfort - so dragging or resizing the stick
                        // moves them with it, the same way L/ZL/minus already travel
                        // with the d-pad above.
                        controls: comfortActive ? ControllerGeometry.leftStickClusterComfort : ControllerGeometry.leftStickCluster,
                        edge: .leading,
                        anchorOffset: ControllerGeometry.leftStickAnchorOffset,
                        skin: skin,
                        unit: unit,
                        container: safeArea,
                        isEditingLayout: isEditingLayout,
                        isPaused: isPaused,
                        individualEditMode: individualEditMode,
                        offsetX: $leftStickOffsetX,
                        offsetY: $leftStickOffsetY,
                        onInput: onInput,
                        onStick: { onStick(0, $0) }
                    )
                }

                ControlCluster(
                    // Comfort controls trims R/ZR/plus back out of it; see
                    // rightClusterComfort.
                    controls: comfortActive ? ControllerGeometry.rightClusterComfort : ControllerGeometry.rightCluster,
                    edge: .trailing,
                    skin: skin,
                    unit: unit,
                    container: safeArea,
                    isEditingLayout: isEditingLayout,
                    isPaused: isPaused,
                    individualEditMode: individualEditMode,
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
                        // Comfort controls adds R/ZR/plus onto this cluster - see
                        // rightStickClusterComfort - for the same reason the left stick
                        // picks up L/ZL/minus above.
                        controls: comfortActive ? ControllerGeometry.rightStickClusterComfort : ControllerGeometry.rightStickCluster,
                        edge: .trailing,
                        anchorOffset: ControllerGeometry.rightStickAnchorOffset,
                        skin: skin,
                        unit: unit,
                        container: safeArea,
                        isEditingLayout: isEditingLayout,
                        isPaused: isPaused,
                        individualEditMode: individualEditMode,
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
    /// The safe area, not the raw GeometryReader size - see OptimizedControlPanel.body.
    /// Everything below measures from this rect's edges rather than from (0, 0) and
    /// proxy.size, so a cluster's near-edge anchor and its drag clamp both stay inside the
    /// safe area instead of reaching under a notch or behind the home indicator.
    let container: CGRect
    let isEditingLayout: Bool
    /// See OptimizedControlPanel's own doc comment on this property - passed straight
    /// through to DpadTouchSurface below, which is the only thing here that needs it.
    let isPaused: Bool
    /// See ControllerLayoutSettings.individualEditModeKey. When true, this cluster's
    /// own drag handle below is not attached at all - every touch inside the cluster
    /// can then only ever be a single button's own drag/pinch, with no whole-cluster
    /// gesture left for it to compete against.
    let individualEditMode: Bool
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

    /// Which of this cluster's own four directions DpadTouchSurface currently has down -
    /// lifted up to here, rather than kept inside the surface itself, because the four
    /// direction ControlButtons below also need it, to draw the pressed state a touch on
    /// the surface now stands for instead of one on the button itself.
    @State private var dpadHeld: Set<String> = []

    /// The ids DpadTouchSurface owns. A cluster with a d-pad in it (leftCluster,
    /// leftClusterComfort) has all four; a stick cluster or the face-button half has none.
    private static let directionIDs: Set<String> = ["up", "down", "left", "right"]

    private var box: CGRect { ControllerGeometry.bounds(of: controls) }

    /// This cluster's own four direction Controls, if it has any - what DpadTouchSurface
    /// hit-tests against. Filtered from `controls` rather than assumed, so a cluster with
    /// no d-pad in it (either stick cluster, the face-button half) simply gets no surface.
    private var dpadControls: [ControllerGeometry.Control] {
        controls.filter { Self.directionIDs.contains($0.id) }
    }

    /// The unmoved position from the measured layout: a fixed number of button-widths in
    /// from the near edge and up from the bottom.
    private var anchor: CGPoint {
        let inset = ControllerGeometry.centreFromNearEdge * unit
        return CGPoint(
            x: (edge == .leading ? container.minX + inset : container.maxX - inset) + anchorOffset.x * unit,
            y: container.maxY - ControllerGeometry.centreFromBottom * unit + anchorOffset.y * unit
        )
    }

    /// The anchor plus the user's drag, held inside the container so a cluster cannot be
    /// pushed off an edge and become unreachable - including on a rotation that makes the
    /// screen smaller than the offset assumed.
    private var centre: CGPoint {
        clamped(CGPoint(x: anchor.x + CGFloat(offsetX), y: anchor.y + CGFloat(offsetY)))
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        let minX = container.minX - box.minX * unit
        let maxX = container.maxX - box.maxX * unit
        let minY = container.minY - box.minY * unit
        let maxY = container.maxY - box.maxY * unit
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

            // The d-pad's four directions, hit-tested as one shape instead of as four
            // separate buttons - see DpadTouchSurface for why. Sits behind everything
            // else here, L3 included: L3 keeps its own small hit square exactly as it
            // was and claims a touch there before this surface ever sees it, the same
            // way Color.clear's allowsHitTesting(false) above lets the game view claim
            // whatever is not on the pad at all.
            if !dpadControls.isEmpty {
                DpadTouchSurface(
                    box: ControllerGeometry.bounds(of: dpadControls),
                    centre: centre,
                    unit: unit,
                    // isPaused, not just isEditingLayout: see OptimizedControlPanel's
                    // doc comment on isPaused for why the app resigning active needs to
                    // reach this the same way editing does.
                    isInteractive: !isEditingLayout && !isPaused,
                    onInput: onInput,
                    held: $dpadHeld
                )
            }

            // Individual mode drops the drag handle entirely rather than leaving it
            // underneath and relying on touch position to sort out which gesture
            // should win - that was the old design (see the ForEach comment this one
            // replaces) and it did not resolve the way it looked like it should
            // on-device: a drag anywhere in the cluster moved the whole cluster,
            // individual buttons included, every time.
            if isEditingLayout && !individualEditMode {
                dragHandle
            }
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
                    individualEditMode: individualEditMode,
                    onStick: onStick,
                    onInput: onInput,
                    // Only the four directions are driven by DpadTouchSurface above -
                    // every other control, L3 included, still answers for its own touch
                    // exactly as before, so this is nil for all of them.
                    externallyPressed: Self.directionIDs.contains(control.id) ? dpadHeld.contains(control.id) : nil
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

/// One shared touch surface for the d-pad's four directions, replacing four separate
/// per-button gestures.
///
/// Real d-pad play rolls a thumb across the cross - up sliding into right, or straight
/// through a diagonal - but a SwiftUI touch belongs to whichever view it began in for the
/// whole gesture and never hands off. Four separate `HeldControl`s, each claiming its own
/// touch the moment it lands, means a roll leaves the first direction stuck down and the
/// second never presses. `GamePadGeometry.PadLayout.dpadDirections` already solves exactly
/// this for the preview pad, by hit-testing the cross as one shape, by angle, instead of
/// as four rects that happen to meet at a point - this calls that same function rather
/// than reimplementing it, so the two pads can never disagree about what a given touch
/// means. What is new here is only the geometry it is called with: the preview pad's d-pad
/// is one solid cross, and this one is a diamond of four separate circles, so `box` is the
/// union of their frames rather than a shape GamePadGeometry already had a size for.
///
/// Sits behind everything else in ControlCluster's stack, including L3. Only the four
/// direction ControlButtons are made non-hit-testable (see EditableControl and
/// ControlButton's `externallyPressed`) so this surface is what actually receives their
/// touches; L3 is untouched and keeps its own small hit square, which is why it still
/// claims a tap there before a touch ever reaches this surface underneath it - the same
/// front-wins-if-hit-testable rule that already lets ControlCluster's own `Color.clear`
/// hand off everything outside the pad to the game view.
private struct DpadTouchSurface: View {
    /// The union of the four direction buttons' own frames, in layout units relative to
    /// the cluster's centre - `ControllerGeometry.bounds(of:)` applied to just those four
    /// Controls, not the whole cluster, so the touchable area cannot grow into a
    /// neighbour (minus, L, ZL) the way hit-testing the whole cluster's box would.
    let box: CGRect
    /// The cluster's own centre point, in the same absolute space every other control in
    /// it is positioned from.
    let centre: CGPoint
    let unit: CGFloat
    let isInteractive: Bool
    let onInput: (String, Bool) -> Void
    /// Which directions are currently down - lifted up into ControlCluster (see its own
    /// `dpadHeld`) rather than kept private here, since the four ControlButtons need it
    /// too, to draw the pressed state a touch on this surface now stands for.
    @Binding var held: Set<String>

    @AppStorage(ControllerLayoutSettings.hapticsKey)
    private var hapticsEnabled = ControllerLayoutSettings.defaultHaptics

    private var width: CGFloat { box.width * unit }
    private var height: CGFloat { box.height * unit }

    var body: some View {
        // A SwiftUI Color is hit-testable even when it is clear - the same fact
        // ControlCluster's own background relies on - which is what makes it usable here
        // as a shape with nothing to draw.
        Color.clear
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .position(x: centre.x + box.midX * unit, y: centre.y + box.midY * unit)
            .allowsHitTesting(isInteractive)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // In this view's own local space - (0, 0) at its top-left corner,
                        // (width, height) at its bottom-right - which is unaffected by
                        // .position() above and needs no translation back to the
                        // cluster's coordinate space at all.
                        let local = CGPoint(x: width / 2, y: height / 2)
                        let next = PadLayout.dpadDirections(at: value.location, centre: local,
                                                            size: CGSize(width: width, height: height))
                        for id in held.subtracting(next) { onInput(id, false) }
                        for id in next.subtracting(held) {
                            // Once per newly pressed direction, not on every tick this
                            // onChanged fires while a direction is already held - the
                            // same "only on the transition" rule HeldControl's own
                            // setPressed applies for every other control on the pad.
                            if hapticsEnabled { PadHaptics.shared.fire() }
                            onInput(id, true)
                        }
                        held = next
                    }
                    .onEnded { _ in release() }
            )
            // The same safety net HeldControl keeps for every other control: a gesture
            // the system cancels, or this view disappearing mid-touch, must not leave a
            // direction stuck down forever.
            .onDisappear { release() }
            .onChange(of: isInteractive) { active in
                if !active { release() }
            }
            // A giant unlabelled rectangle would otherwise sit in the accessibility tree
            // on top of the four direction buttons it draws nothing over; hiding it
            // leaves VoiceOver exactly the four ControlButtons below, unchanged.
            .accessibilityHidden(true)
    }

    private func release() {
        for id in held { onInput(id, false) }
        held = []
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
    /// See ControllerLayoutSettings.individualEditModeKey - gates editGesture below so
    /// it is only ever attached when the cluster's own drag handle (ControlCluster)
    /// is not, rather than both being attached together and left to sort out priority
    /// by touch position.
    let individualEditMode: Bool
    let onStick: (CGPoint) -> Void
    let onInput: (String, Bool) -> Void
    /// Set only for one of the d-pad's four directions, by DpadTouchSurface's own held
    /// set - see ControlButton and HeldControl's own doc comments for what this changes.
    /// nil for every other control, which is unaffected.
    var externallyPressed: Bool? = nil

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
                    onInput: onInput,
                    externallyPressed: externallyPressed
                )
            }
        }
        .position(x: base.x + CGFloat(settings.dx), y: base.y + CGFloat(settings.dy))
        // A dashed ring while editing individually, so it is obvious which things can
        // be moved and that L/ZL and R/ZR answer as one - shown only in individual
        // mode, since in grouped mode this control cannot be moved on its own.
        .overlay(
            Group {
                if isEditingLayout && individualEditMode {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: unit * CGFloat(settings.scale) * 1.25, height: unit * CGFloat(settings.scale) * 1.25)
                        .position(x: base.x + CGFloat(settings.dx), y: base.y + CGFloat(settings.dy))
                        .allowsHitTesting(false)
                }
            }
        )
        .gesture(isEditingLayout && individualEditMode ? editGesture : nil)
        // If this view goes away mid-gesture - individual edit mode toggled off, the
        // cluster it belongs to changing under comfort mode - the gesture's own onEnded
        // never runs, and whatever custom.move/setScale wrote this drag is only in memory
        // (see ControllerCustomLayout.write). Committing here as well is the same safety
        // net HeldControl's onDisappear already is for a stuck button, applied to a drag
        // that would otherwise be silently lost the next time the app quits.
        .onDisappear {
            if dragOrigin != nil || scaleOrigin != nil { custom.commit() }
            dragOrigin = nil
            scaleOrigin = nil
        }
    }

    private var editGesture: some Gesture {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = dragOrigin ?? settings
                if dragOrigin == nil { dragOrigin = origin }
                custom.move(control.id, to: value.translation, from: origin)
            }
            .onEnded { _ in
                dragOrigin = nil
                // custom.move only kept this drag in memory - see
                // ControllerCustomLayout.write - so the finger lifting is what writes it
                // to disk, once, instead of on every touch-move.
                custom.commit()
            }

        let pinch = MagnificationGesture()
            .onChanged { value in
                let origin = scaleOrigin ?? settings.scale
                if scaleOrigin == nil { scaleOrigin = origin }
                custom.setScale(origin * Double(value), for: control.id)
            }
            .onEnded { _ in
                scaleOrigin = nil
                custom.commit()
            }

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
    /// Non-nil for one of the d-pad's four directions once DpadTouchSurface owns their
    /// input: the pressed state this button draws, decided by that surface's own angle
    /// hit test rather than by a gesture attached here. nil - every other control on the
    /// pad - is unchanged: HeldControl still owns its own touch and its own pressed state.
    var externallyPressed: Bool? = nil

    /// The screenshot draws every button light grey with a dark outline. The coloured
    /// skins are an existing feature with a whole selector behind them, so the skin still
    /// colours the d-pad and the four face buttons; the controls the skins have never had
    /// an opinion about - shoulders, plus/minus, stick clicks - take the screenshot's
    /// neutral instead of an invented colour.
    private static let neutralFill = Color(white: 0.85)
    private static let neutralLabel = Color(white: 0.22)

    var body: some View {
        // L3/R3 alone get a hit region that matches the dot actually drawn - see
        // HeldControl's own doc comment on circularHitTarget for why every other
        // control keeps the generous square.
        HeldControl(onPressChange: { onInput(control.id, $0) }, isInteractive: isInteractive,
                    externallyPressed: externallyPressed,
                    circularHitTarget: control.style == .stick) { isPressed in
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
        // Externally driven means DpadTouchSurface, not this button, answers for the
        // touch - false here regardless of isInteractive, so edit mode still disables it
        // the same way it always has and play mode routes the touch to the surface
        // instead of back to this button.
        .allowsHitTesting(externallyPressed == nil && isInteractive)
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
    /// Whether this control can be pressed right now - the same flag the call site already
    /// hands to its own `.allowsHitTesting`. Watched here too, and not left to that modifier
    /// alone: turning hit-testing off does not retroactively end a drag already in
    /// progress, so nothing else resets `isPressed` when, say, edit mode switches on
    /// mid-press - and a button that is still drawn highlighted but can no longer be
    /// touched to release it is stuck exactly the way a jammed physical button would be.
    let isInteractive: Bool
    /// Non-nil when something other than this view's own gesture below decides the
    /// pressed state - DpadTouchSurface, for the d-pad's four directions. Drawing still
    /// goes through here, so every control on the pad keeps one pressed-state code path,
    /// but this view attaches no gesture of its own and never calls `onPressChange` in
    /// that case: the surface calls `onInput` directly instead. `nil`, every other
    /// control, is this type entirely unchanged from before.
    var externallyPressed: Bool? = nil

    /// True only for L3/R3. Every other round button on the pad wants the generous
    /// square below - a bigger, more forgiving target with nothing else contending
    /// for the corners it adds. L3 is different: DpadTouchSurface sits directly
    /// underneath it and hit-tests continuously, by angle, right up to (and past)
    /// L3's own radius, so a diagonal - or even a near-centre cardinal - press that
    /// lands in the square's corners (real distance up to ~0.50 units from centre,
    /// verified against dpadDirections' own 0.18 deadzone, which clears at ~0.30) was
    /// being claimed by L3 instead of ever reaching the surface: the dot fired a
    /// stick click nobody asked for, and the direction it should have registered
    /// never did. Circle here is not a smaller target for its own sake, it is the
    /// square giving back exactly the area it was never visually part of.
    var circularHitTarget: Bool = false
    let content: (Bool) -> Content

    @State private var isPressed = false

    @AppStorage(ControllerLayoutSettings.hapticsKey)
    private var hapticsEnabled = ControllerLayoutSettings.defaultHaptics

    var body: some View {
        hitTestable(content(externallyPressed ?? isPressed))
            .accessibilityAddTraits(.isButton)
            .gesture(externallyPressed == nil ? ownGesture : nil)
            // A gesture the system cancels (backgrounding, an incoming call) or a view
            // removed mid-press never delivers onEnded, and a button stuck down is a
            // title stuck walking into a wall. Skipped when externally driven: isPressed
            // never left false in that case (the gesture that would have set it true was
            // never attached above), so there is nothing here for it to undo, and
            // DpadTouchSurface has its own version of this same safety net.
            .onDisappear {
                if externallyPressed == nil { setPressed(false) }
            }
            .onChange(of: isInteractive) { active in
                if externallyPressed == nil, !active { setPressed(false) }
            }
    }

    private var ownGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in setPressed(true) }
            .onEnded { _ in setPressed(false) }
    }

    /// Without a content shape at all, the hit area is whatever the label happens to
    /// paint, so a finger landing on the transparent corner of a circular button hits
    /// the view behind it instead. Rectangle is the right default for that - a bigger,
    /// forgiving target - everywhere except L3/R3; see circularHitTarget above.
    @ViewBuilder
    private func hitTestable<V: View>(_ view: V) -> some View {
        if circularHitTarget {
            view.contentShape(Circle())
        } else {
            view.contentShape(Rectangle())
        }
    }

    // onChanged repeats for every touch-move, so guard - both to keep the highlight from
    // re-animating and to keep the bridge call one per actual state change.
    private func setPressed(_ value: Bool) {
        guard isPressed != value else { return }
        isPressed = value
        if value, hapticsEnabled { PadHaptics.shared.fire() }
        onPressChange(value)
    }
}

/// One shared impact generator for the whole pad, prepared once rather than allocated fresh
/// on every press. `UIImpactFeedbackGenerator` is meant to be created ahead of the impact
/// and `prepare()`d so the Taptic Engine is already spun up when `impactOccurred()` is
/// called - a generator built fresh per tap would pay that latency on every single input,
/// which on a d-pad held during normal play is dozens of times a second.
final class PadHaptics {
    static let shared = PadHaptics()

    #if canImport(UIKit)
    private let generator = UIImpactFeedbackGenerator(style: .rigid)

    private init() { generator.prepare() }

    func fire() {
        generator.impactOccurred()
        // Re-prime immediately rather than waiting for the next press to ask for it: the
        // Taptic Engine is allowed to spin back down after it has been idle, and a pad
        // fires presses far more often than it sits still, so priming eagerly is the
        // common case, not the wasted one.
        generator.prepare()
    }
    #else
    private init() {}
    func fire() {}
    #endif
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
    @AppStorage(ControllerLayoutSettings.hapticsKey)
    private var hapticsEnabled = ControllerLayoutSettings.defaultHaptics

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
    /// Neither one has a click to give anymore. This used to be "stickL" -> "L3": when
    /// joystick mode replaced the whole d-pad cluster (including its centre L3 dot)
    /// with the stick, a tap-without-moving was the only gesture left to mean L3. Now
    /// the d-pad cluster - L3's own dot included - is always present alongside the
    /// stick, same as A/B/X/Y and R3 always were, so a tap on either stick has nothing
    /// left to mean and is better off meaning nothing than firing a second control
    /// that is already on screen.
    private var clickButton: String? { nil }

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
        // clickButton is nil for both sticks now (see its own doc comment above), so it
        // cannot tell VoiceOver which stick this is - that always read "Camera stick",
        // left and right alike. control.id can: it is "stickL" or "stickR" for every
        // instance ControllerGeometry actually creates.
        .accessibilityLabel(control.id == "stickL" ? "Left stick" : "Right stick")
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
        if hapticsEnabled { PadHaptics.shared.fire() }
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
