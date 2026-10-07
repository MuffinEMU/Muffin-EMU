// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

enum ControllerCategory: String, CaseIterable {
    case wiiU = "Wii U"
    case indigo = "Indigo"
    case primary = "Primary"
    case lilacGrey = "Lilac Grey"
    case redAndCream = "Red and Cream"
    case charcoal = "Charcoal"
    case blueAndRose = "Blue and Rose"
    case green = "Green"
    case slate = "Slate"
    case arcade = "Arcade"
    case modern = "Modern"
    case gameThemed = "Colour Themes"

    var displayName: String {
        self.rawValue
    }

    var skins: [WiiUControllerSkin] {
        switch self {
        case .wiiU:
            return [.standard, .sky, .custom]
        case .indigo:
            return [.indigo]
        case .primary:
            return [.primary]
        case .lilacGrey:
            return [.lilacGrey]
        case .redAndCream:
            return [.redAndCream]
        case .charcoal:
            return [.charcoal]
        case .blueAndRose:
            return [.blueAndRose]
        case .green:
            return [.green]
        case .slate:
            return [.slate]
        case .arcade:
            return [.arcadeCabinet, .blackAndGold]
        case .modern:
            return [.minimal, .glass, .neon, .darkMode, .lightMode]
        case .gameThemed:
            return [.sunsetOrange, .forestGold]
        }
    }
}

struct OrganizedControllerSkinSelector: View {
    @Binding var selectedSkin: WiiUControllerSkin
    @State private var expandedCategory: ControllerCategory? = .wiiU
    @State private var showingSelector = false
    /// Compact on a landscape iPhone, where a 400-point list ran off the bottom of the
    /// screen under the top bar and its last skins could not be reached.
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        VStack(spacing: 0) {
            // The whole row opens the list. Only the skin name used to, a target about
            // fifteen points tall.
            Button(action: { showingSelector.toggle() }) {
                HStack {
                    Text("Controller Skin")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(MuffinTheme.brownDarkest)

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 12))
                        Text(selectedSkin.name)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(LegibleInk.ensure(MuffinTheme.pixelBlue, on: MuffinTheme.cream))
                }
                .padding(12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(MuffinTheme.cream)
            .accessibilityValue(selectedSkin.name)
            .accessibilityHint(showingSelector ? "Hides the list of skins" : "Shows the list of skins")

            if showingSelector {
                Divider()
                    .background(MuffinTheme.wrapper)

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
                .frame(maxHeight: verticalSizeClass == .compact ? 180 : 400)
            }
        }
        .background(MuffinTheme.cream)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(MuffinTheme.wrapper, lineWidth: 1)
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
                        .foregroundColor(LegibleInk.ensure(MuffinTheme.pixelBlue, on: MuffinTheme.wrapper,
                                                           minimum: LegibleInk.glyph))

                    Text(category.displayName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(MuffinTheme.brownDarkest)

                    Spacer()

                    Text("(\(category.skins.count))")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(LegibleInk.ensure(MuffinTheme.brownMid, on: MuffinTheme.wrapper))
                }
                .padding(12)
                .background(MuffinTheme.wrapper.opacity(0.4))
                .cornerRadius(8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

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
                .background(MuffinTheme.wrapper.opacity(0.2))
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
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(MuffinTheme.brownDarkest)

                    // Outlined, so the white and glass skins' swatches don't vanish into
                    // the cream behind them.
                    HStack(spacing: 4) {
                        Circle()
                            .fill(skin.dpadColor)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(MuffinTheme.brownDarkest.opacity(0.35), lineWidth: 0.75))

                        Circle()
                            .fill(skin.buttonColors["A"] ?? Color.gray)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(MuffinTheme.brownDarkest.opacity(0.35), lineWidth: 0.75))

                        Circle()
                            .fill(skin.buttonColors["B"] ?? Color.gray)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(MuffinTheme.brownDarkest.opacity(0.35), lineWidth: 0.75))

                        Circle()
                            .fill(skin.buttonColors["X"] ?? Color.gray)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(MuffinTheme.brownDarkest.opacity(0.35), lineWidth: 0.75))

                        Circle()
                            .fill(skin.buttonColors["Y"] ?? Color.gray)
                            .frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(MuffinTheme.brownDarkest.opacity(0.35), lineWidth: 0.75))
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(LegibleInk.ensure(MuffinTheme.pixelBlue, on: MuffinTheme.wrapper,
                                                           minimum: LegibleInk.glyph))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .frame(minHeight: 44)
            .background(isSelected ? MuffinTheme.wrapper : MuffinTheme.cream)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(skin.name) skin")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct OrganizedControllerSkinSelectorPreview: View {
    @State private var selectedSkin = WiiUControllerSkin.standard

    var body: some View {
        OrganizedControllerSkinSelector(selectedSkin: $selectedSkin)
            .padding()
            .background(MuffinTheme.backgroundGradient)
    }
}

#Preview {
    OrganizedControllerSkinSelectorPreview()
}
