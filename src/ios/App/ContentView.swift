import SwiftUI
import MetalKit
import UniformTypeIdentifiers
import Foundation

struct ContentView: View {
    @StateObject var gameManager = GameManager()
    @AppStorage(OnboardingState.completedKey) private var onboardingCompleted = false
    @State private var selectedGame: GameMetadata?
    @State private var showingGameBrowser = true
    @State private var showingFavorites = false
    @State private var selectedSkin: WiiUControllerSkin = WiiUControllerSkin.standard

    var body: some View {
        ZStack {
            if showingGameBrowser {
                GameBrowserView(
                    gameManager: gameManager,
                    selectedGame: $selectedGame,
                    showingGameBrowser: $showingGameBrowser,
                    showingFavorites: $showingFavorites
                )
            } else if let game = selectedGame {
                switch gameManager.emulationState {
                case .loading, .running, .paused:
                    // Mount as soon as .loading starts, not only once .running - the
                    // Metal surface needs to exist and register itself with the C++
                    // bridge (see GameManager.registerRenderSurface) BEFORE boot() runs,
                    // since the GPU thread reads the window size synchronously the
                    // instant boot() spawns it.
                    EmulatorViewOptimized(
                        game: game,
                        gameManager: gameManager,
                        isRunning: $showingGameBrowser,
                        controllerSkin: $selectedSkin
                    )
                case .error:
                    BootFailureView(
                        game: game,
                        message: gameManager.lastStatusMessage,
                        onDismiss: {
                            gameManager.stopEmulation()
                            showingGameBrowser = true
                        }
                    )
                case .idle:
                    // Reached only if something stopped emulation without restoring the
                    // browser. Rendering nothing here is what the old code did for every
                    // non-loading/running state, so make the recovery explicit instead.
                    Color.clear.onAppear { showingGameBrowser = true }
                }
            }
        }
        .ignoresSafeArea()
        // First launch, and again whenever Settings > About resets the flag.
        .fullScreenCover(isPresented: Binding(
            get: { !onboardingCompleted },
            set: { if !$0 { onboardingCompleted = true } }
        )) {
            OnboardingView(gameManager: gameManager) { onboardingCompleted = true }
        }
    }
}

/// Shown when `emulationState` is `.error`.
///
/// Before this existed, ContentView's only non-browser branch required the state to
/// be `.loading` or `.running`, so a failed boot rendered an empty ZStack: no
/// emulator view, no browser (showingGameBrowser was already false), no Back button,
/// nothing. A blank screen and no way out, which on a device is indistinguishable
/// from the emulator hanging - and is a plausible share of what has been reported as
/// "black screen" during M2 bring-up, since every boot failure path lands here.
///
/// GameManager has always recorded the reason in `lastStatusMessage`; nothing in the
/// app displayed it. (It was also wrong until the bridge's thread_local status buffer
/// was fixed - see CemuBridge.mm.) Showing it is the whole point of this view.
struct BootFailureView: View {
    let game: GameMetadata
    let message: String
    let onDismiss: () -> Void

    /// Where the diagnostics actually are. Computed from the bridge rather than written
    /// down here, because only the bridge knows what $HOME resolved to when it opened the
    /// file, and that differs between a normal install and a LiveContainer one.
    private static var crashLogHint: String {
        let path = String(cString: cemu_bridge_crash_log_path())
        guard !path.isEmpty else {
            return "Full detail is in log.txt. No crash log could be opened this run, so there is no CemuCrashLog.txt to send."
        }
        return "Full detail is in log.txt and CemuCrashLog.txt, at:\n\(path)"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(MuffinTheme.blushPink)

                Text("Couldn't start \(game.title)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                // The engine's own words. Empty only if the bridge never set anything,
                // which is itself worth seeing rather than papering over.
                Text(message.isEmpty ? "The engine didn't report a reason." : message)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: 480)

                // The real path, asked of the bridge, rather than the folder this used to
                // name. It said "Files > On My iPad > Cemu", which is true for a normally
                // installed app and false under LiveContainer - LiveContainer redirects
                // HOME per hosted app, so the file lands under LiveContainer's own
                // Documents instead. Anyone who followed the old line looked in the right
                // place for the wrong install, found nothing, and reasonably concluded no
                // crash log existed. Selectable, because the useful thing to do with a
                // path is copy it.
                Text(Self.crashLogHint)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: 480)

                Button(action: onDismiss) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back to games")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                }
                .buttonStyle(MuffinSecondaryButtonStyle())
                .padding(.top, 4)
            }
            .padding(32)
        }
    }
}

/// How the library grid orders games, offered next to the search field. Persisted via
/// `sortOrderRaw` below rather than reset every launch - a choice someone made once
/// shouldn't need remaking every time they open the app.
enum LibrarySortOrder: String, CaseIterable, Hashable {
    case title
    case recentlyAdded
    case favoritesFirst

    var title: String {
        switch self {
        case .title: return "Title"
        case .recentlyAdded: return "Recently added"
        case .favoritesFirst: return "Favorites first"
        }
    }

    var systemImage: String {
        switch self {
        case .title: return "textformat"
        case .recentlyAdded: return "clock"
        case .favoritesFirst: return "heart"
        }
    }

