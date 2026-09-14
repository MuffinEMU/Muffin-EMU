import SwiftUI

/// Icon and theme, near the end of the Form rather than up front - this is identity,
/// not a setting that changes how the emulator runs, and the sheets it opens are
/// owned by the parent view (IconPickerView/ThemePickerView) since the bindings
/// that present them have to live where those .sheet(...) modifiers are attached.
struct AppearanceSettingsSection: View {
    @Binding var showingIconPicker: Bool
    @Binding var showingThemePicker: Bool

    var body: some View {
        Section("Appearance") {
            Button(action: { showingIconPicker = true }) {
                Label("App Icon", systemImage: "app.badge")
            }
            .foregroundColor(MuffinTheme.brownDarkest)

            // Deliberately its own row, not a sub-option under App Icon: theme and
            // icon are picked independently (see ThemePickerView's header) - someone
            // can love the Strawberry icon and the Galaxy Space theme together.
            Button(action: { showingThemePicker = true }) {
                Label("Theme", systemImage: "paintpalette")
            }
            .foregroundColor(MuffinTheme.brownDarkest)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}
