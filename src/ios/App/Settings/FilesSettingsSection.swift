import SwiftUI

struct FilesSettingsSection: View {
    var body: some View {
        Section {
            Text(Self.documentsPathHint)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        } header: {
            Text("Your Files")
        } footer: {
            InfoButton.footer(
                "ROMs, saves, shader caches and keys.txt all live in this folder - under Files normally, or inside LiveContainer's own Documents if you sideloaded that way.",
                title: "Your Files",
                text: "ROMs, saves, shader caches and keys.txt all live in this folder. Installed normally, it shows up as Files \u{2192} On My iPhone/iPad \u{2192} MuffinEMU. Sideloaded through LiveContainer, iOS attributes the folder to LiveContainer instead of to MuffinEMU by name, so look for it under LiveContainer's own Documents, or one level into Data/Application/<its folder>/Documents - the path above is the one to actually search for.")
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
