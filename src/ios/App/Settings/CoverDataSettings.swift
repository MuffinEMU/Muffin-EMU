// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// The Settings section that leads to everything about cover art and game data.
struct CoverDataSettingsSection: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject private var packs = ArtPackStore.shared
    @ObservedObject private var data = GameDataStore.shared
    @AppStorage(CoverStylePreference.storageKey) private var styleRaw = CoverStylePreference.defaultValue.rawValue

    private var style: CoverStylePreference { CoverStylePreference(stored: styleRaw) }

    var body: some View {
        Section {
            NavigationLink {
                CoverDataSettingsView(gameManager: gameManager)
            } label: {
                Label("Covers and game data", systemImage: "photo.on.rectangle.angled")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            SettingsRow(label: "Covers", value: style.title, icon: "rectangle.portrait")
            SettingsRow(label: "Art packs installed", value: "\(packs.installed.count)", icon: "shippingbox")
            SettingsRow(label: "Games with data", value: "\(data.matchedCount) of \(gameManager.games.count)", icon: "doc.text.magnifyingglass")
        } header: {
            SettingsSectionHeader("Cover art", icon: "photo.stack", accent: .content)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }
}

/// Cover style, art packs, data scraping and credits.
struct CoverDataSettingsView: View {
    @ObservedObject var gameManager: GameManager
    @ObservedObject private var packs = ArtPackStore.shared
    @ObservedObject private var data = GameDataStore.shared
    @AppStorage(CoverStylePreference.storageKey) private var styleRaw = CoverStylePreference.defaultValue.rawValue
    @State private var deleteTarget: ArtPack?

    private var style: CoverStylePreference { CoverStylePreference(stored: styleRaw) }

    private static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    var body: some View {
        Form { Group {
            packsSection
            scrapeSection
            creditsSection
        }.muffinGlassRows()}.muffinGlassFormGround()
        .navigationTitle("Covers and game data")
        .muffinOpaqueNavigationBar(MuffinTheme.formGround)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .foregroundColor(MuffinTheme.brownDarkest)
        .onAppear { if packs.manifest == nil { packs.refreshManifest() } }
        .confirmationDialog("Delete this art pack?", isPresented: Binding(
            get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }
        ), titleVisibility: .visible, presenting: deleteTarget) { pack in
            Button("Delete \(pack.name)", role: .destructive) { packs.delete(pack.id) }
            Button("Cancel", role: .cancel) { }
        } message: { pack in
            Text("The images are removed from this device. You can download \(pack.name) again later.")
        }
    }

    // MARK: Packs

    private var packsSection: some View {
        Section {
            if let manifest = packs.manifest {
                // Disc art has no place in Flat or 3D, so those packs aren't offered.
                ForEach(manifest.packs.filter { $0.style != "disc" }) { pack in
                    PackRow(pack: pack, store: packs, games: gameManager.games) { deleteTarget = pack }
                }
            } else if packs.isLoadingManifest {
                HStack(spacing: 8) { ProgressView(); Text("Loading the pack list\u{2026}").font(.system(size: 13)).foregroundColor(MuffinTheme.secondaryText) }
            }
            if let error = packs.manifestError {
                Text(error).font(.system(size: 12)).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }
            Button {
                packs.refreshManifest()
            } label: {
                Label("Check for packs", systemImage: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .disabled(packs.isLoadingManifest)
        } header: {
            SettingsSectionHeader("Art packs", icon: "shippingbox", accent: .content)
        } footer: {
            InfoButton.footer(
                "Art packs are downloaded from the MuffinEMU-Art repository and installed automatically.",
                title: "Art packs",
                text: "Art packs are community collections of cover art, mostly 3D boxes. Download one and MuffinEMU matches its images to your games by title and region.\n\nYou need free space for the download and the unpacked images at the same time. MuffinEMU checks first. Keep MuffinEMU open while a pack downloads. Cancel stops it and cleans up.\n\nPacks are stored where Files can't see them and aren't included in device backups, since you can download them again."
            )
        }
    }

    // MARK: Scraping

    private var scrapeSection: some View {
        Section {
            SettingsRow(label: "Games with data", value: "\(data.matchedCount) of \(gameManager.games.count)", icon: "doc.text.magnifyingglass")
            SettingsRow(label: "Last updated", value: data.lastScrape.map { ShaderCacheInfo.formatDate($0) } ?? "Never", icon: "clock")
            if data.isScraping {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: data.fraction)
                    Text(data.phase).font(.system(size: 12)).foregroundColor(MuffinTheme.secondaryText)
                }
                Button(role: .destructive) { data.cancelScrape() } label: {
                    Label("Cancel", systemImage: "xmark.circle").font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            } else {
                Button {
                    data.scrape(games: gameManager.games)
                } label: {
                    Label("Download game data", systemImage: "arrow.down.doc")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .disabled(gameManager.games.isEmpty)
            }
            if let summary = data.lastSummary {
                Text(summary).font(.system(size: 12)).foregroundColor(MuffinTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            if let error = data.scrapeError {
                Text(error).font(.system(size: 12)).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            SettingsSectionHeader("Game data", icon: "doc.text.magnifyingglass", accent: .content)
        } footer: {
            InfoButton.footer(
                "Looks up your games in the GameTDB database for summaries, release dates, publishers and more.",
                title: "Game data",
                text: "MuffinEMU downloads GameTDB's Wii U database (about 2 MB) and keeps only the entries for your games.\n\nEach game is matched by its title ID, then its product code, then its title in any language, preferring the game's own region. If a match is wrong, open the game's Info screen and pick a different entry.\n\nIt also runs by itself in the background for new games."
            )
        }
    }

    // MARK: Credits

    private var creditsSection: some View {
        Section {
            creditRow("GameTDB", "Covers and game data. Used with thanks to the GameTDB community.", "https://www.gametdb.com")
            if let manifest = packs.manifest {
                // The same packs the list above offers: disc packs aren't shown there, so they aren't credited here.
                ForEach(manifest.packs.filter { $0.style != "disc" }) { pack in
                    creditRow(pack.name, pack.credits, nil)
                }
            }
            creditRow("MuffinEMU-Art", "Hosts the art packs, with the full credits in CREDITS.md.", "https://github.com/MuffinEMU/MuffinEMU-Art")
            creditRow("box3d by RtaSistemas (MIT)", "The 3D box template behind MuffinEMU's no-cover images.", "https://github.com/RtaSistemas/box3d")
            Text("3D case template (spine, logo and badges) from Robin55's Nintendo Wii U 3D Boxes 1.3.")
            Text("Wii U and Nintendo logos \u{00A9} Nintendo. Rating icons \u{00A9} ESRB.")
            Text("Box art \u{00A9} respective publishers.")
                .font(.system(size: 12))
                .foregroundColor(MuffinTheme.secondaryText)
        } header: {
            SettingsSectionHeader("Credits", icon: "heart", accent: .content)
        }
    }

    private func creditRow(_ title: String, _ detail: String, _ link: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let link, let url = URL(string: link) {
                Link(title, destination: url).font(.system(size: 14, weight: .semibold, design: .rounded))
            } else {
                Text(title).font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            Text(detail).font(.system(size: 12)).foregroundColor(MuffinTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PackRow: View {
    let pack: ArtPack
    @ObservedObject var store: ArtPackStore
    let games: [GameMetadata]
    let onDelete: () -> Void

    /// How many of the player's games this pack has art for.
    private var matchedCount: Int {
        games.filter { g in
            let names = [LibraryMetadataCache.cachedTitleName(for: g.id), g.title, g.id].compactMap { $0 }.filter { !$0.isEmpty }
            let c = CoverContext(gameID: g.id, romPath: g.romPath, dumpDirectoryPath: nil,
                                 libraryDirectory: URL(fileURLWithPath: "/"), currentCoverPath: nil,
                                 region: LibraryMetadataCache.cachedRegion(for: g.id), titles: names)
            return ArtPackIndex.shared.lookup(candidates: ArtPackMatching.candidates(for: c), styles: [pack.style],
                                              regions: RegionCode.codes(in: c.region), onlyPack: pack.id) != nil
        }.count
    }

    private var installed: InstalledPackMeta? { store.installed.first { $0.id == pack.id } }
    private var busy: ArtPackStore.PackProgress? { store.progress[pack.id] }

    private static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    /// Which library mode uses this pack, said plainly.
    private var usedIn: String { pack.style == "3d" ? "Used when Covers is set to 3D." : "Used for flat covers." }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(pack.name).font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer(minLength: 8)
                Text(pack.styleTitle)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(MuffinTheme.brownMid.opacity(0.15))
                    .clipShape(Capsule())
            }
            Text(pack.description).font(.system(size: 12)).foregroundColor(MuffinTheme.secondaryText)
            Text("\(pack.imageCount) images, \(pack.imageSize), \(Self.bytes(pack.downloadBytes)) download")
                .font(.system(size: 12)).foregroundColor(MuffinTheme.secondaryText)
            Text("Credit: \(pack.credits)").font(.system(size: 12)).foregroundColor(MuffinTheme.secondaryText)

            if let busy {
                ProgressView(value: min(max(busy.fraction, 0), 1))
                HStack {
                    Text(busy.phase + "\u{2026} \(Int(min(max(busy.fraction, 0), 1) * 100))%")
                        .font(.system(size: 12)).foregroundColor(MuffinTheme.secondaryText)
                    Spacer()
                    Button("Cancel", role: .destructive) { store.cancel(pack.id) }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .buttonStyle(.borderless)
                }
            } else if let installed {
                HStack {
                    Label("Installed, \(Self.bytes(installed.bytesOnDisk)) on disk", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(MuffinTheme.secondaryText)
                    Spacer()
                    Button("Delete", role: .destructive, action: onDelete)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .buttonStyle(.borderless)
                }
            } else {
                Button {
                    store.install(pack)
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.borderless)
            }
            if installed != nil, busy == nil {
                Text("Has art for \(matchedCount) of \(games.count) of your games. \(usedIn)")
                    .font(.system(size: 12)).foregroundColor(MuffinTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = store.errors[pack.id] {
                Text(error).font(.system(size: 12)).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
