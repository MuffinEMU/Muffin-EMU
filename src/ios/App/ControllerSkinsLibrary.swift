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
        dpadColor: Color(red: 0.7, green: 0.7, blue: 0.7),
        buttonColors: [
            "A": Color(red: 0.2, green: 0.8, blue: 0.3),
            "B": Color(red: 1.0, green: 0.3, blue: 0.2),
            "X": Color(red: 0.1, green: 0.5, blue: 1.0),
            "Y": Color(red: 1.0, green: 0.8, blue: 0.1)
        ],
        backgroundColor: Color(red: 0.15, green: 0.15, blue: 0.17),
        borderColor: Color.white.opacity(0.1),
        shadowOpacity: 0.4,
        cornerRadius: 24
    )

    static let wiiUOriginal = WiiUControllerSkin(
        name: "Wii U Original",
        dpadColor: Color(red: 0.2, green: 0.2, blue: 0.2),
        buttonColors: [
            "A": Color(red: 0.1, green: 0.7, blue: 0.2),
            "B": Color(red: 0.95, green: 0.2, blue: 0.1),
            "X": Color(red: 0.0, green: 0.3, blue: 0.95),
            "Y": Color(red: 0.99, green: 0.75, blue: 0.0)
        ],
        backgroundColor: Color(red: 0.18, green: 0.18, blue: 0.19),
        borderColor: Color.white.opacity(0.12),
        shadowOpacity: 0.45,
        cornerRadius: 22
    )

    static let gameCube = WiiUControllerSkin(
        name: "GameCube",
        dpadColor: Color(red: 0.15, green: 0.15, blue: 0.15),
        buttonColors: [
            "A": Color(red: 0.15, green: 0.75, blue: 0.25),
            "B": Color(red: 1.0, green: 0.1, blue: 0.1),
            "X": Color(red: 0.0, green: 0.3, blue: 0.95),
            "Y": Color(red: 0.95, green: 0.65, blue: 0.0)
        ],
        backgroundColor: Color(red: 0.1, green: 0.1, blue: 0.15),
        borderColor: Color.white.opacity(0.1),
        shadowOpacity: 0.5,
        cornerRadius: 20
    )

    static let nintendo64 = WiiUControllerSkin(
        name: "Nintendo 64",
        dpadColor: Color(red: 0.8, green: 0.1, blue: 0.1),
        buttonColors: [
            "A": Color(red: 0.2, green: 0.8, blue: 0.3),
            "B": Color(red: 1.0, green: 0.8, blue: 0.0),
            "X": Color(red: 0.2, green: 0.8, blue: 0.3),
            "Y": Color(red: 1.0, green: 0.8, blue: 0.0)
        ],
        backgroundColor: Color(red: 0.12, green: 0.12, blue: 0.2),
        borderColor: Color.white.opacity(0.15),
        shadowOpacity: 0.4,
        cornerRadius: 18
    )

    static let superNintendo = WiiUControllerSkin(
        name: "Super Nintendo",
        dpadColor: Color(red: 0.7, green: 0.7, blue: 0.7),
        buttonColors: [
            "A": Color(red: 0.15, green: 0.75, blue: 0.2),
            "B": Color(red: 0.95, green: 0.15, blue: 0.15),
            "X": Color(red: 0.15, green: 0.4, blue: 0.95),
            "Y": Color(red: 0.95, green: 0.7, blue: 0.05)
        ],
        backgroundColor: Color(red: 0.2, green: 0.15, blue: 0.25),
        borderColor: Color.white.opacity(0.1),
        shadowOpacity: 0.35,
        cornerRadius: 16
    )

    static let nes = WiiUControllerSkin(
        name: "NES",
        dpadColor: Color(red: 0.2, green: 0.2, blue: 0.2),
        buttonColors: [
            "A": Color(red: 0.95, green: 0.2, blue: 0.2),
            "B": Color(red: 0.95, green: 0.2, blue: 0.2),
            "X": Color(red: 0.95, green: 0.2, blue: 0.2),
            "Y": Color(red: 0.95, green: 0.2, blue: 0.2)
        ],
        backgroundColor: Color(red: 0.1, green: 0.1, blue: 0.1),
        borderColor: Color.white.opacity(0.08),
        shadowOpacity: 0.3,
        cornerRadius: 12
    )

    static let switchPro = WiiUControllerSkin(
        name: "Switch Pro",
        dpadColor: Color(red: 0.3, green: 0.3, blue: 0.3),
        buttonColors: [
            "A": Color(red: 0.2, green: 0.8, blue: 0.3),
            "B": Color(red: 1.0, green: 0.3, blue: 0.2),
            "X": Color(red: 0.1, green: 0.5, blue: 1.0),
            "Y": Color(red: 1.0, green: 0.8, blue: 0.1)
        ],
        backgroundColor: Color(red: 0.08, green: 0.08, blue: 0.1),
        borderColor: Color.white.opacity(0.12),
        shadowOpacity: 0.5,
        cornerRadius: 20
    )

    // MARK: - Third-Party Themes

    static let playStation = WiiUControllerSkin(
        name: "PlayStation",
        dpadColor: Color(red: 0.2, green: 0.2, blue: 0.2),
        buttonColors: [
            "A": Color(red: 0.2, green: 0.6, blue: 1.0),
            "B": Color(red: 1.0, green: 0.2, blue: 0.3),
            "X": Color(red: 1.0, green: 0.4, blue: 0.2),
            "Y": Color(red: 0.2, green: 0.8, blue: 0.3)
        ],
        backgroundColor: Color(red: 0.05, green: 0.05, blue: 0.07),
        borderColor: Color.white.opacity(0.1),
        shadowOpacity: 0.55,
        cornerRadius: 22
    )

    static let xbox = WiiUControllerSkin(
        name: "Xbox",
        dpadColor: Color(red: 0.2, green: 0.2, blue: 0.2),
        buttonColors: [
            "A": Color(red: 0.1, green: 0.7, blue: 0.2),
            "B": Color(red: 1.0, green: 0.2, blue: 0.1),
            "X": Color(red: 0.15, green: 0.4, blue: 1.0),
            "Y": Color(red: 1.0, green: 0.75, blue: 0.0)
        ],
        backgroundColor: Color(red: 0.08, green: 0.08, blue: 0.08),
        borderColor: Color(red: 0.0, green: 0.8, blue: 0.0).opacity(0.3),
        shadowOpacity: 0.5,
        cornerRadius: 18
    )

    static let steamDeck = WiiUControllerSkin(
        name: "Steam Deck",
        dpadColor: Color(red: 0.15, green: 0.15, blue: 0.15),
        buttonColors: [
            "A": Color(red: 0.2, green: 0.8, blue: 0.3),
            "B": Color(red: 1.0, green: 0.3, blue: 0.2),
            "X": Color(red: 0.1, green: 0.5, blue: 1.0),
            "Y": Color(red: 1.0, green: 0.8, blue: 0.1)
        ],
        backgroundColor: Color(red: 0.1, green: 0.1, blue: 0.11),
        borderColor: Color.white.opacity(0.15),
        shadowOpacity: 0.45,
        cornerRadius: 20
    )

    // MARK: - Retro & Arcade

    static let arcadeCabinet = WiiUControllerSkin(
        name: "Arcade Cabinet",
        dpadColor: Color(red: 0.95, green: 0.4, blue: 0.0),
        buttonColors: [
            "A": Color(red: 0.95, green: 0.1, blue: 0.1),
            "B": Color(red: 0.1, green: 0.8, blue: 0.95),
            "X": Color(red: 0.95, green: 0.95, blue: 0.1),
            "Y": Color(red: 0.1, green: 0.95, blue: 0.4)
        ],
        backgroundColor: Color(red: 0.02, green: 0.02, blue: 0.02),
        borderColor: Color(red: 0.95, green: 0.4, blue: 0.0).opacity(0.5),
        shadowOpacity: 0.6,
        cornerRadius: 12
    )

    static let segaGenesis = WiiUControllerSkin(
        name: "Sega Genesis",
        dpadColor: Color(red: 0.2, green: 0.2, blue: 0.2),
        buttonColors: [
            "A": Color(red: 0.95, green: 0.15, blue: 0.15),
            "B": Color(red: 0.15, green: 0.95, blue: 0.15),
            "X": Color(red: 0.15, green: 0.15, blue: 0.95),
            "Y": Color(red: 0.95, green: 0.95, blue: 0.15)
        ],
        backgroundColor: Color(red: 0.05, green: 0.05, blue: 0.05),
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
            "A": Color(red: 0.2, green: 0.8, blue: 0.3).opacity(0.7),
            "B": Color(red: 1.0, green: 0.3, blue: 0.2).opacity(0.7),
            "X": Color(red: 0.1, green: 0.5, blue: 1.0).opacity(0.7),
            "Y": Color(red: 1.0, green: 0.8, blue: 0.1).opacity(0.7)
        ],
        backgroundColor: Color.black.opacity(0.3),
        borderColor: Color.white.opacity(0.3),
        shadowOpacity: 0.15,
        cornerRadius: 16
    )

    static let neon = WiiUControllerSkin(
        name: "Neon",
        dpadColor: Color(red: 0.0, green: 1.0, blue: 0.8),
        buttonColors: [
            "A": Color(red: 0.0, green: 1.0, blue: 0.3),
            "B": Color(red: 1.0, green: 0.0, blue: 0.5),
            "X": Color(red: 0.0, green: 0.5, blue: 1.0),
            "Y": Color(red: 1.0, green: 0.85, blue: 0.0)
        ],
        backgroundColor: Color(red: 0.02, green: 0.02, blue: 0.05),
        borderColor: Color(red: 0.0, green: 1.0, blue: 0.8).opacity(0.4),
        shadowOpacity: 0.6,
        cornerRadius: 20
    )

    static let darkMode = WiiUControllerSkin(
        name: "Dark Mode",
        dpadColor: Color(red: 0.4, green: 0.4, blue: 0.4),
        buttonColors: [
            "A": Color(red: 0.1, green: 0.6, blue: 0.2),
            "B": Color(red: 0.8, green: 0.15, blue: 0.1),
            "X": Color(red: 0.0, green: 0.35, blue: 0.9),
            "Y": Color(red: 0.9, green: 0.65, blue: 0.0)
        ],
        backgroundColor: Color(red: 0.08, green: 0.08, blue: 0.1),
        borderColor: Color.white.opacity(0.08),
        shadowOpacity: 0.6,
        cornerRadius: 18
    )

    static let lightMode = WiiUControllerSkin(
        name: "Light Mode",
        dpadColor: Color(red: 0.5, green: 0.5, blue: 0.5),
        buttonColors: [
            "A": Color(red: 0.1, green: 0.8, blue: 0.2),
            "B": Color(red: 1.0, green: 0.2, blue: 0.1),
            "X": Color(red: 0.0, green: 0.3, blue: 1.0),
            "Y": Color(red: 1.0, green: 0.8, blue: 0.0)
        ],
        backgroundColor: Color(red: 0.9, green: 0.9, blue: 0.92),
        borderColor: Color.black.opacity(0.1),
        shadowOpacity: 0.15,
        cornerRadius: 20
    )

    static let custom = WiiUControllerSkin(
        name: "Custom",
        dpadColor: Color(red: 0.4, green: 0.6, blue: 0.8),
        buttonColors: [
            "A": Color(red: 0.6, green: 0.3, blue: 0.8),
            "B": Color(red: 0.8, green: 0.3, blue: 0.6),
            "X": Color(red: 0.3, green: 0.8, blue: 0.6),
            "Y": Color(red: 0.8, green: 0.6, blue: 0.3)
        ],
        backgroundColor: Color(red: 0.1, green: 0.12, blue: 0.15),
        borderColor: Color(red: 0.4, green: 0.6, blue: 0.8).opacity(0.3),
        shadowOpacity: 0.4,
        cornerRadius: 20
    )

    // MARK: - Game-Themed

    static let marioTheme = WiiUControllerSkin(
        name: "Mario Theme",
        dpadColor: Color(red: 0.95, green: 0.3, blue: 0.0),
        buttonColors: [
            "A": Color(red: 0.2, green: 0.8, blue: 0.3),
            "B": Color(red: 0.95, green: 0.2, blue: 0.1),
            "X": Color(red: 0.95, green: 0.8, blue: 0.0),
            "Y": Color(red: 0.2, green: 0.4, blue: 0.95)
        ],
        backgroundColor: Color(red: 0.95, green: 0.4, blue: 0.0).opacity(0.1),
        borderColor: Color(red: 0.95, green: 0.3, blue: 0.0).opacity(0.3),
        shadowOpacity: 0.4,
        cornerRadius: 20
    )

    static let zeldaTheme = WiiUControllerSkin(
        name: "Zelda Theme",
        dpadColor: Color(red: 0.8, green: 0.7, blue: 0.2),
        buttonColors: [
            "A": Color(red: 0.8, green: 0.7, blue: 0.2),
            "B": Color(red: 0.3, green: 0.6, blue: 0.2),
            "X": Color(red: 0.2, green: 0.5, blue: 0.8),
            "Y": Color(red: 0.8, green: 0.2, blue: 0.2)
        ],
        backgroundColor: Color(red: 0.1, green: 0.08, blue: 0.12),
        borderColor: Color(red: 0.8, green: 0.7, blue: 0.2).opacity(0.25),
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Button(action: { showingSelector.toggle() }) {
                    Text(selectedSkin.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 0.4, green: 0.6, blue: 1.0))
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
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

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
                        .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
            .cornerRadius(8)
        }
    }
}
