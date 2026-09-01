import SwiftUI

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
/// Scope note: this reuses `HeldControl` for reliable press/release the same way the
/// shipping pad does, and hit-tests the d-pad with `PadLayout.dpadDirections` rather than
/// four separate rects, for the same reason the shipping pad's diamond shape matters -
/// but the stick here is a plain octagon-gated analog, without the shipping pad's
/// deadzone/curve feel settings. That is a deliberate scope cut for a preview build, not
/// an oversight: this file has never run on a device, and duplicating the full feel-tuned
/// stick untested was a worse trade than shipping a simpler, honestly-scoped one.
struct PreviewControllerPad: View {
    @ObservedObject var store: PreviewPadStore
    let onInput: (String, Bool) -> Void
    let onStick: (Int, CGPoint) -> Void
    @Binding var isEditingLayout: Bool

    var body: some View {
        GeometryReader { proxy in
            // CGRect has no .inset(by:) that takes SwiftUI's own EdgeInsets (only
            // UIKit's UIEdgeInsets, a different type), so the safe rect is built by hand
            // rather than reached for an extension that does not apply here.
            let insets = proxy.safeAreaInsets
            let full = proxy.frame(in: .local)
            let safeArea = CGRect(x: full.minX + insets.leading, y: full.minY + insets.top,
                                  width: full.width - insets.leading - insets.trailing,
                                  height: full.height - insets.top - insets.bottom)
            let resolved = store.resolve(container: proxy.size, safeArea: safeArea,
                                         pointsPerInch: DeviceMetrics.current().pointsPerInch)
            let colours = store.colourPreset.file

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
            ForEach(group.controlIDs, id: \.self) { id in
                if let placement = resolved.controls[id] {
                    PreviewControlView(id: id, placement: placement, colours: colours,
                                       isEditingLayout: isEditingLayout, resolved: resolved,
                                       onInput: onInput, onStick: onStick)
                }
            }
            if let caption = group.caption, let anchor = resolved.controls[group.anchorControl]?.centre {
                Text(caption)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(Color(colours.glyph(group.anchorControl)))
                    .position(x: anchor.x, y: anchor.y + captionOffset(for: group))
            }
        }
        // The drag handle covers the whole editing surface rather than one shape, since a
        // group like L+ZL has no single outline to grab - dragging anywhere inside its
        // bounding area moves the pair together, matching how ControllerCustomLayout
        // already groups them.
        .contentShape(Rectangle())
        .gesture(isEditingLayout ? moveGesture : nil)
        .gesture(isEditingLayout ? resizeGesture : nil)
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
                HeldControl(onPressChange: { onInput(id, $0) }) { isPressed in
                    ZStack {
                        Circle()
                            .fill(Color(colours.fill(id)).opacity(colours.alpha(id, pressed: isPressed)))
                            .overlay(Circle().strokeBorder(Color(colours.outline), lineWidth: max(1, diameter * 0.04)))
                        if ["X", "Y", "A", "B"].contains(id) {
                            Text(id)
                                .font(.system(size: diameter * 0.42, weight: .bold, design: .rounded))
                                .foregroundColor(Color(colours.glyph(id)))
                        } else if id == "plus" {
                            Image(systemName: "plus").font(.system(size: diameter * 0.5, weight: .bold))
                                .foregroundColor(Color(colours.glyph(id)))
                        } else if id == "minus" {
                            Image(systemName: "minus").font(.system(size: diameter * 0.5, weight: .bold))
                                .foregroundColor(Color(colours.glyph(id)))
                        } else if id == "HOME" {
                            Image(systemName: "house.fill").font(.system(size: diameter * 0.4))
                                .foregroundColor(Color(colours.glyph(id)))
                        }
                    }
                }
                .frame(width: diameter, height: diameter)
                .position(centre)
                .allowsHitTesting(!isEditingLayout)
            }

        case .pill(let centre, let size, let corner):
            HeldControl(onPressChange: { onInput(id, $0) }) { isPressed in
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color(colours.fill(id)).opacity(colours.alpha(id, pressed: isPressed)))
                        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(Color(colours.outline), lineWidth: max(1, size.height * 0.06)))
                    Text(id).font(.system(size: size.height * 0.38, weight: .bold, design: .rounded))
                        .foregroundColor(Color(colours.glyph(id)))
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

    var body: some View {
        let w = size.width, h = size.height
        Path { p in
            let a = arm / 2, hw = w / 2, hh = h / 2
            p.move(to: CGPoint(x: -a, y: -hh)); p.addLine(to: CGPoint(x: a, y: -hh))
            p.addLine(to: CGPoint(x: a, y: -a)); p.addLine(to: CGPoint(x: hw, y: -a))
            p.addLine(to: CGPoint(x: hw, y: a)); p.addLine(to: CGPoint(x: a, y: a))
            p.addLine(to: CGPoint(x: a, y: hh)); p.addLine(to: CGPoint(x: -a, y: hh))
            p.addLine(to: CGPoint(x: -a, y: a)); p.addLine(to: CGPoint(x: -hw, y: a))
            p.addLine(to: CGPoint(x: -hw, y: -a)); p.addLine(to: CGPoint(x: -a, y: -a))
            p.closeSubpath()
        }
        .offset(x: centre.x, y: centre.y)
        .fill(Color(colours.fill("dpad")))
        .overlay(
            Path { p in
                let a = arm / 2, hw = w / 2, hh = h / 2
                p.move(to: CGPoint(x: -a, y: -hh)); p.addLine(to: CGPoint(x: a, y: -hh))
                p.addLine(to: CGPoint(x: a, y: -a)); p.addLine(to: CGPoint(x: hw, y: -a))
                p.addLine(to: CGPoint(x: hw, y: a)); p.addLine(to: CGPoint(x: a, y: a))
                p.addLine(to: CGPoint(x: a, y: hh)); p.addLine(to: CGPoint(x: -a, y: hh))
                p.addLine(to: CGPoint(x: -a, y: a)); p.addLine(to: CGPoint(x: -hw, y: a))
                p.addLine(to: CGPoint(x: -hw, y: -a)); p.addLine(to: CGPoint(x: -a, y: -a))
                p.closeSubpath()
            }
            .offset(x: centre.x, y: centre.y)
            .stroke(Color(colours.outline), lineWidth: max(1, arm * 0.06))
        )
        .frame(width: w + 40, height: h + 40) // generous frame so the offset path still hit-tests
        .contentShape(Rectangle())
        .allowsHitTesting(isInteractive)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let next = PadLayout.dpadDirections(at: value.location, centre: centre, size: size)
                    for id in held.subtracting(next) { onInput(id, false) }
                    for id in next.subtracting(held) { onInput(id, true) }
                    held = next
                }
                .onEnded { _ in
                    for id in held { onInput(id, false) }
                    held = []
                }
        )
        .onDisappear { for id in held { onInput(id, false) }; held = [] }
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

    private var radius: CGFloat { diameter / 2 }
    private var knobRadius: CGFloat { diameter * 0.28 }
    private var travel: CGFloat { radius - knobRadius }

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
        .position(centre)
        .contentShape(Circle())
        .allowsHitTesting(isInteractive)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
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
                    if !pushed { onInput(clickID, true); onInput(clickID, false) }
                    pushed = false
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { knobOffset = .zero }
                    onStick(id == "stickL" ? 0 : 1, .zero)
                }
        )
        .onDisappear {
            pushed = false
            knobOffset = .zero
            onStick(id == "stickL" ? 0 : 1, .zero)
        }
    }
}
