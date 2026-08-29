import SwiftUI

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
                    controls: ControllerGeometry.leftCluster,
                    edge: .leading,
                    skin: skin,
                    unit: unit,
                    container: proxy.size,
                    isEditingLayout: isEditingLayout,
                    offsetX: $leftOffsetX,
                    offsetY: $leftOffsetY,
                    onInput: onInput
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
                    onInput: onInput
                )
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
    let skin: WiiUControllerSkin
    let unit: CGFloat
    let container: CGSize
    let isEditingLayout: Bool
    @Binding var offsetX: Double
    @Binding var offsetY: Double
    let onInput: (String, Bool) -> Void

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
            x: edge == .leading ? inset : container.width - inset,
            y: container.height - ControllerGeometry.centreFromBottom * unit
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

            ForEach(controls) { control in
                ControlButton(
                    control: control,
                    skin: skin,
                    unit: unit,
                    isInteractive: !isEditingLayout,
                    onInput: onInput
                )
                .position(
                    x: centre.x + control.offset.x * unit,
                    y: centre.y + control.offset.y * unit
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
        case .shoulder, .system, .stick:
            return Self.neutralFill
        }
    }

    private var labelColor: Color {
        switch control.style {
        case .dpad, .face:
            return .white
        case .shoulder, .system, .stick:
            return Self.neutralLabel
        }
    }

    private var fontSize: CGFloat {
        switch control.style {
        case .dpad:     return unit * 0.32   // filled triangles, not letters
        case .face:     return unit * 0.42
        case .system:   return unit * 0.46   // the glyph is small inside its own advance
        case .stick:    return unit * 0.30
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
private struct HeldControl<Content: View>: View {
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
