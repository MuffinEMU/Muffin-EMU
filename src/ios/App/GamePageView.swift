// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// What tapping a game in the library does. Long-press always offers the quick menu.
enum LibraryTapAction: String, CaseIterable, Identifiable {
    case openPage
    case playImmediately

    static let storageKey = "muffin.library.tapAction"
    static let defaultValue = LibraryTapAction.openPage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openPage: return "Open its page"
        case .playImmediately: return "Play immediately"
        }
    }

    static func current(raw: String) -> LibraryTapAction { LibraryTapAction(rawValue: raw) ?? defaultValue }
}

/// A game's own page: its cover and a big Play button, what GameTDB knows about it, how you have
/// played it, and everything you can change for it. Opened by tapping a game in the library.
struct GamePageView: View {
    let game: GameMetadata
    @ObservedObject var store: PerGameSettingsStore
    @ObservedObject var gameManager: GameManager
    /// The actions below run on the library, which sits underneath this page. Each one closes the
    /// page first, so a picker, a sheet or the emulator never has to open on top of it.
    let onPlay: () -> Void
    let onDecrypt: () -> Void
    let onImportDLC: () -> Void
    let onImportUpdate: () -> Void
    let onRemoveDLC: () -> Void
    let onRemoveUpdate: () -> Void
    let onRemoveGame: () -> Void

    @ObservedObject private var stats = LibraryPlayStats.shared
    @ObservedObject private var data = GameDataStore.shared
    @ObservedObject private var names = LibraryCustomNames.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private enum PageSheet: String, Identifiable {
        case settings, cover, rename
        var id: String { rawValue }
    }

    @State private var sheet: PageSheet?
    @State private var sizeOnDisk: Int64?
    @State private var shaderBytes: Int64?
    @State private var slots: [SaveStateSlot] = []
    @State private var slotToDelete: Int?
    @State private var confirmingRemoval = false
    /// Keys the player added from this page. Nil until they do.
    @State private var keysAdded: Int?
    @State private var keysError: String?

    /// An encrypted disc image or game folder with no keys.txt installed: it won't start until there is one, so
    /// say so here, before Play, rather than on the failure screen afterwards. Homebrew (.rpx, .elf, .wuhb),
    /// decrypted dumps and .wua archives don't need keys.
    private var needsKeys: Bool {
        guard keysAdded == nil, !WiiUKeys.keysFileExists() else { return false }
        return ["wux", "wud", "iso", "tmd"].contains(URL(fileURLWithPath: live.romPath).pathExtension.lowercased())
    }

    /// The installed game as the library holds it now, so a new cover, name or favourite shows at once.
    private var live: GameMetadata { gameManager.games.first { $0.id == game.id } ?? game }

    private var installLine: String {
        if let label = live.installLabel { return label }
        return live.installKey.replacingOccurrences(of: "install:", with: "")
    }

    /// Cover beside the text on iPad and in landscape; stacked on a portrait phone.
    private var sideBySide: Bool { horizontalSizeClass == .regular || verticalSizeClass == .compact }

