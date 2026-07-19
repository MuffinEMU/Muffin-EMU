import SwiftUI

enum ControllerCategory: String, CaseIterable {
    case wiiU = "Wii U"
    case gameCube = "GameCube"
    case nintendo64 = "Nintendo 64"
    case snes = "SNES"
    case nes = "NES"
    case switchPro = "Switch Pro"
    case playStation = "PlayStation"
    case xbox = "Xbox"
    case steamDeck = "Steam Deck"
    case arcade = "Arcade"
    case modern = "Modern/Minimalist"
    case gameThemed = "Game-Themed"

    var displayName: String {
        self.rawValue
    }

    var skins: [WiiUControllerSkin] {
        switch self {
        case .wiiU:
            return [.standard, .wiiUOriginal, .custom]
        case .gameCube:
            return [.gameCube]
        case .nintendo64:
            return [.nintendo64]
        case .snes:
            return [.superNintendo]
        case .nes:
            return [.nes]
        case .switchPro:
            return [.switchPro]
        case .playStation:
            return [.playStation]
        case .xbox:
            return [.xbox]
        case .steamDeck:
            return [.steamDeck]
        case .arcade:
            return [.arcadeCabinet, .segaGenesis]
        case .modern:
            return [.minimal, .glass, .neon, .darkMode, .lightMode]
        case .gameThemed:
            return [.marioTheme, .zeldaTheme]
        }
    }
}

struct OrganizedControllerSkinSelector: View {
    @Binding var selectedSkin: WiiUControllerSkin
    @State private var expandedCategory: ControllerCategory? = .wiiU
    @State private var showingSelector = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Controller Skin")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Button(action: { showingSelector.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 12))
                        Text(selectedSkin.name)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color(red: 0.4, green: 0.6, blue: 1.0))
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.03))

            if showingSelector {
                Divider()
                    .background(Color.white.opacity(0.1))

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(ControllerCategory.allCases, id: \.self) { category in
                            ControllerCategoryDropdown(
                                category: category,
                                isExpanded: expandedCategory == category,
                                selectedSkin: $selectedSkin,
                                onCategoryTap: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if expandedCategory == category {
                                            expandedCategory = nil
                                        } else {
                                            expandedCategory = category
                                        }
                                    }
                                },
                                onSkinSelect: {
                                    showingSelector = false
                                }
                            )
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 400)
            }
        }
        .background(Color.white.opacity(0.03))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
}

struct ControllerCategoryDropdown: View {
    let category: ControllerCategory
    let isExpanded: Bool
    @Binding var selectedSkin: WiiUControllerSkin
    let onCategoryTap: () -> Void
    let onSkinSelect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onCategoryTap) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 0.4, green: 0.6, blue: 1.0))

                    Text(category.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Text("(\(category.skins.count))")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                }
                .padding(12)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }

            if isExpanded {
                VStack(spacing: 6) {
                    ForEach(category.skins, id: \.name) { skin in
                        SkinOptionCompact(
                            skin: skin,
                            isSelected: selectedSkin.name == skin.name,
                            onSelect: {
                                selectedSkin = skin
                                onSkinSelect()
                            }
                        )
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.02))
                .cornerRadius(6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct SkinOptionCompact: View {
    let skin: WiiUControllerSkin
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(skin.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(skin.dpadColor)
                            .frame(width: 10, height: 10)

                        Circle()
                            .fill(skin.buttonColors["A"] ?? Color.gray)
                            .frame(width: 10, height: 10)

                        Circle()
                            .fill(skin.buttonColors["B"] ?? Color.gray)
                            .frame(width: 10, height: 10)

                        Circle()
                            .fill(skin.buttonColors["X"] ?? Color.gray)
                            .frame(width: 10, height: 10)

                        Circle()
                            .fill(skin.buttonColors["Y"] ?? Color.gray)
                            .frame(width: 10, height: 10)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 0.4, green: 0.9, blue: 0.4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(isSelected ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
            .cornerRadius(6)
        }
    }
}

#Preview {
    @Previewable @State var selectedSkin = WiiUControllerSkin.standard
    OrganizedControllerSkinSelector(selectedSkin: $selectedSkin)
        .padding()
        .background(Color(red: 0.05, green: 0.08, blue: 0.15))
}
