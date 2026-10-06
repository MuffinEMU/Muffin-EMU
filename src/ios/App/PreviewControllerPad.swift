import SwiftUI
import Dispatch

extension Color {
    /// MuffinColourPresets' colours are plain RGBA (so a .muffinclr stays hand-editable
    /// JSON, not a SwiftUI-specific format), so this is the one place that turns one into
    /// something a View can actually paint.
    init(_ rgba: MuffinRGBA) {
        self.init(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }
}

/// The showcase pad: every control positioned from `PreviewPadStore.resolve(...)` -
/// GamePadGeometry's hardware-measured geometry, PadPresetFitter's cross-device
/// transplant, and MuffinColourPresets' colours - instead of `ControllerGeometry`.
///
/// Same interface as `OptimizedControlPanel` (skin is unused here; colour comes from the
/// selected `PreviewColourPreset` instead) so it drops into `EmulatorViewOptimized` as a
/// straight substitute, gated behind `PreviewPadStore`'s enabled flag.
///
/// Reuses `HeldControl` for press/release and hit-tests the d-pad with
/// `PadLayout.dpadDirections`. The stick is a plain octagon-gated analog without the
/// standard pad's deadzone/curve settings. Experimental; off by default.
struct PreviewControllerPad: View {
    @ObservedObject var store: PreviewPadStore
    let onInput: (String, Bool) -> Void
    let onStick: (Int, CGPoint) -> Void
    @Binding var isEditingLayout: Bool

    var body: some View {
        GeometryReader { proxy in
            // Safe rect built by hand: CGRect.inset(by:) takes UIEdgeInsets, not EdgeInsets.
            let insets = proxy.safeAreaInsets
            let full = proxy.frame(in: .local)
            let safeArea = CGRect(x: full.minX + insets.leading, y: full.minY + insets.top,
                                  width: full.width - insets.leading - insets.trailing,
                                  height: full.height - insets.top - insets.bottom)
            let resolved = store.resolve(container: proxy.size, safeArea: safeArea,
                                         pointsPerInch: DeviceMetrics.current().pointsPerInch)
            let colours = store.colourFile

            ZStack(alignment: .topLeading) {
                ForEach(PadGroup.allCases) { group in
                    PreviewGroupView(group: group, resolved: resolved, colours: colours,
                                     store: store, isEditingLayout: isEditingLayout,
                                     onInput: onInput, onStick: onStick)
                }
            }
            .opacity(isEditingLayout ? 1.0 : 0.85)
        }
        .allowsHitTesting(true)
    }
}

/// One group: every control it owns, drawn from `resolved.controls`, plus (in edit mode)
/// the drag-to-move and pinch-to-resize gesture for the group as a whole.
private struct PreviewGroupView: View {
    let group: PadGroup
    let resolved: PreviewResolved
    let colours: MuffinColourFile
    @ObservedObject var store: PreviewPadStore
    let isEditingLayout: Bool
    let onInput: (String, Bool) -> Void
    let onStick: (Int, CGPoint) -> Void

    @State private var dragOrigin: GroupPlacement?
    @State private var scaleOrigin: GroupPlacement?

    var body: some View {
        ZStack {
            // The edit surface exists only in edit mode, and only over this group's own
            // controls. It used to be a .contentShape on this ZStack, applied all the time:
            // first a full-screen Rectangle, which let the last group drawn (HOME) take
            // every touch on the screen and left the whole pad dead, then the group's rect,
            // which still made each group's empty space swallow touches meant for a
            // neighbour drawn beneath it. Out of edit mode the group itself now takes no
            // touches at all; only its controls do.
            if isEditingLayout, !editRect.isNull {
                Path(editRect)
                    .fill(Color.white.opacity(0.001))
                    .gesture(editGesture)
            }
            ForEach(group.controlIDs, id: \.self) { id in
                if let placement = resolved.controls[id] {
                    PreviewControlView(id: id, placement: placement, colours: colours,
                                       isEditingLayout: isEditingLayout, resolved: resolved,
                                       onInput: onInput, onStick: onStick)
                }
            }
            if let caption = group.caption, let anchor = resolved.controls[group.anchorControl]?.centre {
                // Printed on the game picture itself, with no button behind it, so it carries
                // its own halo: a grey caption on its own vanished over every dark scene.
                let ink = Color(colours.glyph(group.anchorControl))
                let halo = LegibleInk.on(ink, light: .white, dark: .black).opacity(0.75)
                Text(caption)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(ink)
                    .shadow(color: halo, radius: 1)
                    .shadow(color: halo, radius: 1)
                    .position(x: anchor.x, y: anchor.y + captionOffset(for: group))
                    .allowsHitTesting(false)
            }
        }
    }

