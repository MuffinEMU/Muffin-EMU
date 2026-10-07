// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import Dispatch

/// The on-screen pad: every control is placed by absolute position from
/// `ControllerGeometry` (measured from the real GamePad), which lets one unit scale the
/// whole pad and lets clusters be dragged. There is no backing plate, and the space
/// between the clusters is not hit-tested, so taps there reach the game view.
struct OptimizedControlPanel: View {
    let skin: WiiUControllerSkin
    // (label, pressed): reports state changes, so a held button stays held.
    let onInput: (String, Bool) -> Void
    /// Analog stick position, reported while held and once as (0, 0) on release. `stick`
    /// is 0 for left, 1 for right; x is right-positive and y is UP-positive (the
    /// console's convention). Sticks are axes in the engine, not buttons.
    let onStick: (Int, CGPoint) -> Void
    /// While on, clusters carry a drag handle and the buttons stop responding, so moving
    /// the pad never presses a button.
    @Binding var isEditingLayout: Bool
    /// True while the title is paused or the app is inactive. The pad stops taking
    /// touches, which cancels and releases anything held.
    var isPaused: Bool = false
    /// Where the top bar (Back, pause, move controls) ends, in window coordinates. The
    /// pad is drawn over that bar, so without this a cluster could be dragged on top of it
    /// and take the buttons that get the player out of edit mode.
    var topInset: CGFloat = 0
    /// Held upright on an iPhone, in the area under the picture: see PortraitPad.swift. Fixed for
    /// the life of the view, because the offsets below are stored under different keys; a turn
    /// builds a new pad (EmulatorViewOptimized.belowPicture is a different branch in each).
    var portrait: Bool = false

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
    @AppStorage(ControllerLayoutSettings.stickSpacingKey)
    private var stickSpacing = ControllerLayoutSettings.defaultStickSpacing
    @AppStorage(ControllerLayoutSettings.shoulderOffsetKey)
    private var shoulderOffset = ControllerLayoutSettings.defaultShoulderOffset
    // The default must match SettingsView's declaration of the same key.
    @AppStorage(ControllerLayoutSettings.comfortControlsKey)
    private var comfortControls = ControllerLayoutSettings.defaultComfortControls
    @AppStorage(ControllerLayoutSettings.joystickKey)
    private var joystickMode = ControllerLayoutSettings.defaultJoystick
    @AppStorage(ControllerLayoutSettings.individualEditModeKey)
    private var individualEditMode = ControllerLayoutSettings.defaultIndividualEditMode

    /// A half's controls as they are laid out in this orientation.
    private func layoutControls(_ controls: [ControllerGeometry.Control]) -> [ControllerGeometry.Control] {
        portrait ? ControllerGeometry.Portrait.cluster(controls) : controls
    }

    init(skin: WiiUControllerSkin,
         onInput: @escaping (String, Bool) -> Void,
         onStick: @escaping (Int, CGPoint) -> Void,
         isEditingLayout: Binding<Bool>,
         isPaused: Bool = false,
         topInset: CGFloat = 0,
         portrait: Bool = false) {
        self.skin = skin
        self.onInput = onInput
        self.onStick = onStick
        self._isEditingLayout = isEditingLayout
        self.isPaused = isPaused
        self.topInset = topInset
        self.portrait = portrait
        // Where each half was dragged to is kept per orientation.
        func key(_ key: String) -> String { portrait ? ControllerLayoutSettings.portraitKey(key) : key }
        _leftOffsetX = AppStorage(wrappedValue: 0.0, key(ControllerLayoutSettings.leftOffsetXKey))
        _leftOffsetY = AppStorage(wrappedValue: 0.0, key(ControllerLayoutSettings.leftOffsetYKey))
        _rightOffsetX = AppStorage(wrappedValue: 0.0, key(ControllerLayoutSettings.rightOffsetXKey))
        _rightOffsetY = AppStorage(wrappedValue: 0.0, key(ControllerLayoutSettings.rightOffsetYKey))
        _rightStickOffsetX = AppStorage(wrappedValue: 0.0, key(ControllerLayoutSettings.rightStickOffsetXKey))
        _rightStickOffsetY = AppStorage(wrappedValue: 0.0, key(ControllerLayoutSettings.rightStickOffsetYKey))
        _leftStickOffsetX = AppStorage(wrappedValue: 0.0, key(ControllerLayoutSettings.leftStickOffsetXKey))
        _leftStickOffsetY = AppStorage(wrappedValue: 0.0, key(ControllerLayoutSettings.leftStickOffsetYKey))
    }

