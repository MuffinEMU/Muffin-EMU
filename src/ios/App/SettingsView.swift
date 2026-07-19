import SwiftUI

private extension Bundle {
    var appVersionString: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

struct SettingsView: View {
    @ObservedObject var gameManager: GameManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingIconPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                MuffinTheme.backgroundGradient
                    .ignoresSafeArea()

                Form {
                    Section("Appearance") {
                        Button(action: { showingIconPicker = true }) {
                            Label("App Icon", systemImage: "app.badge")
                        }
                        .foregroundColor(MuffinTheme.brownDarkest)
                    }

                    Section("Library") {
                        LabeledContent("Games", value: "\(gameManager.games.count)")
                        LabeledContent("Favorites", value: "\(gameManager.favorites.count)")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    Section("About") {
                        LabeledContent("Version", value: Bundle.main.appVersionString)
                        Link(destination: URL(string: "https://github.com/bward-dev1/cemu-ios-muffin")!) {
                            Label("View on GitHub", systemImage: "arrow.up.right.square")
                        }
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView()
            }
        }
    }
}
