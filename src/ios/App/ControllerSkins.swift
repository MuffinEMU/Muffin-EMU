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
    let onDPadInput: (String) -> Void
    let onButtonInput: (String) -> Void
    @State private var activeDPad: String?
    @State private var activeButton: String?

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(skin.borderColor)

            HStack(spacing: 32) {
                DPadControl(
                    skin: skin,
                    onInput: { direction in
                        activeDPad = direction
                        onDPadInput(direction)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            activeDPad = nil
                        }
                    }
                )

                Spacer()

                ActionButtonGrid(
                    skin: skin,
                    onInput: { button in
                        activeButton = button
                        onButtonInput(button)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            activeButton = nil
                        }
                    },
                    activeButton: $activeButton
                )
            }
            .padding(20)
            .background(skin.backgroundColor)
        }
    }
}

struct DPadControl: View {
    let skin: WiiUControllerSkin
    let onInput: (String) -> Void

    var body: some View {
        VStack(spacing: 4) {
            DPadButton(direction: "↑", skin: skin, action: { onInput("up") })
            HStack(spacing: 4) {
                DPadButton(direction: "←", skin: skin, action: { onInput("left") })
                Color.clear.frame(width: 20)
                DPadButton(direction: "→", skin: skin, action: { onInput("right") })
            }
            DPadButton(direction: "↓", skin: skin, action: { onInput("down") })
        }
    }
}

struct DPadButton: View {
    let direction: String
    let skin: WiiUControllerSkin
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(direction)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 44, height: 44)
                .background(
                    isPressed ?
                    skin.dpadColor.opacity(0.9) :
                    skin.dpadColor.opacity(0.6)
                )
                .foregroundColor(.white)
                .cornerRadius(6)
        }
        .onLongPressGesture(
            minimumDuration: 0.05,
            pressing: { isPressing in
                withAnimation(.easeInOut(duration: 0.05)) {
                    isPressed = isPressing
                }
            },
            perform: action
        )
    }
}

struct ActionButtonGrid: View {
    let skin: WiiUControllerSkin
    let onInput: (String) -> Void
    @Binding var activeButton: String?

    var body: some View {
        VStack(spacing: 4) {
            ActionButtonStyled(
                label: "Y",
                color: skin.buttonColors["Y"] ?? Color.yellow,
                isActive: activeButton == "Y",
                action: {
                    onInput("Y")
                }
            )
            HStack(spacing: 4) {
                ActionButtonStyled(
                    label: "X",
                    color: skin.buttonColors["X"] ?? Color.blue,
                    isActive: activeButton == "X",
                    action: { onInput("X") }
                )
                Color.clear.frame(width: 20)
                ActionButtonStyled(
                    label: "B",
                    color: skin.buttonColors["B"] ?? Color.red,
                    isActive: activeButton == "B",
                    action: { onInput("B") }
                )
            }
            ActionButtonStyled(
                label: "A",
                color: skin.buttonColors["A"] ?? Color.green,
                isActive: activeButton == "A",
                action: { onInput("A") }
            )
        }
    }
}

struct ActionButtonStyled: View {
    let label: String
    let color: Color
    let isActive: Bool
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(isPressed ? color.opacity(0.95) : color.opacity(0.75))
                )
                .foregroundColor(.white)
                .overlay(
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: 2)
                )
        }
        .onLongPressGesture(
            minimumDuration: 0.05,
            pressing: { isPressing in
                withAnimation(.easeInOut(duration: 0.05)) {
                    isPressed = isPressing
                }
            },
            perform: action
        )
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