    var body: some View {
        // Re-runs on every size change (rotation, resized scene, external display), so the
        // unit, anchors and drag clamps always follow the size on screen.
        GeometryReader { proxy in
            // Upright, the size is whatever lets both halves fit across, and the slider can only
            // shrink it (see PortraitPad.swift).
            let unit = portrait
                ? ControllerGeometry.Portrait.diameter(in: proxy.size, joystick: joystickMode) * CGFloat(min(userScale, 1))
                : ControllerGeometry.automaticDiameter(in: proxy.size) * CGFloat(userScale)

            // Comfort controls move the shoulder buttons onto the sticks, so it only
            // applies while joystick mode is on. Not upright: there is no room beside the stick.
            let comfortActive = comfortControls && joystickMode && !portrait
            let leftStickControls = comfortActive ? ControllerGeometry.leftStickClusterComfort : ControllerGeometry.leftStickCluster
            let rightStickControls = comfortActive ? ControllerGeometry.rightStickClusterComfort : ControllerGeometry.rightStickCluster
            // The stick-spacing setting, applied to both sticks' starting places (before any
            // drag), so a reset of the drags keeps it and the two sticks always move together.
            let stickShift = portrait ? 0 : ControllerGeometry.stickShift(
                spacing: stickSpacing, containerWidth: proxy.size.width, unit: unit,
                left: leftStickControls, right: rightStickControls)
            // Per-button moves and sizes are measured in the landscape layout, so they are not
            // applied upright.
            let individualEdit = individualEditMode && !portrait
            let leftStickAnchor = portrait ? ControllerGeometry.Portrait.stickAnchorOffset : CGPoint(
                x: ControllerGeometry.leftStickAnchorOffset.x - stickShift,
                y: ControllerGeometry.leftStickAnchorOffset.y)
            let rightStickAnchor = portrait ? ControllerGeometry.Portrait.stickAnchorOffset : CGPoint(
                x: ControllerGeometry.rightStickAnchorOffset.x + stickShift,
                y: ControllerGeometry.rightStickAnchorOffset.y)

            // The shoulder slider is iPad only: on iPhone the stored value is never read.
            let shoulderDrop = ControllerLayoutSettings.effectiveShoulderOffset(shoulderOffset)
            // How much of this view's top the bar covers, in this view's own coordinates.
            let topReserve = max(0, topInset - proxy.frame(in: .global).minY)

            ZStack(alignment: .topLeading) {
                ControlCluster(
                    controls: layoutControls(comfortActive ? ControllerGeometry.leftClusterComfort : ControllerGeometry.leftCluster),
                    edge: .leading,
                    portrait: portrait,
                    skin: skin,
                    unit: unit,
                    shoulderOffset: shoulderDrop,
                    topReserve: topReserve,
                    container: proxy.size,
                    isEditingLayout: isEditingLayout,
                    individualEditMode: individualEdit,
                    offsetX: $leftOffsetX,
                    offsetY: $leftOffsetY,
                    onInput: onInput,
                    // This cluster has no stick; the left stick is its own cluster below.
                    onStick: { onStick(0, $0) }
                )

                // The left stick, in joystick mode only. Its own cluster, with its own
                // drag handle and stored position.
                if joystickMode {
                    ControlCluster(
                        controls: leftStickControls,
                        edge: .leading,
                        portrait: portrait,
                        anchorOffset: leftStickAnchor,
                        skin: skin,
                        unit: unit,
                        shoulderOffset: shoulderDrop,
                        topReserve: topReserve,
                        container: proxy.size,
                        isEditingLayout: isEditingLayout,
                        individualEditMode: individualEdit,
                        offsetX: $leftStickOffsetX,
                        offsetY: $leftStickOffsetY,
                        onInput: onInput,
                        onStick: { onStick(0, $0) }
                    )
                }

                ControlCluster(
                    controls: layoutControls(comfortActive ? ControllerGeometry.rightClusterComfort : ControllerGeometry.rightCluster),
                    edge: .trailing,
                    portrait: portrait,
                    skin: skin,
                    unit: unit,
                    shoulderOffset: shoulderDrop,
                    topReserve: topReserve,
                    container: proxy.size,
                    isEditingLayout: isEditingLayout,
                    individualEditMode: individualEdit,
                    offsetX: $rightOffsetX,
                    offsetY: $rightOffsetY,
                    onInput: onInput,
                    // This cluster has no stick; the camera stick is its own cluster below.
                    onStick: { onStick(1, $0) }
                )

                // The camera stick, in joystick mode only. Its own cluster, like the left stick.
                if joystickMode {
                    ControlCluster(
                        controls: rightStickControls,
                        edge: .trailing,
                        portrait: portrait,
                        anchorOffset: rightStickAnchor,
                        skin: skin,
                        unit: unit,
                        shoulderOffset: shoulderDrop,
                        topReserve: topReserve,
                        container: proxy.size,
                        isEditingLayout: isEditingLayout,
                        individualEditMode: individualEdit,
                        offsetX: $rightStickOffsetX,
                        offsetY: $rightStickOffsetY,
                        onInput: onInput,
                        onStick: { onStick(1, $0) }
                    )
                }
            }
            // Full opacity while editing, regardless of the opacity setting.
            .opacity(isEditingLayout ? 1.0 : max(padOpacity, 0.15))
        }
        // Release is reported from the pad, not per control, so a re-render cannot drop
        // a press: when the whole pad goes away, release everything.
        .onDisappear { cemu_bridge_release_all_buttons() }
        // Cancels any touch in progress while paused or inactive, which releases it.
        .allowsHitTesting(!isPaused)
        // These move controls between clusters, so a held button is rebuilt elsewhere and
        // can't report its release. Release everything.
        .onChange(of: joystickMode) { _ in cemu_bridge_release_all_buttons() }
        .onChange(of: comfortControls) { _ in cemu_bridge_release_all_buttons() }
    }
}

