import SwiftUI

struct ControllerSkinLibrary {
    static let allSkins: [WiiUControllerSkin] = [
        .standard,
        .wiiUOriginal,
        .gameCube,
        .nintendo64,
        .superNintendo,
        .nes,
        .switchPro,
        .playStation,
        .xbox,
        .steamDeck,
        .arcadeCabinet,
        .segaGenesis,
        .minimal,
        .glass,
        .neon,
        .darkMode,
        .lightMode,
        .custom,
        .marioTheme,
        .zeldaTheme,
    ]

    static func getSkin(by name: String) -> WiiUControllerSkin? {
        return allSkins.first { $0.name == name }
    }
}

extension WiiUControllerSkin {
    // MARK: - Nintendo Official Themes

    static let standard = WiiUControllerSkin(
        name: "Standard",
        dpadColor: ControllerSkinPalette.Standard.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Standard.a,
            "B": ControllerSkinPalette.Standard.b,
            "X": ControllerSkinPalette.Standard.x,
            "Y": ControllerSkinPalette.Standard.y
        ],
        backgroundColor: ControllerSkinPalette.Standard.background,
        borderColor: Color.white.opacity(0.1),
        shadowOpacity: 0.4,
        cornerRadius: 24
    )

    static let wiiUOriginal = WiiUControllerSkin(
        name: "Wii U Original",
        dpadColor: ControllerSkinPalette.WiiUOriginal.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.WiiUOriginal.a,
            "B": ControllerSkinPalette.WiiUOriginal.b,
            "X": ControllerSkinPalette.WiiUOriginal.x,
            "Y": ControllerSkinPalette.WiiUOriginal.y
        ],
        backgroundColor: ControllerSkinPalette.WiiUOriginal.background,
        borderColor: Color.white.opacity(0.12),
        shadowOpacity: 0.45,
        cornerRadius: 22
    )

    static let gameCube = WiiUControllerSkin(
        name: "GameCube",
        dpadColor: ControllerSkinPalette.GameCube.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.GameCube.a,
            "B": ControllerSkinPalette.GameCube.b,
            "X": ControllerSkinPalette.GameCube.x,
            "Y": ControllerSkinPalette.GameCube.y
        ],
        backgroundColor: ControllerSkinPalette.GameCube.background,
        borderColor: Color.white.opacity(0.1),
        shadowOpacity: 0.5,
        cornerRadius: 20
    )

    static let nintendo64 = WiiUControllerSkin(
        name: "Nintendo 64",
        dpadColor: ControllerSkinPalette.Nintendo64.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Nintendo64.a,
            "B": ControllerSkinPalette.Nintendo64.b,
            "X": ControllerSkinPalette.Nintendo64.x,
            "Y": ControllerSkinPalette.Nintendo64.y
        ],
        backgroundColor: ControllerSkinPalette.Nintendo64.background,
        borderColor: Color.white.opacity(0.15),
        shadowOpacity: 0.4,
        cornerRadius: 18
    )

    static let superNintendo = WiiUControllerSkin(
        name: "Super Nintendo",
        dpadColor: ControllerSkinPalette.SuperNintendo.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.SuperNintendo.a,
            "B": ControllerSkinPalette.SuperNintendo.b,
            "X": ControllerSkinPalette.SuperNintendo.x,
            "Y": ControllerSkinPalette.SuperNintendo.y
        ],
        backgroundColor: ControllerSkinPalette.SuperNintendo.background,
        borderColor: Color.white.opacity(0.1),
        shadowOpacity: 0.35,
        cornerRadius: 16
    )

    static let nes = WiiUControllerSkin(
        name: "NES",
        dpadColor: ControllerSkinPalette.NES.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.NES.a,
            "B": ControllerSkinPalette.NES.b,
            "X": ControllerSkinPalette.NES.x,
            "Y": ControllerSkinPalette.NES.y
        ],
        backgroundColor: ControllerSkinPalette.NES.background,
        borderColor: Color.white.opacity(0.08),
        shadowOpacity: 0.3,
        cornerRadius: 12
    )

    static let switchPro = WiiUControllerSkin(
        name: "Switch Pro",
        dpadColor: ControllerSkinPalette.SwitchPro.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.SwitchPro.a,
            "B": ControllerSkinPalette.SwitchPro.b,
            "X": ControllerSkinPalette.SwitchPro.x,
            "Y": ControllerSkinPalette.SwitchPro.y
        ],
        backgroundColor: ControllerSkinPalette.SwitchPro.background,
        borderColor: Color.white.opacity(0.12),
        shadowOpacity: 0.5,
        cornerRadius: 20
    )

    // MARK: - Third-Party Themes

    static let playStation = WiiUControllerSkin(
        name: "PlayStation",
        dpadColor: ControllerSkinPalette.PlayStation.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.PlayStation.a,
            "B": ControllerSkinPalette.PlayStation.b,
            "X": ControllerSkinPalette.PlayStation.x,
            "Y": ControllerSkinPalette.PlayStation.y
        ],
        backgroundColor: ControllerSkinPalette.PlayStation.background,
        borderColor: Color.white.opacity(0.1),
        shadowOpacity: 0.55,
        cornerRadius: 22
    )

    static let xbox = WiiUControllerSkin(
        name: "Xbox",
        dpadColor: ControllerSkinPalette.Xbox.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Xbox.a,
            "B": ControllerSkinPalette.Xbox.b,
            "X": ControllerSkinPalette.Xbox.x,
            "Y": ControllerSkinPalette.Xbox.y
        ],
        backgroundColor: ControllerSkinPalette.Xbox.background,
        borderColor: ControllerSkinPalette.Xbox.border.opacity(0.3),
        shadowOpacity: 0.5,
        cornerRadius: 18
    )

    static let steamDeck = WiiUControllerSkin(
        name: "Steam Deck",
        dpadColor: ControllerSkinPalette.SteamDeck.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.SteamDeck.a,
            "B": ControllerSkinPalette.SteamDeck.b,
            "X": ControllerSkinPalette.SteamDeck.x,
            "Y": ControllerSkinPalette.SteamDeck.y
        ],
        backgroundColor: ControllerSkinPalette.SteamDeck.background,
        borderColor: Color.white.opacity(0.15),
        shadowOpacity: 0.45,
        cornerRadius: 20
    )

    // MARK: - Retro & Arcade

    static let arcadeCabinet = WiiUControllerSkin(
        name: "Arcade Cabinet",
        dpadColor: ControllerSkinPalette.ArcadeCabinet.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.ArcadeCabinet.a,
            "B": ControllerSkinPalette.ArcadeCabinet.b,
            "X": ControllerSkinPalette.ArcadeCabinet.x,
            "Y": ControllerSkinPalette.ArcadeCabinet.y
        ],
        backgroundColor: ControllerSkinPalette.ArcadeCabinet.background,
        borderColor: ControllerSkinPalette.ArcadeCabinet.border.opacity(0.5),
        shadowOpacity: 0.6,
        cornerRadius: 12
    )

    static let segaGenesis = WiiUControllerSkin(
        name: "Sega Genesis",
        dpadColor: ControllerSkinPalette.SegaGenesis.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.SegaGenesis.a,
            "B": ControllerSkinPalette.SegaGenesis.b,
            "X": ControllerSkinPalette.SegaGenesis.x,
            "Y": ControllerSkinPalette.SegaGenesis.y
        ],
        backgroundColor: ControllerSkinPalette.SegaGenesis.background,
        borderColor: Color.white.opacity(0.1),
        shadowOpacity: 0.4,
        cornerRadius: 14
    )

    // MARK: - Minimalist & Modern

    static let minimal = WiiUControllerSkin(
        name: "Minimal",
        dpadColor: Color.white.opacity(0.8),
        buttonColors: [
            "A": Color.white.opacity(0.7),
            "B": Color.white.opacity(0.7),
            "X": Color.white.opacity(0.7),
            "Y": Color.white.opacity(0.7)
        ],
        backgroundColor: Color.black.opacity(0.6),
        borderColor: Color.white.opacity(0.2),
        shadowOpacity: 0.2,
        cornerRadius: 12
    )

    static let glass = WiiUControllerSkin(
        name: "Glass",
        dpadColor: Color.white.opacity(0.6),
        buttonColors: [
            "A": ControllerSkinPalette.Glass.a.opacity(0.7),
            "B": ControllerSkinPalette.Glass.b.opacity(0.7),
            "X": ControllerSkinPalette.Glass.x.opacity(0.7),
            "Y": ControllerSkinPalette.Glass.y.opacity(0.7)
        ],
        backgroundColor: Color.black.opacity(0.3),
        borderColor: Color.white.opacity(0.3),
        shadowOpacity: 0.15,
        cornerRadius: 16
    )

    static let neon = WiiUControllerSkin(
        name: "Neon",
        dpadColor: ControllerSkinPalette.Neon.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Neon.a,
            "B": ControllerSkinPalette.Neon.b,
            "X": ControllerSkinPalette.Neon.x,
            "Y": ControllerSkinPalette.Neon.y
        ],
        backgroundColor: ControllerSkinPalette.Neon.background,
        borderColor: ControllerSkinPalette.Neon.border.opacity(0.4),
        shadowOpacity: 0.6,
        cornerRadius: 20
    )

    static let darkMode = WiiUControllerSkin(
        name: "Dark Mode",
        dpadColor: ControllerSkinPalette.DarkMode.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.DarkMode.a,
            "B": ControllerSkinPalette.DarkMode.b,
            "X": ControllerSkinPalette.DarkMode.x,
            "Y": ControllerSkinPalette.DarkMode.y
        ],
        backgroundColor: ControllerSkinPalette.DarkMode.background,
        borderColor: Color.white.opacity(0.08),
        shadowOpacity: 0.6,
        cornerRadius: 18
    )

    static let lightMode = WiiUControllerSkin(
        name: "Light Mode",
        dpadColor: ControllerSkinPalette.LightMode.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.LightMode.a,
            "B": ControllerSkinPalette.LightMode.b,
            "X": ControllerSkinPalette.LightMode.x,
            "Y": ControllerSkinPalette.LightMode.y
        ],
        backgroundColor: ControllerSkinPalette.LightMode.background,
        borderColor: Color.black.opacity(0.1),
        shadowOpacity: 0.15,
        cornerRadius: 20
    )

    static let custom = WiiUControllerSkin(
        name: "Custom",
        dpadColor: ControllerSkinPalette.Custom.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.Custom.a,
            "B": ControllerSkinPalette.Custom.b,
            "X": ControllerSkinPalette.Custom.x,
            "Y": ControllerSkinPalette.Custom.y
        ],
        backgroundColor: ControllerSkinPalette.Custom.background,
        borderColor: ControllerSkinPalette.Custom.dpad.opacity(0.3),
        shadowOpacity: 0.4,
        cornerRadius: 20
    )

    // MARK: - Game-Themed

    static let marioTheme = WiiUControllerSkin(
        name: "Mario Theme",
        dpadColor: ControllerSkinPalette.MarioTheme.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.MarioTheme.a,
            "B": ControllerSkinPalette.MarioTheme.b,
            "X": ControllerSkinPalette.MarioTheme.x,
            "Y": ControllerSkinPalette.MarioTheme.y
        ],
        backgroundColor: ControllerSkinPalette.MarioTheme.background.opacity(0.1),
        borderColor: ControllerSkinPalette.MarioTheme.dpad.opacity(0.3),
        shadowOpacity: 0.4,
        cornerRadius: 20
    )

    static let zeldaTheme = WiiUControllerSkin(
        name: "Zelda Theme",
        dpadColor: ControllerSkinPalette.ZeldaTheme.dpad,
        buttonColors: [
            "A": ControllerSkinPalette.ZeldaTheme.a,
            "B": ControllerSkinPalette.ZeldaTheme.b,
            "X": ControllerSkinPalette.ZeldaTheme.x,
            "Y": ControllerSkinPalette.ZeldaTheme.y
        ],
        backgroundColor: ControllerSkinPalette.ZeldaTheme.background,
        borderColor: ControllerSkinPalette.ZeldaTheme.dpad.opacity(0.25),
        shadowOpacity: 0.45,
        cornerRadius: 20
    )
}

