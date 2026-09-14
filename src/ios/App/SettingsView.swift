import SwiftUI

/// Every section below is its own View struct, most of them in their own file under
/// Settings/. This Form used to be one ~700-line expression, and Swift's type
/// checker gave up on it outright: "the compiler is unable to type-check this
/// expression in reasonable time". SwiftUI's generic ViewBuilder nesting makes
/// inference cost grow sharply with how much is inlined in one expression, and it
/// grew again once Graphics picked up three new controls - so the fix here isn't
/// "fewer siblings in a bigger expression" (the settingsGroup1..4 split this
/// replaces), it's siblings that are themselves concrete named types. A Section
/// literal with a dozen modifiers costs the type checker far more to infer than one
/// call to a struct whose own body already type-checked on its own.
///
/// ViewBuilder's buildBlock only goes up to 10 children per block, though, and
/// there are more than 10 sections - hence formTop/formBottom below rather than one
/// flat list.
struct SettingsView: View {
    @ObservedObject var gameManager: GameManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingIconPicker = false
    @State private var showingThemePicker = false

    // Emulation-first ordering: what decides whether a game runs, then how it
    // looks, then everything around it. CPU and Graphics are worth more to a
    // player than anything below them, so they lead.
    @ViewBuilder private var formTop: some View {
        CPUSettingsSection()
        GraphicsSettingsSection()
        ShaderCompilationSection()
        ShaderCacheSection()
        EmulatedClockSection()
        OnScreenControlsSection()
        LibrarySettingsSection(gameManager: gameManager)
        KeysSettingsSection()
    }

    @ViewBuilder private var formBottom: some View {
        FilesSettingsSection()
        DeviceReportSection()
        DiagnosticsSection()
        AppearanceSettingsSection(showingIconPicker: $showingIconPicker, showingThemePicker: $showingThemePicker)
        PremiumSettingsSection()
        PreviewPadSection()
        AboutSettingsSection()
    }

    var body: some View {
        // NavigationStack needs iOS 16+; this project's deployment target is 15.0.
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient
                    .ignoresSafeArea()

                Form {
                    formTop
                    formBottom
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
            .sheet(isPresented: $showingThemePicker) {
                ThemePickerView()
            }
        }
        .navigationViewStyle(.stack)
    }
}