    /// Applies this order to an already-filtered list.
    ///
    /// `recentlyAdded` falls back to title order for two games whose dates couldn't be
    /// read (addedDate nil, e.g. the attribute lookup failed) - there's nothing to
    /// compare, and title order at least keeps those entries in a stable place instead
    /// of an arbitrary one.
    ///
    /// `favoritesFirst` groups favorites first and sorts by title WITHIN each group -
    /// not a stable no-op, since "grouped, but otherwise still alphabetical" is what
    /// actually makes the option useful once there's more than a couple of favorites.
    func sorted(_ games: [GameMetadata]) -> [GameMetadata] {
        switch self {
        case .title:
            return games.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recentlyAdded:
            return games.sorted { lhs, rhs in
                switch (lhs.addedDate, rhs.addedDate) {
                case let (l?, r?): return l > r
                case (nil, nil): return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        case .favoritesFirst:
            return games.sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
    }
}

/// A small pinned banner for a background operation that's mid-flight - importing a
/// ROM/DLC/update, or removing installed content. Not an alert: those are exactly the
/// operations where blocking the whole screen would be the slowness this work exists
/// to remove.
struct LibraryActivityBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(MuffinTheme.brownDarkest)
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(MuffinTheme.brownDarkest)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MuffinTheme.cream)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(MuffinTheme.wrapper, lineWidth: 1)
        )
        .shadow(color: MuffinTheme.shadow.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

struct GameBrowserView: View {
    @ObservedObject var gameManager: GameManager
    @Binding var selectedGame: GameMetadata?
    @Binding var showingGameBrowser: Bool
    @Binding var showingFavorites: Bool
    @State private var searchText = ""
    @State private var showingIconPicker = false
    @State private var showingSettings = false
    /// Which game "View Game Options" was opened for - the sheet's own presence, not a
    /// separate Bool, so there is no way for the sheet to open pointed at the wrong game.
    @State private var gameOptionsTarget: GameMetadata?
    /// Same pattern as gameOptionsTarget, for "Decrypt…" (DecryptROMView.swift).
    @State private var decryptTarget: GameMetadata?
    @ObservedObject private var perGameSettings = PerGameSettingsStore.shared
    /// What the picker is being opened for.
    ///
    /// A document picker only lets you SELECT a directory when UTType.folder is among
    /// its allowed types; with a file-only type list, tapping a folder navigates into it
    /// and there is no way to choose it. A full Wii U dump IS a directory (code/,
    /// content/, meta/), so one type list cannot serve both without making folder taps
    /// ambiguous - hence two entry points, each with its own fixed list.
    ///
    /// .item, not .data or a list of ROM types, for the file case. iOS has no built-in
    /// UTType for .rpx, .wux, .wud or .wua, so any type-filtered list greys out exactly
    /// the files this button exists to import - the reported "it only opens folders, you
    /// cannot select things". .item is the root of the type hierarchy: everything
    /// matches, nothing is greyed out, and GameManager.importROM does the deciding
    /// afterwards against its own copy. .data is nearly as permissive but still depends
    /// on the provider having resolved a byte-stream type for the file at all; .item
    /// does not.
    ///
    /// Presentation itself is DocumentImport's job rather than .fileImporter's - see
    /// that file for why the button did nothing when it was a SwiftUI modifier.
    private static let fileImportTypes: [UTType] = [.item]
    private static let folderImportTypes: [UTType] = [.folder]

    /// Persisted so the chosen order survives a relaunch, same reasoning as favorites.
    @AppStorage("muffin.library.sortOrder") private var sortOrderRaw = LibrarySortOrder.title.rawValue
    private var sortOrder: LibrarySortOrder {
        get { LibrarySortOrder(rawValue: sortOrderRaw) ?? .title }
        set { sortOrderRaw = newValue.rawValue }
    }

    @State private var romImportErrorMessage: String?
    /// Answers GameManager.confirmOverwrite - see the .onAppear wiring below. A plain
    /// closure captured from the continuation rather than storing the continuation
    /// type directly, so the two alert buttons don't need to know anything about
    /// CheckedContinuation.
    @State private var pendingOverwriteConfirmation: (name: String, resume: (Bool) -> Void)?
    /// Set while DlcUpdateImport.remove() is running in the background (see the
    /// "Remove content?" alert below) - shown as a LibraryActivityBanner, same as
    /// GameManager.importState, rather than blocking the screen for what is, on a
    /// large installed DLC, a real recursive delete.
    @State private var removingContentMessage: String?

    /// See DlcUpdateImport.swift for the actual copy/match/install logic this drives.
    @State private var dlcImportErrorMessage: String?
    /// Set only when an import failed with .noBaseGameMatch - auto-matching by title ID
    /// couldn't place the file, so this asks whether to fall back to the game that was
    /// long-pressed to start the import, per Void's "automatic matching with manual
    /// fallback" spec. Retrying is what actually calls DlcUpdateImport.import again
    /// with manualMatch set; dismissing without confirming leaves nothing on disk,
    /// same as any other rejected import.
    @State private var pendingManualMatchConfirmation: (source: URL, kind: DlcUpdateImport.ContentKind, game: GameMetadata)?
    /// Set by "Remove DLC"/"Remove Update" - deletion itself waits for the confirm
    /// alert below, since it deletes a directory outright with no undo.
    @State private var pendingRemoval: (game: GameMetadata, kind: DlcUpdateImport.ContentKind)?
    /// Set only for an import started from the general menu (no long-pressed game) when
    /// auto-matching fails - presents DlcUpdateGamePickerSheet to ask outright.
    @State private var gamePickerContext: (source: URL, kind: DlcUpdateImport.ContentKind)?
    /// A successful import is otherwise silent - see runDlcUpdateImport.
    @State private var dlcUpdateSuccessMessage: String?

    var filteredGames: [GameMetadata] {
        let gamesToShow = showingFavorites ? gameManager.favorites : gameManager.games
        let searched = searchText.isEmpty
            ? gamesToShow
            : gamesToShow.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        return sortOrder.sorted(searched)
    }

    var body: some View {
        ZStack {
            MuffinTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    Button(action: { showingIconPicker = true }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Muffin")
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundColor(MuffinTheme.sparkleCream)

                            Text("EMU")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(MuffinTheme.pixelBlue)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 8) {
                            Button(action: { showingSettings = true }) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(MuffinTheme.sparkleCream.opacity(0.8))
                            }
                            .frame(width: 44, height: 44)
                            .background(MuffinTheme.sparkleCream.opacity(0.15))
                            .cornerRadius(14)
                            .accessibilityLabel("Settings")

                            Button(action: { showingFavorites.toggle() }) {
                                Image(systemName: showingFavorites ? "heart.fill" : "heart")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(showingFavorites ? MuffinTheme.blushPink : MuffinTheme.sparkleCream.opacity(0.8))
                            }
                            .frame(width: 44, height: 44)
                            .background(MuffinTheme.sparkleCream.opacity(0.15))
                            .cornerRadius(14)
                            .accessibilityLabel(showingFavorites ? "Show all games" : "Show favorites only")

                            Menu {
                                Button {
                                    beginImport(contentTypes: Self.fileImportTypes)
                                } label: {
                                    Label("Game file (.wux, .wud, .wua, .iso, .rpx, .elf, .wuhb)", systemImage: "doc")
                                }
                                Button {
                                    beginImport(contentTypes: Self.folderImportTypes)
                                } label: {
                                    // One folder picker, one entry - it was two identical buttons
                                    // with different labels (both called beginImport with the same
                                    // folderImportTypes; GameManager.importROM already tells the two
                                    // layouts apart on its own regardless of which button was
                                    // tapped), so there was nothing for a second entry to actually
                                    // distinguish. This label just says what the one picker accepts.
                                    Label("Game folder (code/content/meta, or title.tmd + .app files)", systemImage: "folder")
                                }
                                Divider()
                                Button {
                                    beginGeneralDlcUpdateImport(kind: .dlc)
                                } label: {
                                    Label("Import DLC\u{2026}", systemImage: "shippingbox")
                                }
                                Button {
                                    beginGeneralDlcUpdateImport(kind: .update)
                                } label: {
                                    Label("Import Update\u{2026}", systemImage: "arrow.triangle.2.circlepath")
                                }
                            } label: {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(MuffinTheme.sparkleCream.opacity(0.8))
                                    .frame(width: 44, height: 44)
                                    .background(MuffinTheme.sparkleCream.opacity(0.15))
                                    .cornerRadius(14)
                            }
                            .accessibilityLabel("Import")

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(filteredGames.count)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(MuffinTheme.sparkleCream)
                                Text("games")
                                    .font(.system(size: 10, weight: .regular, design: .rounded))
                                    .foregroundColor(MuffinTheme.sparkleCream.opacity(0.7))
                            }
                        }
                    }
                }
                .padding(20)

                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        SearchBarPolished(text: $searchText)

