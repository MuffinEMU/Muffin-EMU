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
    // Observed so flipping Classic UI or Disable Liquid Glass repaints this subtree
    // immediately. MuffinTheme and the shared row/header components read the same store
    // through UIStyle's static accessors, but static reads cannot invalidate a view on
    // their own - something in the tree has to be watching, and this is it.
    @ObservedObject private var uiStyle = UIStyleStore.shared

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

    /// A plain Form, with iOS's own opaque grouped-list background.
    ///
    /// The ZStack behind it paints MuffinTheme.backgroundGradient and that gradient has
    /// never been visible, because a SwiftUI Form is a grouped list whose background is
    /// an opaque systemGroupedBackground sitting on top of it. That looks like a bug and
    /// it was treated as one: on 2026-09-15 this gained
    /// `.scrollContentBackground(.hidden)` to drop the grey sheet plus
    /// `.listRowBackground(MuffinTheme.cream)` so the rows would not read as untinted
    /// grey cards on a warm gradient.
    ///
    /// It was reverted the same day, on device, in Void's words: "it looks really
    /// weird and you can't even read any text."
    ///
    /// DO NOT RE-APPLY THIS WITHOUT SOLVING THE TEXT PROBLEM FIRST. The reason it fails
    /// is not the background - it is that this Form sets
    /// `.foregroundColor(MuffinTheme.brownDarkest)` on its sections, and every section
    /// header and row label is coloured for a light grouped-list ground. Put those same
    /// colours on cream over a saturated gradient and contrast collapses; in dark mode
    /// brownDarkest is a LIGHT cream tone, so light-on-cream leaves the text all but
    /// invisible. Making this work means re-deriving the text colours from whatever fill
    /// the rows actually end up with, in both appearances - a real piece of work, not a
    /// two-line modifier.
    ///
    /// The grey Form is not a placeholder anyone forgot to theme. It is legible, and
    /// legible beat on-brand here.
    private var settingsForm: some View {
        Form {
            formTop
            formBottom
            formExtra
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
