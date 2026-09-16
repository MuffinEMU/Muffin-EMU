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
        DisplaySettingsSection()
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
        OverlaySettingsSection()
        NotificationSettingsSection()
        AudioSettingsSection()
        AboutSettingsSection()
    }

    // formTop/formBottom are already at ViewBuilder's 10-child ceiling (see the doc
    // comment above) - accounts, network service and the emulated-devices toggles landed
    // after both were already full, so they get a third block rather than pushing either
    // one past 10.
    @ViewBuilder private var formExtra: some View {
        AccountSettingsSection()
        NetworkServiceSettingsSection()
        EmulatedDevicesSettingsSection()
    }

    /// The ZStack behind this Form has painted MuffinTheme.backgroundGradient since the
    /// screen was written, and on iOS 15 none of it was ever visible: a SwiftUI Form is
    /// a grouped list whose own background is opaque systemGroupedBackground, so the
    /// brand gradient sat behind a flat grey sheet the whole time. iOS 16's
    /// scrollContentBackground(.hidden) is the supported way to drop that fill, and it
    /// is what finally lets Settings read as part of MuffinEMU rather than as iOS's own
    /// settings app with some coloured labels in it.
    ///
    /// Deliberately not fixed on iOS 15 via `UITableView.appearance().backgroundColor`:
    /// that is process-wide UIKit appearance state, and it would strip the background
    /// out of every other list in the app (the library, the skin pickers, Graphic Packs)
    /// to style this one screen. iOS 15 keeps the grey Form it has always had.
    @ViewBuilder private var settingsForm: some View {
        if #available(iOS 16.0, *) {
            Form {
                formTop
                formBottom
                formExtra
            }
            .scrollContentBackground(.hidden)
            // Once the grey sheet is gone the rows themselves are still iOS's
            // secondarySystemGroupedBackground, which against a warm gradient reads as
            // grey cards someone forgot to theme. cream is the same fill MuffinCard uses
            // for every other surface in the app, so Settings becomes the same material
            // as the library and the pickers instead of a third thing.
            .listRowBackground(MuffinTheme.cream)
        } else {
            Form {
                formTop
                formBottom
                formExtra
            }
        }
    }

    var body: some View {
        // NavigationStack needs iOS 16+; this project's deployment target is 15.0.
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient
                    .ignoresSafeArea()

                settingsForm
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(MuffinTheme.pixelBlue)
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