                        Menu {
                            ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                                Button {
                                    sortOrder = order
                                } label: {
                                    if sortOrder == order {
                                        Label(order.title, systemImage: "checkmark")
                                    } else {
                                        Label(order.title, systemImage: order.systemImage)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(MuffinTheme.brownMid)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Sort games")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    if gameManager.isLoading {
                        LoadingView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredGames.isEmpty {
                        EmptyGamesView(onImportTapped: { beginImport(contentTypes: Self.fileImportTypes) })
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView(showsIndicators: false) {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 140), spacing: 16)],
                                spacing: 20
                            ) {
                                ForEach(filteredGames) { game in
                                    GameCardOptimized(
                                        game: game,
                                        onTap: {
                                            selectedGame = game
                                            gameManager.launchGame(game)
                                            showingGameBrowser = false
                                        },
                                        onFavoriteTap: {
                                            gameManager.toggleFavorite(game)
                                        }
                                    )
                                    // Same pattern as Manic: a long-press on the card
                                    // offers a couple of fast toggles plus a way into the
                                    // full screen, rather than making every per-game
                                    // setting a trip through Settings for one game.
                                    .contextMenu {
                                        GameContextMenu(
                                            game: game,
                                            store: perGameSettings,
                                            onViewOptions: { gameOptionsTarget = game },
                                            onDecryptToFiles: { decryptTarget = game },
                                            onImportDLC: { beginDlcUpdateImport(for: game, kind: .dlc) },
                                            onImportUpdate: { beginDlcUpdateImport(for: game, kind: .update) },
                                            onRemoveDLC: { pendingRemoval = (game: game, kind: .dlc) },
                                            onRemoveUpdate: { pendingRemoval = (game: game, kind: .update) }
                                        )
                                    }
                                }
                            }
                            .padding(16)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .background(
                    MuffinTheme.cream
                        .clipShape(RoundedCorner(radius: 28, corners: [.topLeft, .topRight]))
                        .ignoresSafeArea(edges: .bottom)
                )
                // Lets the whole library area - loading, empty, or the grid itself -
                // accept a drag from Files (or another app's share tray) as an import,
                // not just the toolbar's own picker. Same import path either way: a
                // dropped file is validated and staged exactly like a picked one.
                .onDrop(of: [UTType.item], isTargeted: nil, perform: handleDrop)
                .overlay(alignment: .top) {
                    if case .copying(let name) = gameManager.importState {
                        LibraryActivityBanner(text: "Importing \(name)…")
                            .padding(.top, 8)
                    } else if let removingContentMessage {
                        LibraryActivityBanner(text: removingContentMessage)
                            .padding(.top, 8)
                    }
                }
            }
        }
        .onAppear {
            // Answers "a game/dump named `name` already exists - replace it?" for
            // GameManager.importROM. Set here rather than left nil so declining to
            // wire this up was never an option - importROM treats a nil closure as an
            // automatic "no," which is safe but would make every duplicate-name import
            // silently do nothing instead of asking.
            gameManager.confirmOverwrite = { name in
                await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    pendingOverwriteConfirmation = (name: name, resume: { continuation.resume(returning: $0) })
                }
            }
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(gameManager: gameManager)
        }
        .sheet(item: $gameOptionsTarget) { game in
            GameOptionsView(game: game, store: perGameSettings)
        }
        .sheet(item: $decryptTarget) { game in
            DecryptROMView(game: game)
        }
        .sheet(isPresented: Binding(
            get: { gamePickerContext != nil },
            set: { if !$0 { gamePickerContext = nil } }
        )) {
            if let context = gamePickerContext {
                DlcUpdateGamePickerSheet(games: gameManager.games, kind: context.kind) { game in
                    runDlcUpdateImport(from: context.source, kind: context.kind, longPressedGame: nil, manualMatch: game)
                }
            }
        }
        .alert("Added", isPresented: .constant(dlcUpdateSuccessMessage != nil), presenting: dlcUpdateSuccessMessage) { _ in
            Button("OK") { dlcUpdateSuccessMessage = nil }
        } message: { message in
            Text(message)
        }
        .alert("Couldn't import ROM", isPresented: .constant(romImportErrorMessage != nil), presenting: romImportErrorMessage) { _ in
            Button("OK") { romImportErrorMessage = nil }
        } message: { message in
            Text(message)
        }
        .alert("Couldn't import", isPresented: .constant(dlcImportErrorMessage != nil), presenting: dlcImportErrorMessage) { _ in
            Button("OK") { dlcImportErrorMessage = nil }
        } message: { message in
            Text(message)
        }
        .alert(
            "No automatic match",
            isPresented: .constant(pendingManualMatchConfirmation != nil),
            presenting: pendingManualMatchConfirmation
        ) { pending in
            Button("Add to \"\(pending.game.title)\"") {
                pendingManualMatchConfirmation = nil
                runDlcUpdateImport(from: pending.source, kind: pending.kind, longPressedGame: pending.game, manualMatch: pending.game)
            }
            Button("Cancel", role: .cancel) { pendingManualMatchConfirmation = nil }
        } message: { pending in
            Text("Couldn't automatically match this \(pending.kind.displayName) to a game already in your library. Add it to \"\(pending.game.title)\" - the game you long-pressed?")
        }
        .alert(
            "Remove content?",
            isPresented: .constant(pendingRemoval != nil),
            presenting: pendingRemoval
        ) { pending in
            Button("Remove", role: .destructive) {
                pendingRemoval = nil
                removingContentMessage = "Removing \(pending.kind.displayName) for \"\(pending.game.title)\"…"
                Task {
                    // DlcUpdateImport.remove() is a recursive delete of whatever's
                    // installed - on a real DLC pack that's real disk I/O, and running
                    // it inline in this button's action closure blocked the main
                    // thread (and the whole UI) for as long as it took. Task.detached
                    // for the same reason as GameManager.importROM's own copy.
                    do {
                        try await Task.detached {
                            try DlcUpdateImport.remove(kind: pending.kind, for: pending.game)
                        }.value
                    } catch {
                        dlcImportErrorMessage = error.localizedDescription
                    }
                    removingContentMessage = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { pending in
            Text("Remove the \(pending.kind.displayName) installed for \"\(pending.game.title)\"? This can't be undone - you'll need to import it again.")
        }
        .alert(
            "Replace existing file?",
            isPresented: .constant(pendingOverwriteConfirmation != nil),
            presenting: pendingOverwriteConfirmation
        ) { pending in
            Button("Replace", role: .destructive) {
                let resume = pending.resume
                pendingOverwriteConfirmation = nil
                resume(true)
            }
            Button("Cancel", role: .cancel) {
                let resume = pending.resume
                pendingOverwriteConfirmation = nil
                resume(false)
            }
        } message: { pending in
            Text("\"\(pending.name)\" already exists in your library. Replacing it can't be undone.")
        }
    }

    private func beginImport(contentTypes: [UTType]) {
        DocumentImport.present(contentTypes: contentTypes) { result in
            handleImport(result)
        }
    }

    /// Shared by both pickers - a folder and a file import identically from here, the
    /// only difference being which one the user was allowed to tap.
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    try await gameManager.importROM(from: url)
                } catch {
                    romImportErrorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            romImportErrorMessage = error.localizedDescription
        }
    }

    /// The .onDrop target for the whole library area - a drag from Files (or another
    /// app's share tray) lands on the exact same handleImport() path as the toolbar's
    /// own picker, so a dropped file is validated and staged identically either way.
    /// Only the first provider is used: `.fileImporter`/DocumentImport don't allow
    /// multiple selection either, and a game/dump import only ever means one thing at
    /// a time.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: URL.self) }) else {
            return false
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                handleImport(.success([url]))
            }
        }
        return true
    }

    private func beginDlcUpdateImport(for game: GameMetadata, kind: DlcUpdateImport.ContentKind) {
        // A dumped DLC/update is a directory (code/content/meta), same as a game dump -
        // DlcUpdateImport.swift explicitly doesn't support a loose .wua yet, so there's
        // no reason to offer the file picker here the way the ROM import menu does.
        DocumentImport.present(contentTypes: Self.folderImportTypes) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                runDlcUpdateImport(from: url, kind: kind, longPressedGame: game, manualMatch: nil)
            case .failure(let error):
                dlcImportErrorMessage = error.localizedDescription
            }
        }
    }

    /// Entry point from the general import menu, next to "Game file"/"Game folder" -
    /// unlike the per-game long-press entry, there's no game already in hand, so a
    /// failed auto-match has to ask which game outright (gamePickerContext) rather than
    /// confirm against one the user already picked.
    private func beginGeneralDlcUpdateImport(kind: DlcUpdateImport.ContentKind) {
        DocumentImport.present(contentTypes: Self.folderImportTypes) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                runDlcUpdateImport(from: url, kind: kind, longPressedGame: nil, manualMatch: nil)
            case .failure(let error):
                dlcImportErrorMessage = error.localizedDescription
            }
        }
    }

    private func runDlcUpdateImport(
        from url: URL,
        kind: DlcUpdateImport.ContentKind,
        longPressedGame: GameMetadata?,
        manualMatch: GameMetadata?
    ) {
        Task {
            do {
                let result = try await DlcUpdateImport.import(
                    from: url,
                    kind: kind,
                    library: gameManager.games,
                    manualMatch: manualMatch
                )
                // A successful import is otherwise silent - nothing on screen changes
                // for the imported game unless it happens to already be visible, and
                // that silence is exactly what "doesn't work" looks like from the
                // outside. Naming which game it landed on matters most here since
                // whoever started this from the general menu never picked one.
                if let matched = result.matchedGame {
                    dlcUpdateSuccessMessage = "Added \(kind.displayName) for \"\(matched.title)\"."
                }
            } catch DlcUpdateImport.ImportError.noBaseGameMatch {
                // Auto-matching by title ID came up empty. A long-pressed game gets a
                // quick confirm (an unmatched title ID is also what a flat-out wrong
                // file looks like); starting from the general menu means there is no
                // game to confirm against, so ask outright instead.
                if let longPressedGame {
                    pendingManualMatchConfirmation = (source: url, kind: kind, game: longPressedGame)
                } else {
                    gamePickerContext = (source: url, kind: kind)
                }
            } catch {
                dlcImportErrorMessage = error.localizedDescription
            }
        }
    }
}

