import SwiftUI

/// Every section is its own View struct (most under Settings/), so the type checker isn't
/// asked to infer one huge Form expression. ViewBuilder allows at most 10 children per
/// block, hence the groups below.
struct SettingsView: View {
    // Observed so flipping Classic UI or Flat surfaces repaints this subtree immediately.
    @ObservedObject private var uiStyle = UIStyleStore.shared

    @ObservedObject var gameManager: GameManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingIconPicker = false
    @State private var showingThemePicker = false
    /// Basic hides the advanced rows (see AdvancedSettings); this view only needs it for whole sections.
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue

    // Ordered by what players look for first: Keys, Graphics (Resolution), Controls, Display, Theme, then
    // sound, the library and accounts, then the CPU and shader internals, then housekeeping with About
    // and Reset last. The Settings mode picker and the quick-help section sit above all of it.
    @ViewBuilder private var formFirst: some View {
        KeysSettingsSection()
        GraphicsSettingsSection()
    }

    @ViewBuilder private var formInput: some View {
        OnScreenControlsSection()
        PreviewPadSection()
        MotionSettingsSection()
        DisplaySettingsSection()
    }

    @ViewBuilder private var formApp: some View {
        AppearanceSettingsSection(showingIconPicker: $showingIconPicker, showingThemePicker: $showingThemePicker)
        PremiumSettingsSection()
        AudioSettingsSection()
        OverlaySettingsSection()
        NotificationSettingsSection()
    }

    @ViewBuilder private var formContent: some View {
        LibrarySettingsSection(gameManager: gameManager)
        WiiUMenuSettingsSection()
        AccountSettingsSection()
        NetworkServiceSettingsSection()
        EmulatedDevicesSettingsSection()
    }

    // What decides how fast a game runs, once Resolution is sorted.
    @ViewBuilder private var formCore: some View {
        CPUSettingsSection()
        ShaderCompilationSection()
        ShaderCacheSection()
        if SettingsMode.isAdvanced(raw: settingsModeRaw) {
            EmulatedClockSection()
        }
    }

    @ViewBuilder private var formSystem: some View {
        FilesSettingsSection()
        SettingsBackupSection()
        DeviceReportSection()
        DiagnosticsSection()
        AboutSettingsSection()
    }

    /// Plain Form on iOS's grouped background. Hiding the background makes the text
    /// unreadable with the current colours.
    private var settingsForm: some View {
        Form {
            SettingsModeSection()
            QuickHelpSection()
            formFirst
            formInput
            formApp
            formContent
            formCore
            formSystem
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
            .muffinOpaqueNavigationBar(MuffinTheme.formGround)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(MuffinTheme.accentText)
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
