import SwiftUI

struct LibrarySettingsSection: View {
    @AppStorage(LibraryCardStyle.sizeStorageKey) private var cardSize = 1.0
    @ObservedObject var gameManager: GameManager
    @AppStorage(LibraryCardStyle.storageKey) private var cardStyleRaw = LibraryCardStyle.defaultValue.rawValue
    @AppStorage(CoverStylePreference.storageKey) private var coverRaw = CoverStylePreference.defaultValue.rawValue
    @AppStorage("muffin.library.sortOrder") private var sortRaw = LibrarySortOrder.title.rawValue
    @AppStorage(LibraryGrouping.storageKey) private var groupingRaw = LibraryGrouping.defaultValue.rawValue
    @AppStorage(LibraryFilter.storageKey) private var filterRaw = LibraryFilter.defaultValue.rawValue
    @AppStorage(LibraryTapAction.storageKey) private var tapActionRaw = LibraryTapAction.defaultValue.rawValue
    @AppStorage(SettingsMode.storageKey) private var modeRaw = SettingsMode.defaultValue.rawValue

    var body: some View {
        Section {
            SettingsRow(label: "Games", value: "\(gameManager.games.count)", icon: "square.grid.2x2")
            SettingsRow(label: "Favourites", value: "\(gameManager.favorites.count)", icon: "heart")
            Picker(selection: Binding(get: { CoverStylePreference(stored: coverRaw).rawValue }, set: { coverRaw = $0 })) {
                ForEach(CoverStylePreference.allCases) { mode in Text(mode.title).tag(mode.rawValue) }
            } label: {
                Label("Covers", systemImage: "cube")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .pickerStyle(.segmented)
            Picker(selection: $cardStyleRaw) {
                ForEach(LibraryCardStyle.choices) { style in
                    Text(style.title).tag(style.rawValue)
                }
            } label: {
                Label("Show games as", systemImage: "square.grid.2x2")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Card size", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Text("\(Int((cardSize * 100).rounded()))%")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Button("Reset") { cardSize = LibraryCardStyle.sizeDefault }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .buttonStyle(.borderless)
                        .disabled(abs(cardSize - LibraryCardStyle.sizeDefault) < 0.001)
                        .accessibilityLabel("Reset card size")
                }
                Slider(value: $cardSize, in: LibraryCardStyle.sizeRange, step: 0.05)
                    .tint(MuffinTheme.accentText)
            }
            Picker(selection: $tapActionRaw) {
                ForEach(LibraryTapAction.allCases) { action in
                    Text(action.title).tag(action.rawValue)
                }
            } label: {
                Label("Tap a game to", systemImage: "hand.tap")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            Picker(selection: $sortRaw) {
                ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                    Text(order.title).tag(order.rawValue)
                }
            } label: {
                Label("Sort by", systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            if SettingsMode.isAdvanced(raw: modeRaw) {
                Picker(selection: $groupingRaw) {
                    ForEach(LibraryGrouping.allCases) { grouping in
                        Text(grouping.title).tag(grouping.rawValue)
                    }
                } label: {
                    Label("Group by", systemImage: "rectangle.grid.1x2")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                Picker(selection: $filterRaw) {
                    ForEach(LibraryFilter.allCases) { filter in
                        Text(filter.title).tag(filter.rawValue)
                    }
                } label: {
                    Label("Show", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }
            LinkedLocationsRows(gameManager: gameManager)
            NavigationLink {
                GraphicPacksView()
            } label: {
                Label("Graphic Packs", systemImage: "wand.and.stars")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            Button(role: .destructive) {
                // Back to how a fresh install lays out the library, and no art pack applied.
                let d = UserDefaults.standard
                for key in [LibraryCardStyle.storageKey, LibraryCardStyle.sizeStorageKey, LibraryGrouping.storageKey,
                            LibraryFilter.storageKey, "muffin.library.sortOrder", CoverStylePreference.storageKey,
                            "muffin.art.appliedPack", "muffin.art.preApplySnapshot"] {
                    d.removeObject(forKey: key)
                }
                for key in [LibraryCardStyle.storageKey, LibraryCardStyle.sizeStorageKey, LibraryGrouping.storageKey,
                            LibraryFilter.storageKey, "muffin.library.sortOrder", CoverStylePreference.storageKey,
                            "muffin.art.appliedPack", "muffin.art.preApplySnapshot"] {
                    d.removeObject(forKey: key)
                }
                NotificationCenter.default.post(name: .muffinCoverArtSourcesChanged, object: nil)
            } label: {
                Label("Reset library layout", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        } header: {
            SettingsSectionHeader("Library", icon: "books.vertical", accent: .content)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