struct ControllerSkinSelector: View {
    @Binding var selectedSkin: WiiUControllerSkin
    @State private var showingSelector = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Controller Skin")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(MuffinTheme.brownDarkest)

                Spacer()

                Button(action: { showingSelector.toggle() }) {
                    Text(selectedSkin.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(MuffinTheme.pixelBlue)
                }
            }

            if showingSelector {
                VStack(spacing: 8) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(ControllerSkinLibrary.allSkins, id: \.name) { skin in
                                SkinOption(
                                    skin: skin,
                                    isSelected: selectedSkin.name == skin.name,
                                    onSelect: {
                                        selectedSkin = skin
                                        showingSelector = false
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
                .padding(12)
                .background(MuffinTheme.wrapper.opacity(0.5))
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(MuffinTheme.cream)
        .cornerRadius(12)
    }
}

struct SkinOption: View {
    let skin: WiiUControllerSkin
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(skin.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(MuffinTheme.brownDarkest)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(skin.dpadColor)
                            .frame(width: 12, height: 12)

                        Circle()
                            .fill(skin.buttonColors["A"] ?? Color.gray)
                            .frame(width: 12, height: 12)

                        Circle()
                            .fill(skin.buttonColors["B"] ?? Color.gray)
                            .frame(width: 12, height: 12)

                        Circle()
                            .fill(skin.buttonColors["X"] ?? Color.gray)
                            .frame(width: 12, height: 12)

                        Circle()
                            .fill(skin.buttonColors["Y"] ?? Color.gray)
                            .frame(width: 12, height: 12)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(MuffinTheme.pixelBlue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(isSelected ? MuffinTheme.wrapper : MuffinTheme.cream)
            .cornerRadius(8)
        }
    }
}
