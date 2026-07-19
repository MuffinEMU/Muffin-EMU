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
        // NavigationStack needs iOS 16+; this project's deployment target is 15.0.
        NavigationView {
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
                        SettingsRow(label: "Games", value: "\(gameManager.games.count)")
                        SettingsRow(label: "Favorites", value: "\(gameManager.favorites.count)")
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)

                    Section("About") {
                        SettingsRow(label: "Version", value: Bundle.main.appVersionString)
                        Link(destination: URL(string: "https://github.com/bward-dev1/cemu-ios-muffin")!) {
                            Label("View on GitHub", systemImage: "arrow.up.right.square")
                        }
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)
                }
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
        .navigationViewStyle(.stack)
    }
}

/// LabeledContent needs iOS 16+; this project's deployment target is 15.0.
private struct SettingsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(MuffinTheme.brownMid)
        }
    }
}