/// The manual-match fallback for a DLC/update import started from the general menu -
/// see runDlcUpdateImport's gamePickerContext branch. Long-press already has a game in
/// hand and just confirms against it; this is what "ask outright" looks like when there
/// isn't one.
struct DlcUpdateGamePickerSheet: View {
    let games: [GameMetadata]
    let kind: DlcUpdateImport.ContentKind
    let onPick: (GameMetadata) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List(games) { game in
                Button {
                    onPick(game)
                    dismiss()
                } label: {
                    Text(game.title)
                        .foregroundColor(MuffinTheme.brownDarkest)
                }
            }
            .navigationTitle("Add \(kind.displayName) to which game?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Rounds only the given corners - used for the cream "tray" the library grid sits
/// on, so it reads like a muffin liner cupping the games rather than a flat panel.
struct RoundedCorner: Shape {
    var radius: CGFloat = 0
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

struct GameCardOptimized: View {
    let game: GameMetadata
    let onTap: () -> Void
    let onFavoriteTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MuffinTheme.muffinTopGradient)

                if let coverPath = game.coverPath,
                   let uiImage = UIImage(contentsOfFile: coverPath) {
                    // scaledToFit, not scaledToFill. A game's own icon is SQUARE and
                    // this well is 3:4, so filling it would crop the top and bottom
                    // quarter off every icon - which on a Wii U icon is usually the
                    // title text. Fitting leaves the muffin gradient showing around it
                    // instead, and box art that is already 3:4 fits exactly either way.
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                        .cornerRadius(16)
                } else {
                    VStack {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 28))
                            .foregroundColor(MuffinTheme.sparkleCream)
                    }
                }

                VStack {
                    HStack {
                        Spacer()
                        Button(action: onFavoriteTap) {
                            Image(systemName: game.isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(game.isFavorite ? MuffinTheme.blushPink : MuffinTheme.sparkleCream)
                                .frame(width: 32, height: 32)
                                .background(MuffinTheme.brownDarkest.opacity(0.35))
                                .cornerRadius(10)
                                // The visible circle stays 32x32 - the tappable area
                                // around it grows to the standard 44x44 minimum without
                                // changing how the button looks.
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(game.isFavorite ? "Remove from favorites" : "Add to favorites")
                        .padding(8)
                    }
                    Spacer()
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)

            VStack(alignment: .leading, spacing: 8) {
                Text(game.displayTitle ?? game.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .foregroundColor(MuffinTheme.brownDarkest)

                HStack(spacing: 8) {
                    // Was a hardcoded "Unknown" for every single game - hidden now
                    // rather than shown as a placeholder once the region is a real,
                    // derived value (see GameManager.enrichMissingCoverArt) that can
                    // honestly be absent.
                    if let region = game.region {
                        Label(region, systemImage: "globe")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(MuffinTheme.brownMid)
                    }
                    Spacer()
                }

                Button(action: onTap) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Play")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(MuffinPrimaryButtonStyle())
            }
            .padding(12)
            .background(MuffinTheme.cream)
        }
        .background(MuffinTheme.cream)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MuffinTheme.wrapper, lineWidth: 1)
        )
        .shadow(color: MuffinTheme.shadow.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

struct SearchBarPolished: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MuffinTheme.brownMid)

            TextField("Search games...", text: $text)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .textFieldStyle(.plain)
                .foregroundColor(MuffinTheme.brownDarkest)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(MuffinTheme.brownMid)
                        // Visible glyph stays the same size; the tappable area grows
                        // to the standard 44x44 minimum around it.
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
            }
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .background(MuffinTheme.wrapper.opacity(0.5))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(MuffinTheme.wrapper, lineWidth: 1)
        )
    }
}

struct LoadingView: View {
    @State private var rotation: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 48, weight: .semibold))
                .foregroundColor(MuffinTheme.muffinTopDark)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }

            Text("Loading games...")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(MuffinTheme.brownDarkest)
        }
    }
}

struct EmptyGamesView: View {
    let onImportTapped: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.questionmark")
                .font(.system(size: 56, weight: .regular))
                .foregroundColor(MuffinTheme.muffinTopDark.opacity(0.5))

            VStack(spacing: 8) {
                Text("No Games Found")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(MuffinTheme.brownDarkest)

                VStack(alignment: .center, spacing: 4) {
                    Text("Add .wux, .wud, .wua, .rpx, .elf, .wuhb, or .iso files")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(MuffinTheme.brownMid)

                    Text("to Documents/Roms/ on your device")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(MuffinTheme.brownMid)
                }
            }