/// One half of the pad, laid out around a single centre point.
private struct ControlCluster: View {
    let controls: [ControllerGeometry.Control]
    let edge: HorizontalEdge
    /// The pad is held upright (PortraitPad.swift): the half is pinned to the bottom corner
    /// at the portrait distances, and the per-button overrides are not applied.
    var portrait: Bool = false
    /// Shifts this cluster's unmoved position, in units, away from the standard anchor -
    /// for a cluster the measured layout has no anchor for. Applied before the user's
    /// drag and before the clamp, so it is genuinely a different starting point rather
    /// than a drag nobody made: "Reset to default" returns here, not to the shared anchor.
    var anchorOffset: CGPoint = .zero
    let skin: WiiUControllerSkin
    let unit: CGFloat
    /// How far this cluster's shoulder buttons (if it has any) move down from their
    /// measured place, in units; already zero on iPhone. See ControllerGeometry.shoulderShift.
    let shoulderOffset: Double
    /// Height at the top of `container` that the top bar covers, in points. Nothing is
    /// placed above it.
    var topReserve: CGFloat = 0
    let container: CGSize
    let isEditingLayout: Bool
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

    private var box: CGRect { ControllerGeometry.bounds(of: controls) }

    /// The unmoved position from the measured layout: a fixed number of button-widths in
    /// from the near edge and up from the bottom.
    private var anchor: CGPoint {
        let inset = (portrait ? ControllerGeometry.Portrait.centreFromNearEdge : ControllerGeometry.centreFromNearEdge) * unit
        let fromBottom = portrait ? ControllerGeometry.Portrait.centreFromBottom : ControllerGeometry.centreFromBottom
        return CGPoint(
            x: (edge == .leading ? inset : container.width - inset) + anchorOffset.x * unit,
            y: container.height - fromBottom * unit + anchorOffset.y * unit
        )
    }

