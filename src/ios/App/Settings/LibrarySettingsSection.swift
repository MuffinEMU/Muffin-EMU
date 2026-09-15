import SwiftUI

struct LibrarySettingsSection: View {
    @ObservedObject var gameManager: GameManager

    var body: some View {
        Section {
            SettingsRow(label: "Games", value: "\(gameManager.games.count)", icon: "square.grid.2x2")
            SettingsRow(label: "Favorites", value: "\(gameManager.favorites.count)", icon: "heart")
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