    var body: some View {
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient.ignoresSafeArea()
                Form {
                    heroSection
                    GameInfoSections(game: live, gameManager: gameManager)
                    yourPlaySection
                    manageSection
                    filesSection
                    GameContentSection(game: live)
                    GameShaderCacheSection(game: live)
                    saveStatesSection
                    removeSection
                }
            }
            .navigationTitle(live.cardName.name)
            .muffinOpaqueNavigationBar(MuffinTheme.formGround)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $sheet) { which in
                switch which {
                case .settings:
                    GameOptionsView(game: live, store: store, libraryGames: gameManager.games)
                case .cover:
                    CoverArtPickerView(game: live, gameManager: gameManager)
                case .rename:
                    LibraryRenameSheet(game: live)
                }
            }
            .confirmationDialog(live.removeConfirmTitle, isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button(live.removeConfirmButton, role: .destructive) { closeThen(onRemoveGame) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(live.removeConfirmMessage)
            }
            .alert("Delete this save state?", isPresented: Binding(
                get: { slotToDelete != nil },
                set: { if !$0 { slotToDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let number = slotToDelete,
                       let slot = slots.first(where: { $0.number == number }) {
                        try? FileManager.default.removeItem(at: slot.fileURL)
                    }
                    slotToDelete = nil
                    reloadSlots()
                }
                Button("Cancel", role: .cancel) { slotToDelete = nil }
            }
        }
        .navigationViewStyle(.stack)
        .foregroundColor(MuffinTheme.brownDarkest)
        .onAppear {
            reloadSlots()
            loadSizes()
        }
    }

    // MARK: Hero

    private var heroSection: some View {
        Section {
            VStack(spacing: 18) {
                if sideBySide {
                    HStack(alignment: .center, spacing: 24) {
                        cover(width: 150)
                        VStack(alignment: .leading, spacing: 14) {
                            titleBlock(alignment: .leading)
                            playButtons
                        }
                    }
                } else {
                    cover(width: 190)
                    titleBlock(alignment: .center)
                    playButtons
                }
                if needsKeys || keysAdded != nil || keysError != nil {
                    keysNotice
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        }
    }

    private func cover(width: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(MuffinTheme.muffinTopGradient)
            if let path = live.coverPath {
                CoverImage(path: path, padding: 8)
            } else {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: width * 0.3))
                    .foregroundColor(MuffinTheme.onMuffinTop)
            }
        }
        .frame(width: width, height: width * 4 / 3)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: MuffinTheme.shadow.opacity(0.3), radius: 14, x: 0, y: 8)
        .accessibilityHidden(true)
    }

    private func titleBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            Text(live.cardName.name)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let info = data.info(for: game.id), let by = info.publisher ?? info.developer {
                Text(by)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(MuffinTheme.brownMid)
            }
            Label(live.region ?? "Region unknown", systemImage: "globe")
                .font(.system(size: 13, design: .rounded))
                .foregroundColor(MuffinTheme.brownMid)
            Text(installLine)
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(MuffinTheme.secondaryText)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .lineLimit(2)
        }
    }

    private var playButtons: some View {
        Button {
            closeThen(onPlay)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill").font(.system(size: 18, weight: .bold))
                Text("Play").font(.system(size: 20, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(MuffinPrimaryButtonStyle())
        .frame(maxWidth: 340)
        .accessibilityLabel("Play \(live.cardName.name)")
    }

    /// Said before Play, with the fix on the same card.
    private var keysNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let keysAdded {
                Label("Added \(keysAdded) key\(keysAdded == 1 ? "" : "s"). This game can start now.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(MuffinTheme.brownDarkest)
            } else {
                Label("This game is encrypted. It needs the keys.txt dumped from your own Wii U before it can start.", systemImage: "key.fill")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(MuffinTheme.brownDarkest)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: importKeys) {
                    Label("Import keys.txt", systemImage: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .buttonStyle(MuffinSecondaryButtonStyle())
                .accessibilityHint("Opens the Files picker to choose your keys.txt.")
            }
            if let keysError {
                Text(keysError)
                    .font(.system(size: 12))
                    .foregroundColor(MuffinTheme.alertText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(MuffinTheme.cream, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MuffinTheme.cautionText.opacity(0.35), lineWidth: 1))
    }

    private func importKeys() {
        DocumentImport.present(contentTypes: [.item]) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    keysAdded = try WiiUKeys.importKeys(from: url)
                    keysError = nil
                } catch {
                    keysError = error.localizedDescription
                }
            case .failure(let error):
                keysError = error.localizedDescription
            }
        }
    }

    // MARK: Your play

    private var yourPlaySection: some View {
        Section {
            SettingsRow(label: "Last played", value: lastPlayedText, icon: "clock.arrow.circlepath")
            SettingsRow(label: "Times played", value: "\(stats.entry(for: game.id)?.count ?? 0)", icon: "number")
            SettingsRow(label: "Size on disk", value: sizeOnDisk.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "\u{2026}",
                        icon: "internaldrive")
        } header: {
            SettingsSectionHeader("Play history", icon: "clock.arrow.circlepath", accent: .content)
        }
    }

    private var lastPlayedText: String {
        guard let entry = stats.entry(for: game.id) else { return "Not yet" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: entry.last, relativeTo: Date())
    }

    // MARK: Manage

    private var manageSection: some View {
        Section {
            Button { sheet = .settings } label: {
                rowLabel("Game settings", systemImage: "slider.horizontal.3", chevron: true)
            }
            Toggle(isOn: Binding(
                get: { live.isFavorite },
                set: { _ in gameManager.toggleFavorite(live) }
            )) {
                rowLabel("Favourite", systemImage: live.isFavorite ? "heart.fill" : "heart")
            }
            .tint(MuffinTheme.accentText)
            Button { sheet = .cover } label: {
                rowLabel("Change cover", systemImage: "photo")
            }
            if gameManager.hasManualCoverOverride(forGameID: game.id) {
                Button(role: .destructive) {
                    gameManager.removeManualCover(forGameID: game.id)
                } label: {
                    DestructiveSettingsLabel(title: "Remove custom cover", systemImage: "photo.badge.minus")
                }
            }
            Button { sheet = .rename } label: {
                rowLabel("Rename", systemImage: "pencil")
            }
            if names.name(for: live.installKey) != nil {
                Button { names.set(nil, for: live.installKey) } label: {
                    rowLabel("Reset to original title", systemImage: "arrow.uturn.backward")
                }
            }
        } header: {
            SettingsSectionHeader("Manage", icon: "slider.horizontal.3", accent: .core)
        }
    }

    /// Decrypting works on the game's files, so it hands off to the library. Updates and DLC are in the
    /// Updates & DLC section right below (GameContentSection), so they aren't offered here a second time.
    @ViewBuilder private var filesSection: some View {
        if gameSupportsDecryptToFiles(romPath: live.romPath) {
            Section {
                Button { closeThen(onDecrypt) } label: {
                    rowLabel("Decrypt", systemImage: "lock.open")
                }
            } header: {
                SettingsSectionHeader("Files", icon: "doc", accent: .io)
            }
        }
    }

    // MARK: Save states

    private var saveStatesSection: some View {
        let used = slots.filter { $0.isOccupied }
        return Section {
            if used.isEmpty {
                Text("No save states yet.")
                    .font(.system(size: 13))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
            ForEach(used) { slot in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Slot \(slot.number)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(slotDetail(slot))
                            .font(.system(size: 12))
                            .foregroundColor(MuffinTheme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Button { slotToDelete = slot.number } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete slot \(slot.number)")
                }
            }
        } header: {
            SettingsSectionHeader("Save states", icon: "clock.arrow.2.circlepath", accent: .io)
        } footer: {
            Text("Save and load states from the top bar while the game is running. A state can't be loaded after the game has been closed.")
        }
    }

    private func slotDetail(_ slot: SaveStateSlot) -> String {
        var parts: [String] = []
        if let date = slot.savedAt {
            parts.append(date.formatted(date: .abbreviated, time: .shortened))
        }
        if let bytes = slot.byteCount {
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: Remove

    private var removeSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingRemoval = true
            } label: {
                DestructiveSettingsLabel(title: live.removeActionTitle, systemImage: "trash")
            }
        } footer: {
            Text(live.isExternal
                 ? "Only takes the game out of your library. Its file stays where it is. Your saves and options are kept."
                 : "Frees up the space the game uses. Your saves and options are kept.")
        }
    }

    // MARK: Helpers

    private func rowLabel(_ title: String, systemImage: String, chevron: Bool = false) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            if chevron {
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MuffinTheme.secondaryText)
            }
        }
    }

    /// Closes the page, then runs `action` once it is gone, so what it opens isn't blocked by it.
    private func closeThen(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { action() }
    }

    private func reloadSlots() {
        slots = SaveStateStore.slots(for: game.id)
    }

    private func loadSizes() {
        let path = live.dumpDirectoryPath ?? live.romPath
        let titleId = live.titleId
        let locationID = live.isUnavailable ? nil : live.externalLocationID
        let isExternal = live.isExternal
        DispatchQueue.global(qos: .utility).async {
            // A linked game is measured where it is, so its location is held open for the read.
            let hold = locationID.flatMap { ExternalLibrary.shared.acquire($0) }
            defer { if let hold { ExternalLibrary.shared.release(hold) } }
            let bytes = (isExternal && hold == nil) ? nil : Self.byteCount(atPath: path)
            var shader: Int64?
            if let titleId {
                var learned: Int64 = 0
                var compiled: Int64 = 0
                _ = cemu_bridge_shader_cache_stats(titleId, &learned, &compiled)
                shader = learned + compiled
            }
            DispatchQueue.main.async {
                sizeOnDisk = bytes
                shaderBytes = shader
            }
        }
    }

    /// A file's size, or a folder's total. Blocking: call it off the main thread.
    private static func byteCount(atPath path: String) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return ((try? fm.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0
        }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey]
        guard let walker = fm.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}
