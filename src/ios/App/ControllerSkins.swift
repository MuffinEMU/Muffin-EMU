import SwiftUI

struct ControllerSkinManager {
    static let defaultSkin = WiiUControllerSkin.standard

    enum SkinStyle {
        case standard
        case pro
        case minimal
        case dark
    }
}

struct WiiUControllerSkin {
    let name: String
    let dpadColor: Color
    let buttonColors: [String: Color]
    let backgroundColor: Color
    let borderColor: Color
    let shadowOpacity: Double
    let cornerRadius: CGFloat

    // .standard and .minimal are defined in ControllerSkinsLibrary.swift's
    // `extension WiiUControllerSkin` — kept there since that file already
    // redeclared them as part of its larger skin catalog.

    static let pro = WiiUControllerSkin(
        name: "Pro",
        dpadColor: ControllerSkinPalette.Pro.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Pro.a,
            "B": ControllerSkinPalette.Pro.b,
            "X": ControllerSkinPalette.Pro.x,
            "Y": ControllerSkinPalette.Pro.y
        ],
        backgroundColor: ControllerSkinPalette.Pro.background,
        borderColor: Color.white.opacity(0.15),
        shadowOpacity: 0.5,
        cornerRadius: 20
    )

    static let dark = WiiUControllerSkin(
        name: "Dark",
        dpadColor: ControllerSkinPalette.Dark.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Dark.a,
            "B": ControllerSkinPalette.Dark.b,
            "X": ControllerSkinPalette.Dark.x,
            "Y": ControllerSkinPalette.Dark.y
        ],
        backgroundColor: ControllerSkinPalette.Dark.background,
        borderColor: Color.white.opacity(0.08),
        shadowOpacity: 0.6,
        cornerRadius: 18
    )
}

struct OptimizedControlPanel: View {
    let skin: WiiUControllerSkin
    // (label, pressed) - not (label). A tap has no way to express "still held", and
    // holding a direction is most of playing anything, so the whole panel reports state
    // changes rather than events. Every `true` is followed by exactly one `false`.
    let onDPadInput: (String, Bool) -> Void
    let onButtonInput: (String, Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(skin.borderColor)

            HStack(spacing: 32) {
                DPadControl(skin: skin, onInput: onDPadInput)

                Spacer()

                ActionButtonGrid(skin: skin, onInput: onButtonInput)
            }
            .padding(20)
            .background(skin.backgroundColor)
        }
    }
}

/// A control that is held for as long as a finger is on it.
///
/// The panel used to be built out of `Button` + `onLongPressGesture`, which is a tap:
/// it fires once, on release, and there is no way to ask it whether the finger is still
/// down. It also serialises - UIKit's button machinery claims the interaction, so a
/// second finger arriving on a different button while the first is held was simply
/// dropped, and "hold left while pressing A" was not expressible at all.
///
/// `DragGesture(minimumDistance: 0)` fixes both. onChanged arrives on touch-down and
/// onEnded on lift, including a lift that happens outside the view's own bounds, so a
/// press cannot get stuck by sliding a thumb off the edge of a button.
///
/// Attached with `.gesture`, deliberately, not `.simultaneousGesture`: a gesture on a
/// child view takes precedence over one on an ancestor, and the emulator screen has a
/// full-screen `.onTapGesture` on it that shows and hides this very panel. Made
/// simultaneous, every button press would also toggle the controls away underneath the
/// finger. Sibling buttons are not ancestors of one another, so they arbitrate
/// independently and two fingers on two different controls both register.
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

struct DPadControl: View {
    let skin: WiiUControllerSkin
    let onInput: (String, Bool) -> Void

    var body: some View {
        VStack(spacing: 4) {
            DPadButton(direction: "↑", skin: skin) { onInput("up", $0) }
            HStack(spacing: 4) {
                DPadButton(direction: "←", skin: skin) { onInput("left", $0) }
                Color.clear.frame(width: 20)
                DPadButton(direction: "→", skin: skin) { onInput("right", $0) }
            }
            DPadButton(direction: "↓", skin: skin) { onInput("down", $0) }
        }
    }
}

struct DPadButton: View {
    let direction: String
    let skin: WiiUControllerSkin
    let onPressChange: (Bool) -> Void

    var body: some View {
        HeldControl(onPressChange: onPressChange) { isPressed in
            Text(direction)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
                .background(
                    skin.dpadColor.opacity(isPressed ? 0.9 : 0.6)
                )
                .foregroundColor(.white)
                .cornerRadius(6)
                .animation(.easeInOut(duration: 0.05), value: isPressed)
        }
    }
}

struct ActionButtonGrid: View {
    let skin: WiiUControllerSkin
    let onInput: (String, Bool) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ActionButtonStyled(
                label: "Y",
                color: skin.buttonColors["Y"] ?? Color.yellow
            ) { onInput("Y", $0) }
            HStack(spacing: 4) {
                ActionButtonStyled(
                    label: "X",
                    color: skin.buttonColors["X"] ?? Color.blue
                ) { onInput("X", $0) }
                Color.clear.frame(width: 20)
                ActionButtonStyled(
                    label: "B",
                    color: skin.buttonColors["B"] ?? Color.red
                ) { onInput("B", $0) }
            }
            ActionButtonStyled(
                label: "A",
                color: skin.buttonColors["A"] ?? Color.green
            ) { onInput("A", $0) }
        }
    }
}

struct ActionButtonStyled: View {
    let label: String
    let color: Color
    let onPressChange: (Bool) -> Void

    var body: some View {
        HeldControl(onPressChange: onPressChange) { isPressed in
            Text(label)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(color.opacity(isPressed ? 0.95 : 0.75))
                )
                .foregroundColor(.white)
                .overlay(
                    Circle()
                        .stroke(color.opacity(isPressed ? 0.8 : 0.3), lineWidth: 2)
                )
                .animation(.easeInOut(duration: 0.05), value: isPressed)
        }
    }
}

struct SkinPreview: View {
    let skin: WiiUControllerSkin

    var body: some View {
        VStack(spacing: 12) {
            Text(skin.name)
                .font(.system(.headline, design: .rounded))
                .foregroundColor(MuffinTheme.brownDarkest)

            HStack(spacing: 20) {
                VStack(spacing: 2) {
                    Circle().fill(skin.dpadColor).frame(width: 16, height: 16)
                    Text("D-Pad").font(.caption2).foregroundColor(MuffinTheme.brownMid)
                }

                ForEach(["A", "B", "X", "Y"], id: \.self) { button in
                    VStack(spacing: 2) {
                        Circle()
                            .fill(skin.buttonColors[button] ?? Color.gray)
                            .frame(width: 16, height: 16)
                        Text(button)
                            .font(.caption2)
                            .foregroundColor(MuffinTheme.brownMid)
                    }
                }
            }
            .padding(12)
            .background(skin.backgroundColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(skin.borderColor, lineWidth: 1)
            )
        }
        .padding(12)
        .background(MuffinTheme.cream)
        .cornerRadius(12)
    }
}
