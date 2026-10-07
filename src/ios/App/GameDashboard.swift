import SwiftUI

/// The top of a game's options screen: the cover, the name, where it came from, how it has been
/// played, and the actions people reach for first. The per-game settings follow below it.
struct GameDashboardSection: View {
    let game: GameMetadata
    @ObservedObject var gameManager: GameManager
    let onPlay: () -> Void
    @ObservedObject private var stats = LibraryPlayStats.shared
    @ObservedObject private var data = GameDataStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var shaderBytes: Int64?
    @State private var showingCoverPicker = false

    /// The installed game's current cover, read from the live library so a change shows at once.
    private var coverPath: String? { gameManager.games.first { $0.id == game.id }?.coverPath ?? game.coverPath }

    private var installLine: String {
        if let label = game.installLabel { return label }
        return game.installKey.replacingOccurrences(of: "install:", with: "")
    }

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MuffinTheme.muffinTopGradient)
                    if let path = coverPath {
                        CoverImage(path: path, padding: 6)
                    } else {
                        Image(CoverStylePreference.current.genericIs3D ? "NoCover3d" : "NoCover2d")
                            .resizable().scaledToFit().padding(6)
                    }
                }
                .frame(width: 96, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(game.cardName.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Label(game.region ?? "Region unknown", systemImage: "globe")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(MuffinTheme.brownMid)
                    Text(installLine)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(MuffinTheme.secondaryText)
                        .lineLimit(2)
                    if let info = data.info(for: game.id), let match = data.match(for: game.id) {
                        Text("\(info.publisher ?? info.developer ?? "GameTDB"), \(match.confidenceText.lowercased()) confidence match")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(MuffinTheme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)

            SettingsRow(label: "Last played", value: lastPlayedText, icon: "clock.arrow.circlepath")
            SettingsRow(label: "Times played", value: "\(stats.entry(for: game.id)?.count ?? 0)", icon: "number")
            if game.titleId != nil {
                SettingsRow(label: "Shader cache", value: shaderBytes.map { ShaderCacheInfo.formatBytes($0) } ?? "\u{2026}", icon: "externaldrive")
            }

            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onPlay() }
            } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            Button {
                showingCoverPicker = true
            } label: {
                Label("Change cover", systemImage: "photo")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            NavigationLink {
                GameInfoView(game: game, gameManager: gameManager)
            } label: {
                Label("Info", systemImage: "info.circle")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        } header: {
            SettingsSectionHeader("Dashboard", icon: "gauge", accent: .content)
        }
        .sheet(isPresented: $showingCoverPicker) {
            CoverArtPickerView(game: game, gameManager: gameManager)
        }
        .onAppear { loadShaderSize() }
    }

    private var lastPlayedText: String {
        guard let entry = stats.entry(for: game.id) else { return "Not yet" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: entry.last, relativeTo: Date())
    }

    private func loadShaderSize() {
        guard let titleId = game.titleId else { return }
        DispatchQueue.global(qos: .utility).async {
            var learned: Int64 = 0
            var compiled: Int64 = 0
            _ = cemu_bridge_shader_cache_stats(titleId, &learned, &compiled)
            DispatchQueue.main.async { shaderBytes = learned + compiled }
        }
    }
}
