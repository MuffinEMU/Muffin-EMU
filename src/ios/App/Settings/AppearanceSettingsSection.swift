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
                Label("Theme", systemImage: "paintpalette")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundColor(MuffinTheme.brownDarkest)

            Toggle(isOn: $style.disableLiquidGlass) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Disable Liquid Glass")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Turns off the translucent, glassy material on cards and buttons. Layout and text stay as they are.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)
            // Redundant while Classic UI is on, and saying so beats leaving someone to
            // wonder why flipping it changes nothing: UIStyle.glassDisabled is already
            // true in that mode, because v2.0 had no glassy material to begin with.
            .disabled(style.useClassicUI)

            Toggle(isOn: $style.useClassicUI) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use Classic UI")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("The v2.0 look - flat cards, plain section headers, system-font rows. Every setting, button and feature stays exactly where it is.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)
        } header: {
            SettingsSectionHeader("Appearance", icon: "paintpalette", accent: .identity)
        } footer: {
            InfoButton.footer(
                "Both change how MuffinEMU looks and nothing about what it does.",
                title: "Appearance",
                text: "Disable Liquid Glass removes the translucent, glassy material from cards and buttons - the lighting pass that sits over their fill - and leaves the layout, spacing and typography alone.\n\nUse Classic UI goes further and restores the styling MuffinEMU had at v2.0: flat cards with one soft shadow, plain text section headers instead of icon chips, and system-font rows. It implies Disable Liquid Glass, because v2.0 had no glassy material to turn off.\n\nNeither removes anything. Every setting, toggle, button and screen added since v2.0 is still there and still does the same thing - this is not a v2.0 build, it is the current app wearing the old styling. Some newer screens will still look newer, because they did not exist to have a classic form.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
