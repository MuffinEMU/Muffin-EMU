import SwiftUI

struct LibrarySettingsSection: View {
    @ObservedObject var gameManager: GameManager
    @AppStorage(LibraryCardStyle.storageKey) private var cardStyleRaw = LibraryCardStyle.defaultValue.rawValue
    @AppStorage("muffin.library.sortOrder") private var sortRaw = LibrarySortOrder.title.rawValue
    @AppStorage(LibraryGrouping.storageKey) private var groupingRaw = LibraryGrouping.defaultValue.rawValue
    @AppStorage(LibraryFilter.storageKey) private var filterRaw = LibraryFilter.defaultValue.rawValue
    @AppStorage(SettingsMode.storageKey) private var modeRaw = SettingsMode.defaultValue.rawValue

    var body: some View {
        Section {
            SettingsRow(label: "Games", value: "\(gameManager.games.count)", icon: "square.grid.2x2")
            SettingsRow(label: "Favorites", value: "\(gameManager.favorites.count)", icon: "heart")
            Picker(selection: $cardStyleRaw) {
                ForEach(LibraryCardStyle.allCases) { style in
                    Text(style.title).tag(style.rawValue)
                }
            } label: {
                Label("Show games as", systemImage: "square.grid.2x2")
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
            NavigationLink {
                GraphicPacksView()
            } label: {
                Label("Graphic Packs", systemImage: "wand.and.stars")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        } header: {
            SettingsSectionHeader("Library", icon: "books.vertical", accent: .content)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
