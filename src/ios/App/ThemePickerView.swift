import SwiftUI

/// Picks which MuffinTheme palette is active - completely independent of
/// IconPickerView. Every icon in IconManifest has a matching theme here (see
/// MuffinThemePresets.swift), shown first and labelled "Matches your icon", but
/// nothing stops picking any theme with any icon: liking Strawberry's icon but
/// preferring the Galaxy Space theme is a fully supported combination, not a
/// workaround. See MuffinThemeStore's header for why that decoupling is deliberate.
struct ThemePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = MuffinThemeStore.shared
    private let currentIconId = UIApplication.shared.alternateIconName
        .map { $0.replacingOccurrences(of: "AltIcon-", with: "") } ?? "original"

    private var orderedThemes: [MuffinThemeDefinition] {
        let all = MuffinThemePresets.all
        guard let matchIndex = all.firstIndex(where: { $0.iconId == currentIconId }) else { return all }
        var rest = all
        let match = rest.remove(at: matchIndex)
        return [match] + rest
    }

    var body: some View {
        // NavigationStack needs iOS 16+; this project's deployment target is 15.0.
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient.ignoresSafeArea()

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                        ForEach(orderedThemes) { theme in
                            ThemeOptionCard(
                                theme: theme,
                                isSelected: theme.id == store.current.id,
                                matchesCurrentIcon: theme.iconId == currentIconId,
                                onSelect: { store.select(theme) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(MuffinSecondaryButtonStyle())
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private struct ThemeOptionCard: View {
    let theme: MuffinThemeDefinition
    let isSelected: Bool
    let matchesCurrentIcon: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            MuffinCard {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        swatchPreview
                            .frame(height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isSelected ? swatchAccent : swatchOutline, lineWidth: isSelected ? 3 : 1)
                            )

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(swatchAccent)
                                .background(Color.white, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }

                    Text(theme.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(MuffinTheme.brownDarkest)
                        .lineLimit(1)

                    if matchesCurrentIcon {
                        Text("Matches your icon")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(MuffinTheme.brownMid)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    /// A small live preview swatch built straight from this theme's own hex pairs -
    /// not a screenshot of the app in that theme, but the same background gradient
    /// plus accent dot every card in the app would actually render with it active,
    /// so the card is a true preview rather than a guess.
    private var swatchGradient: LinearGradient {
        let stops = theme.backgroundStopsLight
        guard stops.count >= 2 else {
            return LinearGradient(
                colors: [Color(hex: theme.backgroundTopLight), Color(hex: theme.backgroundBottomLight)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        // Colours evenly, NOT at the theme's own stop locations. Those locations are
        // tuned for a full screen - the rainbow is spent in the top 7.5% because the
        // header is a thin strip of a tall one - and replaying them inside a 56pt
        // sample would draw a two-pixel rainbow above 52pt of flat cream. Spreading
        // the same colours in the same order fills the swatch with what the theme is.
        return LinearGradient(
            colors: stops.map { Color(hex: $0) },
            startPoint: .top, endPoint: .bottom
        )
    }

    private var swatchPreview: some View {
        // Mirrors MuffinTheme.backgroundGradient, including the multi-stop path, so a
        // theme that paints a rainbow shows a rainbow in the grid you pick it from.
        // Reading only backgroundTop/Bottom here showed Autism Muffin as a plain
        // pink-to-violet fade - nothing you could recognise the theme by.
        //
        // Light stops only: the swatch is a fixed sample, not a live surface, and the
        // cards around it are light-mode-ish regardless.
        swatchGradient
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color(hex: theme.pixelBlueLight))
                    .frame(width: 18, height: 18)
                    .padding(6)
            }
    }

    private var swatchAccent: Color { Color(hex: theme.pixelBlueLight) }
    private var swatchOutline: Color { Color(hex: theme.wrapperLight) }
}