            // Same import flow as the toolbar's menu (GameBrowserView.beginImport) -
            // an empty library used to have no way to start an import except that
            // small menu button up top, which is easy to miss on a screen whose whole
            // point is "there's nothing here yet."
            Button(action: onImportTapped) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Import a Game")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            .buttonStyle(MuffinPrimaryButtonStyle())
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Where the launch-log setting lives, so the settings sheet and the emulator view
/// agree on the key without one importing the other.
enum LaunchLogSettings {
    static let showKey = "muffin.showLaunchLog"
}

struct EmulatorViewOptimized: View {
    let game: GameMetadata
    @ObservedObject var gameManager: GameManager
    @Binding var isRunning: Bool
    @Binding var controllerSkin: WiiUControllerSkin
    // Read so the app can pause the emulator itself when it leaves the foreground -
    // see the .onChange(of: scenePhase) below - rather than relying on the emulator
    // to notice on its own that nobody is looking at it, which nothing in this codebase
    // does. iOS terminates apps that keep submitting Metal command buffers while
    // backgrounded, so this is not a nicety; see cemu_bridge_pause() in CemuBridge.mm
    // for the other half of what actually stops that.
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSkinSelector = false
    /// Turns the pad into something you position rather than something you press. Local
    /// state, not AppStorage: nobody wants to come back to a game and find the controls
    /// still in edit mode because that is how they last left them.
    @State private var isEditingControlLayout = false
    @State private var isPaused = false
    /// True only when isPaused was set by leaving the foreground, not by the pause
    /// button below. Read on the way back to .active: the app should resume a title
    /// it paused on the way out, but must not resume one the person playing paused
    /// on purpose right before backgrounding it. Both look identical in isPaused
    /// alone, which is exactly why this needs its own bit.
    @State private var pausedByLifecycle = false
    /// Visible only while the preview pad is on. Exists purely to answer one question
    /// with certainty and without needing log.txt: does a tap on the preview pad even
    /// reach this closure at all. If this counter never moves when you tap a button,
    /// the break is in the SwiftUI gesture layer (PreviewControllerPad/HeldControl); if
    /// it does move but the game still doesn't react, the break is further down, in the
    /// bridge or the engine's input override path.
    @State private var previewInputDebugText = "no input yet"
    @State private var previewInputDebugCount = 0
    /// The same two keys the pad itself reads. Declared here as well so the in-game
    /// sliders write to the thing being dragged, with no plumbing between them.
    @AppStorage(ControllerLayoutSettings.scaleKey)
    private var controlScale = ControllerLayoutSettings.defaultScale
    @AppStorage(ControllerLayoutSettings.opacityKey)
    private var controlOpacity = ControllerLayoutSettings.defaultOpacity
    /// Same key the pad and SettingsView read. Offered in the move-controls panel as
    /// well as in Settings because switching schemes is a thing you decide with a game
    /// under you, exactly like the two sliders next to it.
    @AppStorage(ControllerLayoutSettings.joystickKey)
    private var joystickMode = ControllerLayoutSettings.defaultJoystick
    /// Same key ControllerPad.swift reads to decide whether L/ZL/minus and R/ZR/plus are
    /// drawn on the sticks or on the d-pad/A-B-X-Y clusters. Declared here for the same
    /// reason joystickMode is: this is the panel you have a game under you to judge it
    /// from.
    @AppStorage(ControllerLayoutSettings.comfortControlsKey)
    private var comfortControls = ControllerLayoutSettings.defaultComfortControls
    /// Same key ControllerPad.swift reads to decide which gesture (if either) a
    /// button/cluster gets. Declared here too so the segmented control below writes to
    /// the thing actually being edited, same reasoning as the two sliders above it.
    @AppStorage(ControllerLayoutSettings.individualEditModeKey)
    private var individualEditMode = ControllerLayoutSettings.defaultIndividualEditMode
    /// Off by default - see the branch on this flag a few lines below for exactly what
    /// it swaps in and why the shipping path is otherwise untouched.
    @AppStorage(PreviewPadStore.enabledKey) private var previewPadEnabled = PreviewPadStore.defaultEnabled
    @AppStorage(MeloControlsSetting.storageKey) private var useMeloControls = MeloControlsSetting.defaultValue
    @ObservedObject private var previewPad = PreviewPadStore.shared
    // The two feel settings, offered here as well as in Settings for the same reason the
    // toggle is: a deadzone is not something you can judge from a settings screen with no
    // game under it. This is the panel you have open while steering.
    @AppStorage(ControllerLayoutSettings.deadzoneKey)
    private var stickDeadzone = ControllerLayoutSettings.defaultDeadzone
    @AppStorage(ControllerLayoutSettings.stickCurveKey)
    private var stickCurve = ControllerLayoutSettings.defaultStickCurve
    // The gate belongs here more than either slider does: it is the one setting you
    // judge by pushing the stick to a corner and seeing whether the game turns as hard
    // as you meant it to.
    @AppStorage(ControllerLayoutSettings.stickGateKey)
    private var stickGateRaw = ControllerLayoutSettings.defaultStickGateRaw
    // Defaults ON, and must keep matching SettingsView's declaration of the same key -
    // two @AppStorage defaults for one key that disagree means the toggle and the
    // emulator disagree about what is on. See SettingsView for why this flipped.
    @AppStorage(LaunchLogSettings.showKey) private var showLaunchLog = true
    @StateObject private var launchLog = LaunchLogStore()
    @State private var launchLogDismissed = false

