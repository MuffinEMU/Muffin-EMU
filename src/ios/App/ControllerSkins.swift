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
