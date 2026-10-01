import SwiftUI

/// The library entry for the Wii U Menu, pinned above the game grid so it reads as the
/// console's own home rather than one more game. Shown only while a Menu title is
/// installed (Settings > Wii U Menu). Tapping it checks the pieces the Menu is known not
/// to work without and, if any are missing, says which before launching.
struct WiiUMenuTile: View {
    @ObservedObject private var store = WiiUMenuStore.shared
    let onLaunch: (GameMetadata) -> Void
    @State private var showingPreflight = false

    var body: some View {
        if let entry = WiiUMenu.libraryEntry(for: store.status) {
            Button(action: { attemptLaunch(entry) }) {
                HStack(spacing: 14) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(colors: [MuffinTheme.pixelBlue, MuffinTheme.blueberryNavy],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Wii U Menu")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(MuffinTheme.brownDarkest)
                        Text(subtitle(entry))
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(MuffinTheme.brownMid)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Text("Experimental")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(MuffinTheme.cautionText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(Capsule().stroke(MuffinTheme.cautionText, lineWidth: 1))
                    Image(systemName: "play.fill")
                        .foregroundColor(MuffinTheme.accentText)
                }
                .padding(12)
                .background(MuffinTheme.cream)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MuffinTheme.pixelBlue, lineWidth: 2)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .accessibilityLabel("Wii U Menu, experimental")
            .alert("The Wii U Menu may not start", isPresented: $showingPreflight) {
                Button("Launch anyway") { onLaunch(entry) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Missing: " + store.status.missingRequired.joined(separator: ", ")
                     + ".\n\nImport them in Settings > Wii U Menu. Without them the Menu is likely to crash a few seconds in.")
            }
        }
    }

    private func subtitle(_ entry: GameMetadata) -> String {
        let missing = store.status.missingRequired
        if missing.isEmpty {
            return "\(entry.region ?? "System") - your games appear in it"
        }
        return "Missing files - tap for details"
    }

    private func attemptLaunch(_ entry: GameMetadata) {
        store.refresh()
        if store.status.missingRequired.isEmpty {
            onLaunch(entry)
        } else {
            showingPreflight = true
        }
    }
}