    /// Armed on every entry into this view, which is once per game launch. Cleared by
    /// the intro itself when it has finished playing.
    @State private var showLaunchIntro = true
    /// A way out. The intro is theatre and theatre gets old on the fiftieth launch, so
    /// it is a setting rather than a fact of the app.
    @AppStorage("muffin.showLaunchIntro") private var launchIntroEnabled = true
    /// Guards the top-bar Back button while a title is actually running or paused -
    /// tapping it used to stop the game outright with no confirmation, which is one
    /// stray tap away from losing whatever progress the title itself hasn't saved.
    /// Not shown for .loading (nothing to lose yet) or .error (BootFailureView's own
    /// "Back to games" already IS the confirmation - there's no session underneath it).
    @State private var showingBackConfirmation = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Button(action: {
                        if gameManager.emulationState == .loading {
                            gameManager.stopEmulation()
                            isRunning = true
                        } else {
                            showingBackConfirmation = true
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                    }
                    .buttonStyle(MuffinSecondaryButtonStyle())
                    .confirmationDialog(
                        "Quit \(game.title)?",
                        isPresented: $showingBackConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Quit", role: .destructive) {
                            gameManager.stopEmulation()
                            isRunning = true
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Any progress the game itself hasn't saved will be lost.")
                    }

                    VStack(alignment: .center, spacing: 2) {
                        Text(game.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        Text(controllerSkin.name)
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundColor(MuffinTheme.pixelBlue)
                    }
                    .frame(maxWidth: .infinity)

                    HStack(spacing: 8) {
                        Button(action: { showSkinSelector.toggle() }) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(MuffinSecondaryButtonStyle())

                        // cemu_bridge_pause/resume wrap CafeSystem::PauseTitle()/
                        // ResumeTitle() (and, since the app-lifecycle work, also the
                        // Metal GPU thread's own drawable gate - see CemuBridge.mm).
                        // isPaused is local state rather than a query, because there is
                        // no cemu_bridge_is_paused() to ask. Two things change it now:
                        // this button and the .onChange(of: scenePhase) below - so it is
                        // pausedByLifecycle, not isPaused itself, that keeps the two from
                        // fighting over what a return to .active should do.
                        Button(action: {
                            isPaused.toggle()
                            if isPaused {
                                cemu_bridge_pause()
                            } else {
                                cemu_bridge_resume()
                            }
                        }) {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(MuffinSecondaryButtonStyle())

                        // Reachable without leaving the game, because the only way to
                        // tell whether the pad is in the right place is to have the
                        // game under it while you move it.
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditingControlLayout.toggle()
                            }
                            // Editing disables the buttons, and a button held at the
                            // moment it stops being able to report its own release
                            // would stay held inside the title.
                            cemu_bridge_release_all_buttons()
                        }) {
                            Image(systemName: isEditingControlLayout
                                  ? "checkmark.circle.fill"
                                  : "arrow.up.and.down.and.arrow.left.and.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(MuffinSecondaryButtonStyle())

                        // Reads the @Published frameRate directly rather than calling
                        // getFrameRate(): a plain method call cannot invalidate this
                        // view, so even once the value became real the HUD would only
                        // update when something else happened to redraw it. Until
                        // the emulator reports its first measurement this shows "--",
                        // not "0" - "0 FPS" reads as a measured stall, which is a
                        // different and much more alarming claim than "no reading yet".
                        //
                        // The string comes from EmulatorProgress rather than from
                        // frameRate alone because whole frames per second is the wrong
                        // unit for this port. Every rate the interpreter has actually
                        // produced rounds to zero there, so a title rendering slowly and
                        // a title that has stopped dead both read "-- FPS" - the one
                        // distinction anybody looking at this HUD needs. hudText() keeps
                        // frameRate in charge whenever it is non-zero, so a build that
                        // reaches a normal rate reads exactly as it always did, and only
                        // falls back to the engine's own counters below that.
                        HStack(spacing: 6) {
                            Image(systemName: "speedometer")
                                .font(.system(size: 12, weight: .semibold))
                            Text(gameManager.progress.hudText(wholeFramesPerSecond: gameManager.frameRate))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                        .foregroundColor(gameManager.frameRate >= 20 ? Color.green : MuffinTheme.blushPink)
                        .frame(height: 40)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                    }
                }
                .padding(12)
                .background(Color.black.opacity(0.5))
                .borderBottom(width: 0.5, color: Color.white.opacity(0.1))

                if showSkinSelector {
                    OrganizedControllerSkinSelector(selectedSkin: $controllerSkin)
                        .padding(12)
                        .background(Color.black.opacity(0.7))
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if previewPadEnabled && !useMeloControls {
                    // Video and pad have to agree on the exact same rect for Native mode
                    // to mean anything - a mismatch between two independent resolves
                    // would put the picture in one place and the "never overlaps it"
                    // guarantee somewhere else. So both are siblings inside ONE
                    // GeometryReader here, sharing one PreviewResolved, rather than the
                    // video living in the VStack and the pad spanning the full screen the
                    // way the shipping OptimizedControlPanel does below. The trade is
                    // real and worth stating plainly: in this preview path the pad no
                    // longer draws over the top bar/skin-selector area above it. The
                    // shipping path (this flag off, the default) is untouched by any of
                    // this - same MetalView, same .ignoresSafeArea(), same full-screen pad.
                    GeometryReader { proxy in
                        let insets = proxy.safeAreaInsets
                        let full = proxy.frame(in: .local)
                        let safeArea = CGRect(x: full.minX + insets.leading, y: full.minY + insets.top,
                                              width: full.width - insets.leading - insets.trailing,
                                              height: full.height - insets.top - insets.bottom)
                        let resolved = previewPad.resolve(container: proxy.size, safeArea: safeArea,
                                                          pointsPerInch: DeviceMetrics.current().pointsPerInch)
                        ZStack(alignment: .topLeading) {
                            #if os(iOS)
                            MetalViewIOS(gameManager: gameManager)
                            #else
                            MetalView(gameManager: gameManager)
                            #endif
                        }
                        .frame(width: previewPad.displayMode == .native ? resolved.video.width : proxy.size.width,
                              height: previewPad.displayMode == .native ? resolved.video.height : proxy.size.height)
                        .position(x: previewPad.displayMode == .native ? resolved.video.midX : proxy.size.width / 2,
                                 y: previewPad.displayMode == .native ? resolved.video.midY : proxy.size.height / 2)
                        .clipped()

                        PreviewControllerPad(
                            store: previewPad,
                            onInput: { label, pressed in
                                previewInputDebugCount += 1
                                previewInputDebugText = "\(label) \(pressed ? "down" : "up") (#\(previewInputDebugCount))"
                                cemu_bridge_set_button_state(cemuBridgeButton(forLabel: label), pressed)
                            },
                            onStick: { stick, position in
                                previewInputDebugCount += 1
                                previewInputDebugText = "stick\(stick) (\(String(format: "%.2f", position.x)), \(String(format: "%.2f", position.y))) (#\(previewInputDebugCount))"
                                cemu_bridge_set_stick_axis(
                                    stick == 0 ? CEMU_BRIDGE_STICK_LEFT : CEMU_BRIDGE_STICK_RIGHT,
                                    Float(position.x), Float(position.y)
                                )
                            },
                            isEditingLayout: $isEditingControlLayout
                        )

                        #if DEBUG
                        // Debug HUD: proves whether SwiftUI ever calls onInput/onStick at
                        // all, which is exactly the question a "controls don't do anything"
                        // report can't answer from the outside. Temporary, and gone the
                        // moment the real bug is found - not something to leave shipping.
                        VStack {
                            Text("PAD DEBUG: \(previewInputDebugText)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.yellow)
                                .padding(6)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(6)
                                .padding(.top, 4)
                            Spacer()
                        }
                        .allowsHitTesting(false)
                        #endif
                    }
                } else {
                    #if os(iOS)
                    MetalViewIOS(gameManager: gameManager)
                        .ignoresSafeArea()
                        // Defense in depth: tvGeometry() now sizes the TV CAMetalLayer
                        // from the real container instead of the whole screen, but
                        // .clipped() means a future regression of that (or a Vulkan/
                        // pad-surface path that inherits the same bug) shows a
                        // squashed picture instead of one bleeding past this view's
                        // edges into whatever SwiftUI content sits below it.
                        .clipped()
                    #else
                    MetalView(gameManager: gameManager)
                        .ignoresSafeArea()
                    #endif
                }
            }

            // Unconditional: no showControls state, no tap-to-toggle, no transition.
            // The pad is on screen for as long as the emulator view is, and floating
            // it here rather than stacking it under the Metal view is what actually
            // removes the grey slab - the panel no longer needs an opaque background
            // to sit on, so the game keeps the full height and the buttons are drawn
            // straight onto it.
            //
            // Placed above the Metal view but below the two overlays that follow, so
            // the boot screen still comes up clean rather than with a live-looking pad
            // sitting on a title that has not started. The launch log below carries the
            // bottom padding that keeps it clear of these buttons.
            //
            // These two closures used to be `{ _ in }`. The on-screen pad drew itself,
            // highlighted on touch and sent the result precisely nowhere, which is why
            // a touch could never move anything: not a missing mapping or an
            // unconfigured controller, just no call. OptimizedControlPanel reports
            // press AND release, and each label is translated here into the bridge's
            // own button numbering.
            // No VStack/Spacer any more: the pad positions every control itself against
            // the size it is handed, which is what lets one half be dragged somewhere a
            // bottom-aligned stack could never have put it.
            // Preview mode draws its own pad inside the GeometryReader above, alongside
            // the video it shares a coordinate space with - so the shipping pad only
            // renders when that flag is off, which is also its default.
            // Melo-Controller's pad, when chosen, takes the place of both of MuffinEMU's.
            if useMeloControls {
                MeloControlsOverlay(
                    gameID: gameManager.currentGame?.id,
                    isEditing: isEditingControlLayout
                )
            } else if !previewPadEnabled {
                OptimizedControlPanel(
                    skin: controllerSkin,
                    onInput: { label, pressed in
                        cemu_bridge_set_button_state(cemuBridgeButton(forLabel: label), pressed)
                    },
                    // The axis path. Deliberately not routed through the button call above:
                    // the bridge keeps sticks and buttons apart because the engine does, and
                    // a stick sent as a press reaches VPADRead's button loop, which skips
                    // the stick mappings outright.
                    onStick: { stick, position in
                        cemu_bridge_set_stick_axis(
                            stick == 0 ? CEMU_BRIDGE_STICK_LEFT : CEMU_BRIDGE_STICK_RIGHT,
                            Float(position.x),
                            Float(position.y)
                        )
                    },
                    isEditingLayout: $isEditingControlLayout
                )
            }

            // Above the pad (which stays on screen and interactive-looking underneath
            // it) so there is no ambiguity about whether input is actually reaching a
            // paused title - the label is the whole point, not just the pause itself.
            if isPaused {
                VStack(spacing: 10) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 40))
                    Text("PAUSED")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .tracking(2)
                }
                .foregroundColor(.white)
                .padding(28)
                .background(Color.black.opacity(0.6))
                .cornerRadius(20)
                .transition(.opacity)
                .allowsHitTesting(false)
            }

            // The Metal view above must mount (so it can register the render
            // surface) before boot() actually runs, so this state genuinely
            // overlaps with an on-screen MetalViewIOS for the first time now -
            // cover it with a status overlay until emulationState flips to .running.
            if gameManager.emulationState == .loading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Booting…")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))

                    if showLaunchLog {
                        LaunchLogView(store: launchLog)
                            .frame(maxWidth: 720, maxHeight: 340)
                            .padding(.horizontal, 24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
            }

            // The launch intro sits ON TOP of the booting overlay rather than replacing
            // it, and it is the thing you actually see. Underneath, boot proceeds at
            // exactly the pace it always did - the intro adds no wait of its own, it
            // occupies a wait that was already there and was previously a spinner.
            //
            // It clears itself when finished. It does NOT gate .running: the engine
            // flips that on its own schedule and the intro fading out reveals whatever
            // state the emulator has genuinely reached, which keeps the animation
            // honest about the boot instead of pretending to drive it.
            //
            // Hidden while the launch log is up. Someone who has turned that on is
            // diagnosing a boot, and covering the log with an animation would be
            // exactly the wrong call.
            if showLaunchIntro && launchIntroEnabled && !showLaunchLog {
                LaunchIntroView { showLaunchIntro = false }
                    .transition(.opacity)
                    .zIndex(10)
            }

            // Deliberately outlives .loading. emulationState flips to .running the
            // moment boot() returns, which is BEFORE the GPU thread has presented
            // anything - so the interesting part of the log (first swap request, first
            // present, or the silence where those should be) all happens after the
            // boot overlay above has already gone. Hiding the log at .running would
            // hide exactly the lines that explain a black screen. It stays, small and
            // dismissable, until the user closes it.
            if showLaunchLog && gameManager.emulationState == .running && !launchLogDismissed {
                VStack {
                    Spacer()
                    LaunchLogView(store: launchLog) {
                        withAnimation(.easeInOut(duration: 0.2)) { launchLogDismissed = true }
                    }
                    .frame(maxWidth: 720, maxHeight: 240)
                    .padding(.horizontal, 24)
                    // Clears the control pad, which now floats over the bottom of the
                    // game instead of occupying a strip below it. 24pt was enough only
                    // while the pad lived somewhere the log could never reach.
                    .padding(.bottom, 180)
                }
                .transition(.opacity)
            }

            // Last in the ZStack so it sits above the pad it is adjusting - a size
            // slider you have to hunt for behind a button is not an adjustment anyone
            // makes twice. Everything here writes to the same AppStorage keys the pad
            // reads, so the change is under the finger as the slider moves.
            if isEditingControlLayout {
                VStack {
                    VStack(spacing: 10) {
                        Picker("Edit mode", selection: $individualEditMode) {
                            Text("Grouped").tag(false)
                            Text("Individual").tag(true)
                        }
                        .pickerStyle(.segmented)

                        Text(individualEditMode
                             ? "Drag any button to move it on its own, or pinch it to resize. L and ZL move together, and so do R and ZR. Nothing here reaches the game."
                             : "Drag the empty space inside a dashed box to move that whole half - L/ZL and the rest of the left side together, R/ZR and the right side together. Nothing here reaches the game.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .multilineTextAlignment(.center)

                        HStack(spacing: 10) {
                            Image(systemName: "minus.magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                            Slider(
                                value: $controlScale,
                                in: ControllerLayoutSettings.minScale...ControllerLayoutSettings.maxScale
                            )
                            Image(systemName: "plus.magnifyingglass")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        HStack(spacing: 10) {
                            Image(systemName: "circle.lefthalf.filled")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                            Slider(value: $controlOpacity, in: 0.2...1.0)
                            Image(systemName: "circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        Toggle(isOn: $joystickMode) {
                            Text("Joystick instead of d-pad")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .tint(MuffinTheme.brownDarkest)

                        if joystickMode {
                            Toggle(isOn: $comfortControls) {
                                Text("Comfort controls")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                            .tint(MuffinTheme.brownDarkest)

                            Text(comfortControls
                                 ? "L, ZL and minus sit on the left stick; R, ZR and plus sit on the right stick."
                                 : "L, ZL and minus stay on the d-pad; R, ZR and plus stay on A/B/X/Y.")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.65))

                            Picker("Gate", selection: $stickGateRaw) {
                                ForEach(ControllerGeometry.StickGate.allCases) { gate in
                                    Text(gate.title).tag(gate.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)

                            HStack(spacing: 10) {
                                Text("Deadzone")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.85))
                                Slider(
                                    value: $stickDeadzone,
                                    in: ControllerLayoutSettings.minDeadzone...ControllerLayoutSettings.maxDeadzone
                                )
                                // Fixed width, so dragging the slider does not make the
                                // slider itself change size under the finger as the
                                // number beside it gets wider.
                                Text(stickDeadzone <= 0.0005
                                     ? "off"
                                     : "\(Int((stickDeadzone * 100).rounded()))%")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.7))
                                    .frame(width: 34, alignment: .trailing)
                            }

                            HStack(spacing: 10) {
                                Text("Fine")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.85))
                                Slider(
                                    value: $stickCurve,
                                    in: ControllerLayoutSettings.minStickCurve...ControllerLayoutSettings.maxStickCurve
                                )
                                Text(stickCurve <= ControllerLayoutSettings.minStickCurve + 0.005
                                     ? "lin"
                                     : String(format: "%.1fx", stickCurve))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.7))
                                    .frame(width: 34, alignment: .trailing)
                            }
                        }

                        HStack(spacing: 12) {
                            Button("Reset layout") { ControllerLayoutSettings.reset() }
                                .buttonStyle(MuffinSecondaryButtonStyle())

                            Button("Done") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingControlLayout = false
                                }
                            }
                            .buttonStyle(MuffinSecondaryButtonStyle())
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: 420)
                    .background(Color.black.opacity(0.82))
                    .cornerRadius(14)
                    .padding(.top, 12)

