import SwiftUI

struct FilesSettingsSection: View {
    var body: some View {
        Section {
            Text(Self.documentsPathHint)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        } header: {
            SettingsSectionHeader("Your Files", icon: "folder", accent: .system)
        } footer: {
            InfoButton.footer(
                "ROMs, saves, shader caches and keys.txt live in this folder.",
                title: "Your Files",
                text: "Normally this is Files \u{2192} On My iPhone/iPad \u{2192} MuffinEMU. If you installed through LiveContainer, iOS lists the folder under LiveContainer instead; use the path shown above to find it.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    /// Computed live rather than written down, for the same reason BootFailureView's
    /// crash-log hint is: only the OS knows what $HOME actually resolved to for this
    /// install, and that differs between a normal signed install and a sideloaded one.
    /// The Wii U Keys section already tells someone to "open MuffinEMU in the Files app" -
    /// this is the exact path that instruction means, spelled out, so it is followable
    /// rather than a folder name to guess at.
    private static var documentsPathHint: String {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return "Could not resolve a Documents folder for this install."
        }
        return url.path
    }
}