    /// The anchor plus the user's drag, held inside the container so a cluster cannot be
    /// pushed off an edge and become unreachable - including on a rotation that makes the
    /// screen smaller than the offset assumed.
    private var centre: CGPoint {
        clamped(CGPoint(x: anchor.x + CGFloat(offsetX), y: anchor.y + CGFloat(offsetY)))
    }

    /// The shoulders' vertical shift in points, from the setting and the room this
    /// cluster has. Added to where each shoulder is positioned, so its hit area moves too.
    private var shoulderShift: CGFloat {
        ControllerGeometry.shoulderShift(
            offset: shoulderOffset, centreY: centre.y, containerHeight: container.height,
            unit: unit, controls: controls, topInset: topReserve) * unit
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        let minX = -box.minX * unit
        let maxX = container.width - box.maxX * unit
        // The top bar's height comes off the top, so a cluster cannot sit under Back / pause.
        let minY = topReserve - box.minY * unit
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
            // Fills the proposed size so each .position() is an absolute coordinate. Must
            // not be hit-testable, or the pad would swallow every touch meant for the game.
            Color.clear
                .allowsHitTesting(false)

            // Individual mode has no cluster drag handle, so it can't compete with the
            // per-control gestures.
            if isEditingLayout && !individualEditMode {
                dragHandle
            }
            let shoulderDrop = shoulderShift
            ForEach(controls) { control in
                EditableControl(
                    control: control,
                    skin: skin,
                    unit: unit,
                    base: CGPoint(
                        x: centre.x + control.offset.x * unit,
                        y: centre.y + control.offset.y * unit
                            + (control.style == .shoulder ? shoulderDrop : 0)
                    ),
                    container: container,
                    topReserve: topReserve,
                    isEditingLayout: isEditingLayout,
                    individualEditMode: individualEditMode,
                    portrait: portrait,
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
    /// The pad's own size, and the height at its top that the top bar covers. A moved
    /// control is held inside what is left, so it cannot be dragged off the screen or
    /// under the bar and lost.
    let container: CGSize
    let topReserve: CGFloat
    let isEditingLayout: Bool
    /// See ControllerLayoutSettings.individualEditModeKey. editGesture is only attached
    /// when the cluster's own drag handle is not.
    let individualEditMode: Bool
    /// Upright: the per-button moves and sizes are landscape measurements, so they are not applied.
    var portrait: Bool = false
    let onStick: (CGPoint) -> Void
    let onInput: (String, Bool) -> Void

    @ObservedObject private var custom = ControllerCustomLayout.shared
    @State private var dragOrigin: ControlOverride?
    @State private var scaleOrigin: Double?

    private var settings: ControlOverride { portrait ? .identity : custom.override(for: control.id) }

    /// Where the control is drawn and hit: the default place plus the player's move, kept
    /// inside the screen. Held at draw time as well as on drag, so a rotation, a bigger
    /// size or a move saved before this limit existed still lands somewhere reachable.
    private var placed: CGPoint {
        held(CGPoint(x: base.x + CGFloat(settings.dx), y: base.y + CGFloat(settings.dy)))
    }

    private func held(_ point: CGPoint) -> CGPoint {
        let size = ControllerGeometry.size(of: control)
        let halfWidth = size.width * unit * CGFloat(settings.scale) / 2
        let halfHeight = size.height * unit * CGFloat(settings.scale) / 2
        let minX = halfWidth, maxX = container.width - halfWidth
        let minY = topReserve + halfHeight, maxY = container.height - halfHeight
        return CGPoint(
            x: minX <= maxX ? min(max(point.x, minX), maxX) : (minX + maxX) / 2,
            y: minY <= maxY ? min(max(point.y, minY), maxY) : (minY + maxY) / 2
        )
    }

    var body: some View {
        Group {
            if control.style == .joystick {
                JoystickControl(
                    control: control,
                    skin: skin,
                    unit: unit * CGFloat(settings.scale),
                    isInteractive: !isEditingLayout,
                    onStick: onStick
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
        .position(placed)
        // A dashed ring shows which controls can be moved individually.
        .overlay(
            Group {
                if isEditingLayout && individualEditMode {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: unit * CGFloat(settings.scale) * 1.25, height: unit * CGFloat(settings.scale) * 1.25)
                        .position(placed)
                        .allowsHitTesting(false)
                }
            }
        )
        .gesture(isEditingLayout && individualEditMode ? editGesture : nil)
    }

    private var editGesture: some Gesture {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = dragOrigin ?? settings
                if dragOrigin == nil { dragOrigin = origin }
                // Stored as the drag is limited to, not as the finger asked: a finger that
                // goes past the edge would otherwise leave slack the next drag has to undo.
                let wanted = CGPoint(x: base.x + CGFloat(origin.dx) + value.translation.width,
                                     y: base.y + CGFloat(origin.dy) + value.translation.height)
                let limited = held(wanted)
                custom.move(control.id,
                            to: CGSize(width: limited.x - base.x - CGFloat(origin.dx),
                                       height: limited.y - base.y - CGFloat(origin.dy)),
                            from: origin)
            }
            .onEnded { _ in
                dragOrigin = nil
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

        // Simultaneous, so the first finger of a pinch isn't read as a drag.
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

    /// Skins colour the d-pad and face buttons; shoulders, plus/minus and stick clicks
    /// use this neutral.
    private static let neutralFill = Color(white: 0.85)
    private static let neutralLabel = Color(white: 0.22)

    var body: some View {
        HeldControl(onPressChange: { onInput(control.id, $0) }, isInteractive: isInteractive) { isPressed in
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
            // Skins put one glyph colour on every button colour, from navy to lemon, so keep it
            // readable on whichever the skin gave this button.
            return LegibleInk.ensure(.white, on: fillColor, minimum: LegibleInk.glyph)
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
/// Built on `DragGesture(minimumDistance: 0)` rather than `Button`, so a control can be
/// held and several can be held at once with different fingers.
///
/// The press and the lift are reported straight from the gesture's own callbacks. They
/// used to be reported from `.onChange(of: isPressed)`, which only runs when SwiftUI
/// renders: a tap whose touch-down and touch-up were both handled before the next render
/// flipped `isPressed` true and back to false unseen, and nothing was sent at all.
/// A moving finger survived only because it kept the gesture alive across renders.
///
/// `isPressed` (a `@GestureState`, reset by SwiftUI whenever the gesture ends for any
/// reason) is still the safety net for a gesture the system cancels, which never calls
/// `onEnded`. `downSent` only stops a moving finger re-sending "down" on every event;
/// the bridge treats a repeated down as a no-op anyway, and every path that could strand
/// it true also sends the release.
///
/// Release-all lives on the pad's `.onDisappear`, not on each control: a per-control
/// release fired a frame after every press began.
struct HeldControl<Content: View>: View {
    let onPressChange: (Bool) -> Void
    /// Whether this control can be pressed right now. Turning it off cancels a press in
    /// progress, which releases it.
    var isInteractive: Bool = true
    /// The area that takes touches. The whole frame by default, so a finger on the
    /// transparent corner of a round button still presses it.
    var hitShape: HeldControlHitShape = .rectangle
    let content: (Bool) -> Content

    @GestureState private var isPressed = false
    @State private var downSent = false
    /// True once the gesture ended normally, to tell a lift from a cancel in diagnostics.
    @State private var endedNormally = false
    @State private var pressBegan = Date()
    /// The pressed look is kept on screen for at least `minimumLook` after a press, so a tap
    /// whose down and up were both handled before the next render (a busy main thread) is still
    /// seen pressed once. Drawing only: the press and release reach the game as they happen.
    @State private var glowing = false
    private static var minimumLook: TimeInterval { 0.09 }

    @AppStorage(ControllerLayoutSettings.hapticsKey)
    private var hapticsEnabled = ControllerLayoutSettings.defaultHaptics

    var body: some View {
        content(isPressed || downSent || glowing)
            .contentShape(hitShape)
            .accessibilityAddTraits(.isButton)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in state = true }
                    .onChanged { _ in
                        PadDiagnostics.shared.recordRawTouch()
                        if !downSent {
                            downSent = true
                            report(true)
                        }
                    }
                    .onEnded { _ in
                        endedNormally = true
                        release()
                    }
            )
            // The system cancelled the gesture (no onEnded).
            .onChange(of: isPressed) { pressed in
                if !pressed { release() }
            }
            // A cancel that landed before the first render after the press: isPressed
            // went true and back to false unseen, so the handler above never ran.
            .onChange(of: downSent) { sent in
                if sent && !isPressed { release() }
            }
            .allowsHitTesting(isInteractive)
    }

    private func release() {
        guard downSent else { return }
        downSent = false
        report(false)
    }

    // Report first, then diagnostics, then haptics: nothing may sit between the state
    // change and the report.
    private func report(_ pressed: Bool) {
        let began = pressBegan
        if pressed { pressBegan = Date(); endedNormally = false; glowing = true }
        onPressChange(pressed)
        if pressed {
            PadDiagnostics.shared.recordPressBegan()
        } else {
            let reason: PadDiagnostics.ReleaseReason =
                !isInteractive ? .stoppedAcceptingTouches
                : (endedNormally ? .fingerLifted : .gestureCancelled)
            PadDiagnostics.shared.recordRelease(reason, heldSince: began)
        }
        if pressed, hapticsEnabled { PadHaptics.shared.fire() }
        if !pressed {
            let remaining = Self.minimumLook - Date().timeIntervalSince(pressBegan)
            if remaining > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { glowing = false }
            } else {
                glowing = false
            }
        }
    }
}

/// The touch area of a `HeldControl`, in its own frame.
enum HeldControlHitShape: Shape {
    case rectangle
    /// A circle centred in the frame, with this diameter as a fraction of the frame's
    /// shorter side - for a control that has to leave the space around it to a neighbour.
    case circle(fraction: CGFloat)

    func path(in rect: CGRect) -> Path {
        switch self {
        case .rectangle:
            return Path(rect)
        case .circle(let fraction):
            let d = min(rect.width, rect.height) * fraction
            return Path(ellipseIn: CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d))
        }
    }
}

/// One shared impact generator for the whole pad, prepared once rather than allocated
/// fresh on every press. UIImpactFeedbackGenerator is meant to be created ahead of the
/// impact and prepare()d so the Taptic Engine is already spun up when impactOccurred() is
/// called.
///
/// @MainActor because UIImpactFeedbackGenerator is a UIKit class and main-thread-only.
/// It was not isolated before, and it was being called from a gesture callback in the
/// middle of the press path - see setPressed's comment for what that cost.
@MainActor
final class PadHaptics {
    static let shared = PadHaptics()

    #if canImport(UIKit)
    private let generator = UIImpactFeedbackGenerator(style: .rigid)

    private init() { generator.prepare() }

    func fire() {
        generator.impactOccurred()
        // Re-prime immediately rather than waiting for the next press: the Taptic Engine
        // is allowed to spin back down after it has been idle, and a pad fires presses far
        // more often than it sits still.
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
/// A stick reports a position, not a bit: Cemu derives the sticks from `get_axis()` and
/// skips them in its button loop, so this is the only control that calls
/// `cemu_bridge_set_stick_axis()`. It is absolute: the knob goes where the finger is.
private struct JoystickControl: View {
    let control: ControllerGeometry.Control
    let skin: WiiUControllerSkin
    let unit: CGFloat
    let isInteractive: Bool
    /// Console convention: +x right, +y UP, magnitude at most 1.
    let onStick: (CGPoint) -> Void

    // Same keys SettingsView writes; read here so the defaults live in one place.
    @AppStorage(ControllerLayoutSettings.deadzoneKey)
    private var deadzoneSetting = ControllerLayoutSettings.defaultDeadzone
    @AppStorage(ControllerLayoutSettings.stickCurveKey)
    private var curveSetting = ControllerLayoutSettings.defaultStickCurve
    @AppStorage(ControllerLayoutSettings.stickGateKey)
    private var gateSetting = ControllerLayoutSettings.defaultStickGateRaw

    /// Where the knob is drawn, in points from the ring's centre, clamped to the gate.
    @State private var knobOffset: CGSize = .zero
    /// True while a finger is on the stick. Resets if the system cancels the gesture, so
    /// the stick always recentres.
    @GestureState private var touching = false
    /// Whether the stick has been pushed past the click threshold; lights the cap.
    @State private var pushed = false

    /// The settings, clamped to their declared ranges (a stored value can be out of range).
    private var deadzone: CGFloat {
        CGFloat(min(max(deadzoneSetting, ControllerLayoutSettings.minDeadzone),
                    ControllerLayoutSettings.maxDeadzone))
    }
    private var curve: CGFloat {
        CGFloat(min(max(curveSetting, ControllerLayoutSettings.minStickCurve),
                    ControllerLayoutSettings.maxStickCurve))
    }
    /// Falls back to the default if the stored string names no gate.
    private var gate: ControllerGeometry.StickGate {
        ControllerGeometry.StickGate(rawValue: gateSetting) ?? ControllerLayoutSettings.defaultStickGate
    }

    private var base: CGFloat { ControllerGeometry.stickBaseDiameter * unit }
    private var knob: CGFloat { ControllerGeometry.stickKnobDiameter * unit }
    private var travel: CGFloat { ControllerGeometry.stickTravel(ringDiameter: base) }

    var body: some View {
        ZStack {
            // The gate, drawn as the shape the knob can reach.
            StickGateShape(gate: gate)
                .fill(Color(white: 0.85).opacity(0.55))
                .overlay(
                    StickGateShape(gate: gate)
                        .strokeBorder(Color.black.opacity(0.45), lineWidth: max(1, unit * 0.05))
                )

            // The cap uses the skin's d-pad colour.
            Circle()
                .fill(skin.dpadColor.opacity(pushed ? 1.0 : 0.9))
                .overlay(
                    Circle().strokeBorder(Color.black.opacity(0.45), lineWidth: max(1, unit * 0.05))
                )
                .frame(width: knob, height: knob)
                .offset(knobOffset)
        }
        .frame(width: base, height: base)
        // The hit area is the circle, not the octagonal gate, so a thumb overshooting a
        // diagonal still counts.
        .contentShape(Circle())
        .accessibilityLabel(control.id == "stickL" ? "Left stick" : "Camera stick")
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($touching) { _, state, _ in state = true }
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
                // Recentre on the lift itself, not only when `touching` is next seen false
                // at a render: a flick handled entirely between two renders never shows
                // `touching` as true, and left the stick deflected.
                .onEnded { _ in recentre() }
        )
        .allowsHitTesting(isInteractive)
        .onChange(of: touching) { down in
            if !down { recentre() }
        }
        // A system cancel handled before a render has the same blind spot, and no onEnded.
        .onChange(of: knobOffset) { offset in
            if offset != .zero && !touching { recentre() }
        }
        .onChange(of: isInteractive) { active in
            if !active { recentre() }
        }
        // The stick's own view going away must not leave the axis deflected.
        .onDisappear { recentre() }
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