                    Spacer()
                }
                .transition(.opacity)
            }
        }
        // No full-screen tap gesture. There used to be one here toggling showControls,
        // which meant every stray tap on the game could take the pad away and every
        // press near an edge risked doing it by accident. The controls are permanent,
        // so there is nothing left to toggle and taps on the game are just taps.
        //
        // Tied to this view's lifetime, not the store's: no launch log on screen means
        // nothing draining, and the C ring keeps filling either way so switching the
        // setting on mid-boot still catches up on everything already logged.
        .onAppear { if showLaunchLog { launchLog.start() } }
        .onDisappear {
            launchLog.stop()
            // The pad can no longer vanish mid-press while a title runs, so the only
            // way out from under a held finger is leaving the emulator entirely. Each
            // button releases itself on disappear; this sweeps anyway, because a button
            // the title still thinks is held survives into the next launch. Idempotent.
            cemu_bridge_release_all_buttons()
        }
        .onChange(of: showLaunchLog) { enabled in
            if enabled { launchLog.start() } else { launchLog.stop() }
        }
        // The whole reason this exists: before it, nothing anywhere in this app
        // hooked app lifecycle at all - switching apps or locking the screen left
        // the emulator running full tilt, guest CPU and all, which both burns
        // battery/CPU in the background and keeps the Latte thread submitting
        // Metal work. iOS terminates apps that submit Metal command buffers while
        // backgrounded, so that second half is not just wasteful, it is a crash
        // waiting to happen - and a very plausible cause of reported
        // crashes/instability whenever backgrounding was involved.
        //
        // .inactive and .background both count as "left the foreground" and are
        // treated identically: .inactive already precedes .background on the way
        // out, so waiting for .background specifically would spend part of iOS's
        // few-second grace window before suspension instead of all of it.
        //
        // cemu_bridge_pause()/cemu_bridge_resume() (CemuBridge.mm) are safe to call
        // even if nothing has finished booting yet - CafeSystem::PauseTitle()/
        // ResumeTitle() no-op when no title is running, and the Metal GPU-thread
        // gate they also flip is harmless to set on a renderer that exists but has
        // not presented a frame yet. Nothing here checks emulationState first
        // because there is nothing safer to gate on: this view does not exist
        // unless a game is loading, running, or paused (see ContentView's switch
        // over emulationState) - so "pause when nothing is loaded" is already a
        // structural no-op rather than something to re-check here, and re-checking
        // via cemu_bridge_is_title_running() would only narrow the window in which
        // the GPU gate above gets closed, not widen any safety margin.
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                guard pausedByLifecycle else { return }
                pausedByLifecycle = false
                isPaused = false
                cemu_bridge_resume()
            } else {
                // Released on every trip out of .active, paused or not. A touch in
                // progress when the app resigns active is cancelled by UIKit, which does
                // not reliably deliver the gesture's end, so without this a held button or
                // deflected stick would still be held when the game comes back.
                cemu_bridge_release_all_buttons()
                guard !isPaused else { return }
                isPaused = true
                pausedByLifecycle = true
                cemu_bridge_pause()
            }
        }
        // Keeps the home indicator (and the system's own edge-swipe gestures) from
        // popping up mid-game - a stray swipe near the bottom edge no longer competes
        // with on-screen controls sitting right where it appears.
        .hidingSystemOverlaysDuringPlay()
    }
}

