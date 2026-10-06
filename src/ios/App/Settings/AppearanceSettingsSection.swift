import SwiftUI

/// Icon and theme, near the end of the Form rather than up front - this is identity,
/// not a setting that changes how the emulator runs, and the sheets it opens are
/// owned by the parent view (IconPickerView/ThemePickerView) since the bindings
/// that present them have to live where those .sheet(...) modifiers are attached.
struct AppearanceSettingsSection: View {
    @Binding var showingIconPicker: Bool
    @Binding var showingThemePicker: Bool

    // A real ObservedObject on the shared store rather than @AppStorage over the same
    // keys. The store is what MuffinTheme, SettingsSectionHeader and SettingsRow read
    // through, so binding to it is what makes a flip here repaint the app immediately
    // instead of at the next launch - the same reasoning PreviewPadSection's own doc
    // comment already spells out for PreviewPadStore.
    @ObservedObject private var style = UIStyleStore.shared
    // Observed so the row's value follows a change made in the picker sheet.
    @ObservedObject private var themeStore = MuffinThemeStore.shared

    var body: some View {
        Section {
            Button(action: { showingIconPicker = true }) {
                Label("App Icon", systemImage: "app.badge")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundColor(MuffinTheme.brownDarkest)

            // Deliberately its own row, not a sub-option under App Icon: theme and
            // icon are picked independently (see ThemePickerView's header) - someone
            // can love the Strawberry icon and the Galaxy Space theme together.
            Button(action: { showingThemePicker = true }) {
                HStack {
                    Label("Theme", systemImage: "paintpalette")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer(minLength: 12)
                    Text(themeStore.current.name)
                        .font(.system(size: 15, design: .rounded))
                        .foregroundColor(MuffinTheme.brownMid)
                }
            }
            .foregroundColor(MuffinTheme.brownDarkest)

            Toggle(isOn: $style.disableLiquidGlass) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Flat surfaces")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(style.useClassicUI
                         ? "Already on while Classic UI is on."
                         : "Removes the highlights and shading on cards and buttons.")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            .tint(MuffinTheme.accentText)
            // Redundant while Classic UI is on, and saying so beats leaving someone to
            // wonder why flipping it changes nothing: UIStyle.glassDisabled is already
            // true in that mode, because v2.0 had no glassy material to begin with.
            .disabled(style.useClassicUI)

            Toggle(isOn: $style.useClassicUI) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use Classic UI")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("The v2.0 look: flat cards, plain headers, system-font rows.")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
            }
            .tint(MuffinTheme.accentText)
        } header: {
            SettingsSectionHeader("Appearance", icon: "paintpalette", accent: .identity)
        } footer: {
            InfoButton.footer(
                "Both change how MuffinEMU looks, not what it does.",
                title: "Appearance",
                text: "Flat surfaces removes the soft highlights on cards and buttons.\n\nClassic UI restores the flat v2.0 styling: plain cards, text headers, system-font rows. It turns on flat surfaces too. All settings and screens are still there; newer screens just have no classic form.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
