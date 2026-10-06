import SwiftUI

/// Every section is its own View struct (most under Settings/), so the type checker isn't
/// asked to infer one huge Form expression. ViewBuilder allows at most 10 children per
/// block, hence the five groups below.
struct SettingsView: View {
    // Observed so flipping Classic UI or Flat surfaces repaints this subtree immediately.
    @ObservedObject private var uiStyle = UIStyleStore.shared

    @ObservedObject var gameManager: GameManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingIconPicker = false
    @State private var showingThemePicker = false
    @ObservedObject private var accountSheets = AccountSheetRouter.shared
    /// Basic hides the advanced rows (see AdvancedSettings); this view only needs it for whole sections.
    @AppStorage(SettingsMode.storageKey) private var settingsModeRaw = SettingsMode.defaultValue.rawValue

    // Grouped the way the section headers are coloured (SettingsSectionAccent): what decides
    // whether a game runs, then what the player touches, sees and hears, then what the app
    // holds for them, then identity, then housekeeping with About and Reset last.
    @ViewBuilder private var formCore: some View {
        CPUSettingsSection()
        GraphicsSettingsSection()
        ShaderCompilationSection()
        ShaderCacheSection()
        if SettingsMode.isAdvanced(raw: settingsModeRaw) {
            EmulatedClockSection()
        }
    }

    @ViewBuilder private var formInput: some View {
        OnScreenControlsSection()
        PreviewPadSection()
        MotionSettingsSection()
        DisplaySettingsSection()
        AudioSettingsSection()
        OverlaySettingsSection()
        NotificationSettingsSection()
    }

    @ViewBuilder private var formContent: some View {
        LibrarySettingsSection(gameManager: gameManager)
        KeysSettingsSection()
        WiiUMenuSettingsSection()
        AccountSettingsSection()
        NetworkServiceSettingsSection()
        EmulatedDevicesSettingsSection()
    }

    @ViewBuilder private var formApp: some View {
        AppearanceSettingsSection(showingIconPicker: $showingIconPicker, showingThemePicker: $showingThemePicker)
        PremiumSettingsSection()
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
            formCore
            formInput
            formContent
            formApp
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
            .sheet(isPresented: $accountSheets.showingCreateAccount, onDismiss: accountSheets.sheetClosed) {
                CreateAccountView()
            }
        }
        .navigationViewStyle(.stack)
    }
}