/// `.persistentSystemOverlays` is iOS 16+; this makes calling it from a 15-deployment-
/// target file a real no-op on 15 rather than an availability error. The pad's own
/// hit-testing is the only defense against an edge swipe on iOS 15 - there is no
/// system API here to fall back to.
private struct HideSystemOverlaysIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.persistentSystemOverlays(.hidden)
        } else {
            content
        }
    }
}

private extension View {
    func hidingSystemOverlaysDuringPlay() -> some View {
        modifier(HideSystemOverlaysIfAvailable())
    }
}

// The on-screen pad speaks in labels ("up", "A", "ZL") because that is what it draws. The
// engine speaks in CemuBridgeButton. Keeping the translation here, at the one call site,
// rather than inside the view means ControllerPad.swift stays a pure SwiftUI file with no
// dependency on the bridge at all.
//
// One function now rather than two, because the pad no longer has two kinds of control to
// tell apart: the d-pad, the face buttons, the shoulders, plus/minus and the stick clicks
// all report through the same closure, and the bridge has had an id for every one of them
// since CemuBridge.h was written - it was the pad that was only drawing eight of them.
private func cemuBridgeButton(forLabel label: String) -> CemuBridgeButton {
    switch label {
    case "up":    return CEMU_BRIDGE_BUTTON_UP
    case "down":  return CEMU_BRIDGE_BUTTON_DOWN
    case "left":  return CEMU_BRIDGE_BUTTON_LEFT
    case "right": return CEMU_BRIDGE_BUTTON_RIGHT

    case "A": return CEMU_BRIDGE_BUTTON_A
    case "B": return CEMU_BRIDGE_BUTTON_B
    case "X": return CEMU_BRIDGE_BUTTON_X
    case "Y": return CEMU_BRIDGE_BUTTON_Y

    case "L":  return CEMU_BRIDGE_BUTTON_L
    case "R":  return CEMU_BRIDGE_BUTTON_R
    case "ZL": return CEMU_BRIDGE_BUTTON_ZL
    case "ZR": return CEMU_BRIDGE_BUTTON_ZR

    case "plus":  return CEMU_BRIDGE_BUTTON_PLUS
    case "minus": return CEMU_BRIDGE_BUTTON_MINUS

    // The stick clicks. In d-pad mode these are the two small grey dots in the middle
    // of each cluster; in joystick mode the left one is a tap on the stick itself, which
    // is where L3 went when the knob took the dot's place. The bridge now has a real
    // axis call as well (cemu_bridge_set_stick_axis), and it is deliberately not routed
    // through here - these two ids are the click and only the click.
    case "L3": return CEMU_BRIDGE_BUTTON_STICK_L
    case "R3": return CEMU_BRIDGE_BUTTON_STICK_R

    default: return CEMU_BRIDGE_BUTTON_NONE
    }
}

struct BorderBottomModifier: ViewModifier {
    let width: CGFloat
    let color: Color

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            content
            Divider()
                .frame(height: width)
                .background(color)
        }
    }
}

extension View {
    func borderBottom(width: CGFloat, color: Color) -> some View {
        self.modifier(BorderBottomModifier(width: width, color: color))
    }
}

#Preview {
    ContentView()
}
