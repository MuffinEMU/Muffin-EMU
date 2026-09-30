import SwiftUI

/// Every section is its own View struct (most under Settings/), so the type checker isn't
/// asked to infer one huge Form expression. ViewBuilder allows at most 10 children per
/// block, hence formTop/formBottom/formExtra.
struct SettingsView: View {
    // Observed so flipping Classic UI or Flat surfaces repaints this subtree immediately.
    @ObservedObject private var uiStyle = UIStyleStore.shared

    @ObservedObject var gameManager: GameManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingIconPicker = false
    @State private var showingThemePicker = false

    // Ordered by importance: what decides whether a game runs, then how it looks, then the rest.
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
        WiiUMenuSettingsSection()
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

    @ViewBuilder private var formExtra: some View {
        MotionSettingsSection()
        AccountSettingsSection()
        NetworkServiceSettingsSection()
        EmulatedDevicesSettingsSection()
    }

    /// Plain Form on iOS's grouped background. Hiding the background makes the text
    /// unreadable with the current colours.
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