    private var editRect: CGRect {
        group.controlIDs
            .compactMap { resolved.controls[$0] }
            .map { CGRect(x: $0.centre.x - $0.boundingSize.width / 2,
                          y: $0.centre.y - $0.boundingSize.height / 2,
                          width: $0.boundingSize.width, height: $0.boundingSize.height) }
            .reduce(CGRect.null) { $0.union($1) }
    }

    /// Move and resize as one attached gesture, not two separate `.gesture()` modifiers -
    /// two independent, exclusive gestures on the same view compete for the same touches,
    /// so a two-finger pinch was read as a one-finger drag by whichever of the two claimed
    /// it first. `SimultaneousGesture` is what `EditableControl.editGesture` already uses
    /// for the shipping pad's own per-element drag/pinch, for the identical reason.
    private var editGesture: some Gesture {
        SimultaneousGesture(moveGesture, resizeGesture)
    }

    private func captionOffset(for group: PadGroup) -> CGFloat {
        // Printed under the button, as the hardware illustration has it - roughly one
        // system-button diameter below the anchor's own centre.
        (resolved.controls[group.anchorControl].map { $0.boundingSize.height / 2 + 10 }) ?? 16
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let origin = dragOrigin ?? store.adjustment(for: group)
                if dragOrigin == nil { dragOrigin = origin }
                let unit = max(resolved.unit, 1)
                var next = origin
                next.dx += (value.translation.width / unit) * group.inboardSign
                next.dy -= value.translation.height / unit
                store.setAdjustment(next, for: group)
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private var resizeGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let origin = scaleOrigin ?? store.adjustment(for: group)
                if scaleOrigin == nil { scaleOrigin = origin }
                var next = origin
                next.scale = origin.scale * value
                store.setAdjustment(next, for: group)
            }
            .onEnded { _ in scaleOrigin = nil }
    }
}

/// One control, drawn as its real shape and wired to real input.
private struct PreviewControlView: View {
    let id: String
    let placement: PadLayout.Placement
    let colours: MuffinColourFile
    let isEditingLayout: Bool
    let resolved: PreviewResolved
    let onInput: (String, Bool) -> Void
    let onStick: (Int, CGPoint) -> Void

    /// The colour file's glyph, kept wherever it reads on the button: moved toward black or
    /// white only when it doesn't, as the Super Famicom preset's white letters do on its
    /// yellow and green buttons.
    private var glyphInk: Color {
        LegibleInk.ensure(Color(colours.glyph(id)), on: Color(colours.fill(id)), minimum: LegibleInk.glyph)
    }

