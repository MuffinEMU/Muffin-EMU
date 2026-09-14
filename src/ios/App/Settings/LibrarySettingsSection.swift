import SwiftUI

struct LibrarySettingsSection: View {
    @ObservedObject var gameManager: GameManager

    var body: some View {
        Section("Library") {
            SettingsRow(label: "Games", value: "\(gameManager.games.count)")
            SettingsRow(label: "Favorites", value: "\(gameManager.favorites.count)")
            NavigationLink("Graphic Packs") {
                GraphicPacksView()
            }
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