    var body: some View {
        switch placement {
        case .circle(let centre, let diameter):
            if id == "stickL" || id == "stickR" {
                PreviewStickView(id: id, centre: centre, diameter: diameter,
                                 colours: colours, isInteractive: !isEditingLayout, onStick: onStick,
                                 clickID: id == "stickL" ? "L3" : "R3", onInput: onInput)
            } else if id.hasPrefix("knob") {
                EmptyView() // drawn by the stick itself
            } else {
                HeldControl(onPressChange: { onInput(id, $0) }, isInteractive: !isEditingLayout,
                            hitShape: hitShape(for: id, diameter: diameter)) { isPressed in
                    ZStack {
                        Circle()
                            .fill(Color(colours.fill(id)).opacity(colours.alpha(id, pressed: isPressed)))
                            .overlay(Circle().strokeBorder(Color(colours.outline), lineWidth: max(1, diameter * 0.04)))
                        if ["X", "Y", "A", "B"].contains(id) {
                            Text(id)
                                .font(.system(size: diameter * 0.42, weight: .bold, design: .rounded))
                                .foregroundColor(glyphInk)
                        } else if id == "plus" {
                            Image(systemName: "plus").font(.system(size: diameter * 0.5, weight: .bold))
                                .foregroundColor(glyphInk)
                        } else if id == "minus" {
                            Image(systemName: "minus").font(.system(size: diameter * 0.5, weight: .bold))
                                .foregroundColor(glyphInk)
                        } else if id == "HOME" {
                            Image(systemName: "house.fill").font(.system(size: diameter * 0.4))
                                .foregroundColor(glyphInk)
                        }
                    }
                }
                .frame(width: diameter, height: diameter)
                .position(centre)
                .allowsHitTesting(!isEditingLayout)
            }

        case .pill(let centre, let size, let corner):
            HeldControl(onPressChange: { onInput(id, $0) }, isInteractive: !isEditingLayout) { isPressed in
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color(colours.fill(id)).opacity(colours.alpha(id, pressed: isPressed)))
                        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Color(colours.outline), lineWidth: max(1, size.height * 0.06)))
                    Text(id).font(.system(size: size.height * 0.38, weight: .bold, design: .rounded))
                        .foregroundColor(glyphInk)
                }
            }
            .frame(width: size.width, height: size.height)
            .position(centre)
            .allowsHitTesting(!isEditingLayout)

        case .cross(let centre, let size, let arm):
            PreviewDpadView(centre: centre, size: size, arm: arm, colours: colours,
                            isInteractive: !isEditingLayout, onInput: onInput)
        }
    }

    /// L3 sits on the middle of the d-pad cross. With the default full-frame hit area its
    /// square covered the inner part of every arm, so a d-pad press near the centre fired
    /// L3 instead. It now takes only the cross's dead centre - the circle
    /// `PadLayout.dpadDirections` reports no direction for - and R3 matches it.
    private func hitShape(for id: String, diameter: CGFloat) -> HeldControlHitShape {
        guard id == "L3" || id == "R3", diameter > 0,
              let dpad = resolved.controls["dpad"], case .cross(_, let size, _) = dpad else {
            return .rectangle
        }
        let deadDiameter = 2 * PadLayout.dpadDeadZone * min(size.width, size.height) / 2
        return .circle(fraction: min(1, deadDiameter / diameter))
    }
}

/// The d-pad, hit-tested as the real cross `PadLayout.dpadDirections` already defines -
/// eight-way, both ids pressed on a diagonal - rather than as four separate rects, which
/// has no diagonal at all.
private struct PreviewDpadView: View {
    let centre: CGPoint
    let size: CGSize
    let arm: CGFloat
    let colours: MuffinColourFile
    let isInteractive: Bool
    let onInput: (String, Bool) -> Void

    @State private var held: Set<String> = []
    /// True while a finger is down. Resets if the system cancels the gesture.
    @GestureState private var touching = false

    /// The cross, drawn around the middle of its own w x h frame.
    private func cross() -> Path {
        let w = size.width, h = size.height
        let a = arm / 2, hw = w / 2, hh = h / 2
        return Path { p in
            p.move(to: CGPoint(x: hw - a, y: 0)); p.addLine(to: CGPoint(x: hw + a, y: 0))
            p.addLine(to: CGPoint(x: hw + a, y: hh - a)); p.addLine(to: CGPoint(x: w, y: hh - a))
            p.addLine(to: CGPoint(x: w, y: hh + a)); p.addLine(to: CGPoint(x: hw + a, y: hh + a))
            p.addLine(to: CGPoint(x: hw + a, y: h)); p.addLine(to: CGPoint(x: hw - a, y: h))
            p.addLine(to: CGPoint(x: hw - a, y: hh + a)); p.addLine(to: CGPoint(x: 0, y: hh + a))
            p.addLine(to: CGPoint(x: 0, y: hh - a)); p.addLine(to: CGPoint(x: hw - a, y: hh - a))
            p.closeSubpath()
        }
    }

    private func releaseAll() {
        for id in held { onInput(id, false) }
        held = []
    }

    var body: some View {
        // Drawn, hit-tested and measured in the same w x h frame; `.position` comes last.
        cross()
            .fill(Color(colours.fill("dpad")))
            .overlay(cross().stroke(Color(colours.outline), lineWidth: max(1, arm * 0.06)))
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { value in
                        let next = PadLayout.dpadDirections(
                            at: value.location,
                            centre: CGPoint(x: size.width / 2, y: size.height / 2),
                            size: size)
                        for id in held.subtracting(next) { onInput(id, false) }
                        for id in next.subtracting(held) { onInput(id, true) }
                        held = next
                    }
                    .onEnded { _ in releaseAll() }
            )
            .allowsHitTesting(isInteractive)
            .position(centre)
            .onChange(of: touching) { down in
                if !down { releaseAll() }
            }
            // A cancel handled before the first render after the press never flips
            // `touching` visibly, so the handler above cannot see it.
            .onChange(of: held) { now in
                if !now.isEmpty && !touching { releaseAll() }
            }
            .onChange(of: isInteractive) { active in
                if !active { releaseAll() }
            }
            .onDisappear { releaseAll() }
    }
}

/// A plain octagon-gated analog stick - see the scope note at the top of this file for
/// why it does not carry the shipping pad's deadzone/curve settings.
private struct PreviewStickView: View {
    let id: String
    let centre: CGPoint
    let diameter: CGFloat
    let colours: MuffinColourFile
    let isInteractive: Bool
    let onStick: (Int, CGPoint) -> Void
    let clickID: String
    let onInput: (String, Bool) -> Void

    @State private var knobOffset: CGSize = .zero
    @State private var pushed = false
    /// True while a finger is on the stick. Resets if the system cancels the gesture.
    @GestureState private var touching = false
    /// The pending release of a tap-click, so a view that goes away mid-click cannot leave
    /// L3/R3 held. Mirrors JoystickControl's own clickRelease in ControllerPad.swift.
    @State private var clickRelease: DispatchWorkItem?

    @AppStorage(ControllerLayoutSettings.hapticsKey)
    private var hapticsEnabled = ControllerLayoutSettings.defaultHaptics

    private var radius: CGFloat { diameter / 2 }
    private var knobRadius: CGFloat { diameter * 0.28 }
    /// Shared with the shipping pad's stick - see ControllerGeometry.stickTravelFraction.
    private var travel: CGFloat { ControllerGeometry.stickTravel(ringDiameter: diameter) }

    /// How long a tap holds L3/R3 before releasing, so a title polling on its own schedule
    /// can see it.
    private static let clickHoldSeconds = 0.12

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(colours.fill("default")).opacity(0.5))
                .overlay(Circle().strokeBorder(Color(colours.outline), lineWidth: max(1, diameter * 0.03)))
            Circle()
                .fill(Color(colours.fill("default")))
                .frame(width: knobRadius * 2, height: knobRadius * 2)
                .offset(knobOffset)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($touching) { _, state, _ in state = true }
                .onChanged { value in
                    // Local to the stick's own frame, so its centre is (radius, radius).
                    let dx = value.location.x - radius, dy = value.location.y - radius
                    let distance = (dx * dx + dy * dy).squareRoot()
                    let reach = travel * ControllerGeometry.StickGate.octagon.radiusFraction(atAngle: atan2(dy, dx))
                    let scale = distance > reach ? reach / distance : 1
                    knobOffset = CGSize(width: dx * scale, height: dy * scale)
                    let deflection = travel > 0 ? min(distance, reach) / travel : 0
                    if deflection > 0.14 { pushed = true }
                    // Console convention: x right-positive, y UP-positive - the opposite
                    // of screen y, which is why this negates dy and not dx.
                    let nx = travel > 0 ? max(-1, min(1, (dx * scale) / travel)) : 0
                    let ny = travel > 0 ? max(-1, min(1, -(dy * scale) / travel)) : 0
                    onStick(id == "stickL" ? 0 : 1, CGPoint(x: nx, y: ny))
                }
                .onEnded { _ in
                    if !pushed { click() }
                }
        )
        .allowsHitTesting(isInteractive)
        .position(centre)
        .onChange(of: touching) { down in
            if !down { recentre() }
        }
        // Same unseen-cancel case as the d-pad's.
        .onChange(of: knobOffset) { offset in
            if offset != .zero && !touching { recentre() }
        }
        .onChange(of: isInteractive) { active in
            if !active { recentre() }
        }
        .onDisappear {
            clickRelease?.cancel()
            clickRelease = nil
            // Don't leave L3/R3 held if the view goes away mid-click.
            onInput(clickID, false)
            pushed = false
            knobOffset = .zero
            onStick(id == "stickL" ? 0 : 1, .zero)
        }
    }

    private func recentre() {
        pushed = false
        onStick(id == "stickL" ? 0 : 1, .zero)
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { knobOffset = .zero }
    }

    private func click() {
        clickRelease?.cancel()
        if hapticsEnabled { PadHaptics.shared.fire() }
        onInput(clickID, true)
        let release = DispatchWorkItem { onInput(clickID, false) }
        clickRelease = release
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clickHoldSeconds, execute: release)
    }
}
