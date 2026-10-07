import SwiftUI
import MetalKit
import UniformTypeIdentifiers
import Foundation

struct ContentView: View {
    @StateObject var gameManager = GameManager()
    @Environment(\.scenePhase) private var appScenePhase
    @AppStorage(OnboardingState.completedKey) private var onboardingCompleted = false
    // What the welcome guide's full-screen cover follows. Its own state rather than a binding computed from
    // onboardingCompleted: Settings > About > "Show welcome guide again" clears that flag and posts a notification, and a
    // cover bound to the flag tried to present while the Settings sheet was still up (SwiftUI drops that), and once
    // shown could not be closed because only the flag was reset on Finish.
    @State private var showOnboarding = OnboardingState.shouldPresentOnFirstLaunch
    @State private var selectedGame: GameMetadata?
    @State private var showingGameBrowser = true
    @State private var showingFavorites = false
    @State private var sharedImportError: String?
    /// The skin's name, stored so the choice survives relaunch (it used to be @State and reset to Standard).
    /// A name rather than the skin: ControllerSkinLibrary.getSkin(by:) also resolves renamed skins.
    @AppStorage(ControllerSkinStorage.key) private var selectedSkinName = WiiUControllerSkin.standard.name

    private var selectedSkin: Binding<WiiUControllerSkin> {
        Binding(
            get: { ControllerSkinLibrary.getSkin(by: selectedSkinName) ?? WiiUControllerSkin.standard },
            set: { selectedSkinName = $0.name }
        )
    }

    /// Wii U game files MuffinEMU claims; anything else opened into the app is ignored.
    static let sharedGameExtensions: Set<String> = ["wua", "wud", "wux", "rpx"]

    private func openSharedFile(_ url: URL) {
        guard url.isFileURL, Self.sharedGameExtensions.contains(url.pathExtension.lowercased()) else { return }
        if gameManager.emulationState == .idle { showingGameBrowser = true }
        Task {
            do {
                try await gameManager.importROM(from: url)
            } catch {
                sharedImportError = error.localizedDescription
            }
            // A shared copy lands in Documents/Inbox; once imported it is only clutter in Files.
            if url.path.contains("/Documents/Inbox/") { try? FileManager.default.removeItem(at: url) }
        }
    }

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
                        controllerSkin: selectedSkin
                    )
                    .overlay(alignment: .top) {
                        if let notice = gameManager.launchNotice {
                            LaunchNoticeBanner(text: notice)
                                .padding(.top, 24)
                                .padding(.horizontal, 16)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .allowsHitTesting(false)
                        }
                    }
                case .error:
                    BootFailureView(
                        game: game,
                        message: gameManager.lastStatusMessage,
                        needsCleanRestart: gameManager.needsCleanRestart,
                        endedWhileRunning: gameManager.titleEndedByEngine,
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
        // "Open with MuffinEMU", "Copy to MuffinEMU" from the share sheet, and AirDrop: a Wii U game
        // file is imported exactly as if it had been picked in the library.
        .onOpenURL { url in openSharedFile(url) }
        // Theme music in the library (Settings > Audio): only while no game is running and the app is on screen.
        .onAppear { MenuMusic.shared.update(emulationState: gameManager.emulationState, appActive: appScenePhase == .active) }
        .onChange(of: gameManager.emulationState) { state in
            MenuMusic.shared.update(emulationState: state, appActive: appScenePhase == .active)
        }
        .onChange(of: appScenePhase) { phase in
            MenuMusic.shared.update(emulationState: gameManager.emulationState, appActive: phase == .active)
        }
        .alert("Couldn't add that game", isPresented: Binding(
            get: { sharedImportError != nil }, set: { if !$0 { sharedImportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sharedImportError ?? "")
        }
        .jitEnablerPrompt(blocked: { [gameManager] in
            switch gameManager.emulationState {
            case .idle, .error: return false
            case .loading, .running, .paused: return true
            }
        })
        // First launch, and again whenever Settings > About resets the flag. The library closes Settings first
        // (GameBrowserView), so the guide waits for that sheet to finish going away.
        .onReceive(NotificationCenter.default.publisher(for: .muffinReopenOnboarding)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { showOnboarding = true }
        }
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: { onboardingCompleted = true }) {
            OnboardingView(gameManager: gameManager) {
                onboardingCompleted = true
                showOnboarding = false
            }
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
    /// Set when the launch was refused because the last game left the emulator in a state that only an app restart fixes.
    var needsCleanRestart: Bool = false
    /// Set when the game was running and the engine ended it (it quit, or something fatal happened), as opposed to never starting.
    var endedWhileRunning: Bool = false
    let onDismiss: () -> Void

    /// The name the library card shows, not the dump's file name.
    private var name: String { game.displayTitle ?? game.title }

    /// Where the diagnostics actually are. Computed from the bridge rather than written
    /// down here, because only the bridge knows what $HOME resolved to when it opened the
    /// file, and that differs between a normal install and a LiveContainer one.
    private static var crashLogHint: String {
        let path = String(cString: cemu_bridge_crash_log_path())
        guard !path.isEmpty else {
            return "If you report this, include log.txt. No crash log could be opened this run, so there is no CemuCrashLog.txt to send."
        }
        return "If you report this, include log.txt and CemuCrashLog.txt. They are in:\n\(path)"
    }

    private var title: String {
        if needsCleanRestart { return "Restart needed before \(name)" }
        return endedWhileRunning ? "\(name) stopped" : "Couldn't start \(name)"
    }

    /// Keys the player added from this screen. Nil until they do.
    @State private var keysAdded: Int?
    @State private var keysError: String?

    /// An encrypted disc image or game folder, with no keys.txt installed: the likely reason it didn't start. Homebrew
    /// (.rpx, .elf, .wuhb), decrypted dumps and .wua archives don't need keys.
    private var needsKeys: Bool {
        guard !needsCleanRestart, !endedWhileRunning, keysAdded == nil, !WiiUKeys.keysFileExists() else { return false }
        return ["wux", "wud", "iso", "tmd"].contains(URL(fileURLWithPath: game.romPath).pathExtension.lowercased())
    }

    /// What to do next, in plain words. The engine's own message and the log paths are under Details.
    private var plainLine: String {
        if needsCleanRestart { return "Close MuffinEMU and open it again from your Home Screen, then start a game." }
        if endedWhileRunning { return "The game stopped. Go back and try it again. If it keeps happening, close and reopen MuffinEMU." }
        if needsKeys { return "This game is encrypted, so it needs a keys.txt file to start." }
        if let keysAdded { return "Added \(keysAdded) key\(keysAdded == 1 ? "" : "s"). Go back and start the game again. If it still won't start, close and reopen MuffinEMU." }
        return "This game didn't start. Try again. If it keeps happening, close and reopen MuffinEMU."
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Scrolls: on an iPhone in landscape, or at a large text size, the whole card is taller
            // than the screen, and the buttons are at the bottom.
            GeometryReader { proxy in
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
            }
        }
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

    private var content: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(MuffinTheme.alertOnDark)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(plainLine)
                .font(.system(.footnote, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)

            if let keysError {
                Text(keysError)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundColor(MuffinTheme.alertOnDark)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            if needsKeys {
                Button(action: importKeys) {
                    HStack(spacing: 6) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Import keys.txt")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                }
                .buttonStyle(MuffinPrimaryButtonStyle())
            }

            // The engine's own words and where the logs are, for anyone reporting the problem. Empty message only if
            // the bridge never set anything, which is itself worth seeing rather than papering over. The path is
            // asked of the bridge: LiveContainer redirects HOME per hosted app, so a written-down folder is wrong there.
            DisclosureGroup("Details") {
                VStack(spacing: 10) {
                    Text(message.isEmpty ? "The engine didn't report a reason." : message)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    Text(Self.crashLogHint)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
            .font(.system(.footnote, design: .rounded))
            .foregroundColor(.white.opacity(0.75))
            .accentColor(.white.opacity(0.75))
            .frame(maxWidth: 480)

            if needsCleanRestart {
                // Closing is the player's own tap, never automatic. iOS gives an app no way to relaunch itself, and
                // exit(0) after a tap is accepted for a sideloaded app. _exit, not exit: exit() runs the core's
                // static destructors while its threads are still alive, and one of them then locks a destroyed
                // mutex ("mutex lock failed: Invalid argument" in the crash log). Flush, then leave without them.
                Button(action: { fflush(nil); _exit(0) }) {
                    Text("Close MuffinEMU")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                .buttonStyle(MuffinPrimaryButtonStyle())
                .padding(.top, 4)
            }

            Button(action: onDismiss) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back to games")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
            }
            .buttonStyle(MuffinBarButtonStyle())
            .padding(.top, 4)
        }
        .padding(32)
    }
}

/// How the library grid orders games, offered next to the search field. Persisted via
/// `sortOrderRaw` below rather than reset every launch - a choice someone made once
/// shouldn't need remaking every time they open the app.
enum LibrarySortOrder: String, CaseIterable, Hashable {
    case title
    case recentlyAdded
    case favoritesFirst
    case lastPlayed
    case mostPlayed

    var title: String {
        switch self {
        case .title: return "Title"
        case .recentlyAdded: return "Recently added"
        case .favoritesFirst: return "Favourites first"
        case .lastPlayed: return "Last played"
        case .mostPlayed: return "Most played"
        }
    }

    var systemImage: String {
        switch self {
        case .title: return "textformat"
        case .recentlyAdded: return "clock"
        case .favoritesFirst: return "heart"
        case .lastPlayed: return "clock.arrow.circlepath"
        case .mostPlayed: return "flame"
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
    func sorted(_ games: [GameMetadata], stats: LibraryPlayStats = .shared) -> [GameMetadata] {
        let byTitle: (GameMetadata, GameMetadata) -> Bool = {
            $0.sortTitle.localizedCaseInsensitiveCompare($1.sortTitle) == .orderedAscending
        }
        switch self {
        case .lastPlayed:
            // Never-played games go after the played ones, in title order.
            return games.sorted { lhs, rhs in
                switch (stats.entry(for: lhs.id)?.last, stats.entry(for: rhs.id)?.last) {
                case let (l?, r?): return l > r
                case (nil, nil): return byTitle(lhs, rhs)
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        case .mostPlayed:
            return games.sorted { lhs, rhs in
                let l = stats.entry(for: lhs.id)?.count ?? 0
                let r = stats.entry(for: rhs.id)?.count ?? 0
                return l != r ? l > r : byTitle(lhs, rhs)
            }
        case .title:
            return games.sorted { $0.sortTitle.localizedCaseInsensitiveCompare($1.sortTitle) == .orderedAscending }
        case .recentlyAdded:
            return games.sorted { lhs, rhs in
                switch (lhs.addedDate, rhs.addedDate) {
                case let (l?, r?): return l > r
                case (nil, nil): return lhs.sortTitle.localizedCaseInsensitiveCompare(rhs.sortTitle) == .orderedAscending
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        case .favoritesFirst:
            return games.sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
                return lhs.sortTitle.localizedCaseInsensitiveCompare(rhs.sortTitle) == .orderedAscending
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

/// One line over the game about how this launch differed from the request, for example Vulkan not starting so Metal
/// was used. Fades on its own (GameManager.showLaunchNotice) and never takes touches.
struct LaunchNoticeBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(MuffinTheme.brownDarkest)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(MuffinTheme.cream)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(MuffinTheme.wrapper, lineWidth: 1)
            )
            .shadow(color: MuffinTheme.shadow.opacity(0.15), radius: 8, x: 0, y: 4)
            .frame(maxWidth: 520)
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
    /// Which game's page is open - the sheet's own presence, not a separate Bool, so there is
    /// no way for the sheet to open pointed at the wrong game.
    @State private var gamePageTarget: GameMetadata?
    @AppStorage(LibraryTapAction.storageKey) private var tapActionRaw = LibraryTapAction.defaultValue.rawValue
    /// Same pattern as gamePageTarget, for "Decrypt…" (DecryptROMView.swift).
    @State private var decryptTarget: GameMetadata?
    /// Same pattern again, for "Change Cover Art…" (CoverArtPickerView.swift).
    @State private var coverArtTarget: GameMetadata?
    @ObservedObject private var perGameSettings = PerGameSettingsStore.shared
    @ObservedObject private var playStats = LibraryPlayStats.shared
    @ObservedObject private var customNames = LibraryCustomNames.shared
    @State private var renameTarget: GameMetadata?
    @AppStorage(LibraryCardStyle.storageKey) private var cardStyleRaw = LibraryCardStyle.defaultValue.rawValue
    @AppStorage(CoverStylePreference.storageKey) private var coverModeRaw = CoverStylePreference.defaultValue.rawValue
    @AppStorage(LibraryGrouping.storageKey) private var groupingRaw = LibraryGrouping.defaultValue.rawValue
    @AppStorage(LibraryFilter.storageKey) private var filterRaw = LibraryFilter.defaultValue.rawValue
    @Environment(\.scenePhase) private var scenePhase
    /// Set by "Remove game...". Deleting waits for the confirmation below.
    @State private var pendingGameRemoval: GameMetadata?
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
    private static let helpURL = URL(string: "https://muffinemu.github.io/MuffinEMU/docs/")!

    /// Persisted so the chosen order survives a relaunch, same reasoning as favorites.
    @AppStorage("muffin.library.sortOrder") private var sortOrderRaw = LibrarySortOrder.title.rawValue
    private var sortOrder: LibrarySortOrder {
        get { LibrarySortOrder(rawValue: sortOrderRaw) ?? .title }
        // nonmutating: the sort menu assigns this from a Button action, where the view is
        // immutable. The write lands in @AppStorage, not in the struct, so it never needed
        // to mutate self.
        nonmutating set { sortOrderRaw = newValue.rawValue }
    }

    /// Settings > Wii U Menu. The Menu is a bar above the grid by default; these turn it
    /// into a card in the grid, or take it out of the library (it stays installed).
    @AppStorage(WiiUMenuSettings.showAsCardKey) private var menuAsCard = WiiUMenuSettings.defaultShowAsCard
    @AppStorage(WiiUMenuSettings.hideKey) private var menuHidden = WiiUMenuSettings.defaultHidden
    @ObservedObject private var menuStore = WiiUMenuStore.shared

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
    /// long-pressed to start the import (automatic matching with manual
    /// fallback). Retrying is what actually calls DlcUpdateImport.import again
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
            : gamesToShow.filter {
                $0.title.localizedCaseInsensitiveContains(searchText)
                    || ($0.displayTitle?.localizedCaseInsensitiveContains(searchText) ?? false)
                    || (customNames.name(for: $0.installKey)?.localizedCaseInsensitiveContains(searchText) ?? false)
                    || ($0.installLabel?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        let filtered = (LibraryFilter(rawValue: filterRaw) ?? .all).apply(searched, stats: playStats)
        return sortOrder.sorted(filtered, stats: playStats)
    }

    private var libraryCardStyle: LibraryCardStyle {
        // Covers > 3D turns every card into a box; otherwise the chosen layout.
        CoverStylePreference(stored: coverModeRaw) == .threeD ? .box3d : (LibraryCardStyle(rawValue: cardStyleRaw) ?? .standard)
    }

    private var librarySections: [LibrarySection] {
        (LibraryGrouping(rawValue: groupingRaw) ?? .none).sections(for: filteredGames, stats: playStats)
    }

    /// The Menu is offered in the library at all: installed, not hidden, and not being
    /// searched for or filtered to favourites.
    private var menuOffered: Bool {
        !menuHidden && menuStore.status.menuInstalled && searchText.isEmpty && !showingFavorites
    }
    private var showsMenuBar: Bool { menuOffered && !menuAsCard }
    private var showsMenuCard: Bool { menuOffered && menuAsCard }

    private func launchMenu(_ menu: GameMetadata) {
        guard gameManager.emulationState == .idle else { return }
        selectedGame = menu
        gameManager.launchGame(menu)
        showingGameBrowser = false
    }

    var body: some View {
        withAlerts(withSheets(
            libraryScreen
            // Games dropped into Files > On My iPad > MuffinEMU > Roms while the app was in the background show up on return.
            .onChange(of: scenePhase) { phase in
                if phase == .active { Task { await gameManager.rescanIfIdle() } }
            }
            // The welcome guide (ContentView) can't present over the Settings sheet, so close it first.
            .onReceive(NotificationCenter.default.publisher(for: .muffinReopenOnboarding)) { _ in
                showingSettings = false
            }
            .onAppear {
                #if os(iOS)
                // Back at the library with nothing running: take back any starting controls or screen
                // layout a game's hints turned on, so Settings shows what the person chose (GameControlHints).
                if gameManager.emulationState == .idle { GameControlHints.restoreGlobals() }
                #endif
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
        ))
    }

    // body is split into these pieces because as one expression - the screen, a drop
    // target and overlay, five sheets and six alerts - it grew past what the Swift type
    // checker will solve in reasonable time. Same views, same modifier order.
    private var libraryScreen: some View {
        ZStack {
            MuffinTheme.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                libraryHeader

                libraryPanel
            }
        }
    }

    private var libraryHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Button(action: { showingIconPicker = true }) {
                VStack(alignment: .leading, spacing: 4) {
                    // onBackground rather than fixed cream and accent: cream was 1.9:1 on
                    // Bakery's light orange, and the accent was dark on the dark gradients.
                    Text("Muffin")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(MuffinTheme.onBackground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("EMU")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(MuffinTheme.onBackgroundAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                // Four 44pt buttons share the row; on a 320pt-wide phone the wordmark
                // shrinks a little instead of truncating to "Muf...".
            }
            .buttonStyle(.plain)
            // VoiceOver read only "Muffin, EMU" with nothing saying what a tap does.
            .accessibilityLabel("MuffinEMU")
            .accessibilityHint("Changes the app icon.")

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Button(action: { showingSettings = true }) {
                        // No foregroundColor here on purpose. MuffinSecondaryButtonStyle
                        // already paints its label MuffinTheme.brownDark, which is the ink
                        // colour that token pairs with - the style's fill is
                        // MuffinTheme.cream. This icon used to override that with
                        // sparkleCream, and sparkleCream's own doc comment says what it is
                        // for: "button text painted onto the muffin-top gradient fill",
                        // i.e. the ORANGE primary button. Painted onto the cream secondary
                        // button instead, it was light cream on cream and the glyph
                        // vanished until pressed.
                        //
                        // Deleting the override rather than substituting another colour is
                        // the fix, because it hands the decision back to the one place that
                        // knows the fill. It also follows every theme: all 31 palettes
                        // define their own brownDark/cream pair, so this stays legible in
                        // each of them and in dark mode, which a hardcoded replacement
                        // colour would not.
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(MuffinSecondaryButtonStyle())
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Settings")

                    Button(action: { showingFavorites.toggle() }) {
                        // Same fix as the gear above, with one difference: the ACTIVE
                        // state keeps an explicit pink. That is a real state colour
                        // carrying information ("favourites only is on"), and it is the
                        // one case here where overriding the style's ink is deliberate
                        // rather than accidental. alertText rather than raw blushPink,
                        // which was under 2:1 on cream in half the themes. Only the
                        // inactive branch - the invisible one - gives its colour back to
                        // the button style.
                        Image(systemName: showingFavorites ? "heart.fill" : "heart")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(showingFavorites ? MuffinTheme.alertText : MuffinTheme.brownDark)
                    }
                    .buttonStyle(MuffinSecondaryButtonStyle())
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(showingFavorites ? "Show all games" : "Show favourites only")

                    Menu {
                        Button {
                            beginImport(contentTypes: Self.fileImportTypes)
                        } label: {
                            Label("Game file", systemImage: "doc")
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
                            Label("Game folder", systemImage: "folder")
                        }
                        Button {
                            beginKeysImport()
                        } label: {
                            Label("Keys (keys.txt)", systemImage: "key")
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
                        Divider()
                        Link(destination: Self.helpURL) {
                            Label("Help & troubleshooting", systemImage: "questionmark.circle")
                        }
                    } label: {
                        // Same bug and same colour as the two buttons above, but stated
                        // explicitly rather than inherited. This is a Menu, not a Button,
                        // and a ButtonStyle's foregroundColor does not propagate into a
                        // Menu's label as dependably as it does into a Button's across the
                        // iOS versions this app supports (15 through 27). Naming
                        // brownDark here is the same value MuffinSecondaryButtonStyle
                        // would have applied, so it still tracks every theme and dark
                        // mode - it just does not depend on that propagation happening.
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(MuffinTheme.brownDark)
                    }
                    .buttonStyle(MuffinSecondaryButtonStyle())
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Import")

                    // On a cream chip like the buttons beside it. Bare, it was cream at 70%
                    // and 10pt straight on the gradient, which no theme could keep readable
                    // across the whole width of an iPad.
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(filteredGames.count)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(MuffinTheme.brownDarkest)
                        Text("games")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(MuffinTheme.brownMid)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(MuffinTheme.cream, in: RoundedRectangle(cornerRadius: MuffinTheme.Radius.chip, style: .continuous))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(20)
    }

    private var libraryPanel: some View {
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

                LibraryViewMenu()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // The Wii U Menu, when one is installed. Pinned above the grid, not part of it, so
            // sorting never moves it; it is hidden while searching or viewing favourites.
            // Settings can instead put it in the grid as a card, or hide it.
            if showsMenuBar {
                WiiUMenuTile(onLaunch: launchMenu)
            }

            if gameManager.isLoading {
                LoadingView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredGames.isEmpty && !showsMenuCard {
                EmptyGamesView(
                    kind: !searchText.isEmpty ? .noSearchMatch(searchText) : (showingFavorites ? .noFavourites : .emptyLibrary),
                    onImportTapped: { beginImport(contentTypes: Self.fileImportTypes) }
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LibraryGameCollection(
                    sections: librarySections,
                    style: libraryCardStyle,
                    lead: {
                        if showsMenuCard {
                            WiiUMenuCard(onLaunch: launchMenu)
                        }
                    },
                    card: { game in
                            LibraryCard(
                                game: game,
                                style: libraryCardStyle,
                                onTap: {
                                    if LibraryTapAction.current(raw: tapActionRaw) == .openPage {
                                        gamePageTarget = game
                                    } else {
                                        playGame(game)
                                    }
                                },
                                onFavoriteTap: {
                                    gameManager.toggleFavorite(game)
                                },
                                onPlay: { playGame(game) },
                                options: { gameMenu(for: game) }
                            )
                            // Same pattern as Manic: a long-press on the card
                            // offers a couple of fast toggles plus a way into the
                            // full screen, rather than making every per-game
                            // setting a trip through Settings for one game. The
                            // "..." button on the card opens the same menu.
                            .contextMenu { gameMenu(for: game) }
                    }
                )
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

    /// The per-game menu: the long-press menu, and the "..." button on each card. Only the quick
    /// actions live here; everything else is on the game's page.
    @ViewBuilder private func gameMenu(for game: GameMetadata) -> some View {
        GameContextMenu(
            game: game,
            gameManager: gameManager,
            onPlay: { playGame(game) },
            onOpenPage: { gamePageTarget = game },
            onChangeCoverArt: { coverArtTarget = game },
            onRename: { renameTarget = game }
        )
        Divider()
        Button(role: .destructive) {
            pendingGameRemoval = game
        } label: {
            DestructiveSettingsLabel(title: "Remove game\u{2026}", systemImage: "trash")
        }
    }

    /// Starts a game from the library. A second tap while a launch is under way must not swap the
    /// game the screen thinks it is showing.
    private func playGame(_ game: GameMetadata) {
        guard gameManager.emulationState == .idle else { return }
        selectedGame = game
        gameManager.launchGame(game)
        showingGameBrowser = false
    }

    private func removeGameNow(_ game: GameMetadata) {
        pendingGameRemoval = nil
        removingContentMessage = "Removing \"\(game.cardName.name)\"\u{2026}"
        Task {
            do {
                try await gameManager.removeGame(game)
            } catch {
                dlcImportErrorMessage = error.localizedDescription
            }
            removingContentMessage = nil
        }
    }

    private func withSheets<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showingIconPicker) {
                IconPickerView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(gameManager: gameManager)
            }
            .sheet(item: $renameTarget) { game in
                LibraryRenameSheet(game: game)
            }
            .sheet(item: $gamePageTarget) { game in
                GamePageView(
                    game: game,
                    store: perGameSettings,
                    gameManager: gameManager,
                    onPlay: { playGame(game) },
                    onDecrypt: { decryptTarget = game },
                    onImportDLC: { beginDlcUpdateImport(for: game, kind: .dlc) },
                    onImportUpdate: { beginDlcUpdateImport(for: game, kind: .update) },
                    onRemoveDLC: { pendingRemoval = (game: game, kind: .dlc) },
                    onRemoveUpdate: { pendingRemoval = (game: game, kind: .update) },
                    onRemoveGame: { removeGameNow(game) }
                )
            }
            .sheet(item: $decryptTarget) { game in
                DecryptROMView(game: game)
            }
            .sheet(item: $coverArtTarget) { game in
                CoverArtPickerView(game: game, gameManager: gameManager)
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
    }

    private func withAlerts<Content: View>(_ content: Content) -> some View {
        content
            .modifier(AudioRecordingNoticeModifier())
            .alert("Added", isPresented: .constant(dlcUpdateSuccessMessage != nil), presenting: dlcUpdateSuccessMessage) { _ in
                Button("OK") { dlcUpdateSuccessMessage = nil }
            } message: { message in
                Text(message)
            }
            .alert("Couldn't add that game", isPresented: .constant(romImportErrorMessage != nil), presenting: romImportErrorMessage) { _ in
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
            .confirmationDialog(
                "Remove content?",
                isPresented: .constant(pendingRemoval != nil),
                titleVisibility: .visible,
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
            .confirmationDialog(
                "Remove this game?",
                isPresented: .constant(pendingGameRemoval != nil),
                titleVisibility: .visible,
                presenting: pendingGameRemoval
            ) { pending in
                Button("Remove game", role: .destructive) {
                    removeGameNow(pending)
                }
                Button("Cancel", role: .cancel) { pendingGameRemoval = nil }
            } message: { pending in
                Text("This deletes \"\(pending.cardName.name)\" from MuffinEMU to free up space. Your saves and options are kept. To play it again, add the game back.")
            }
            .confirmationDialog(
                "Replace existing file?",
                isPresented: .constant(pendingOverwriteConfirmation != nil),
                titleVisibility: .visible,
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

    /// keys.txt from the same menu as games. .item for the same reason as the game picker: a keys.txt can carry no useful
    /// type, and WiiUKeys.importKeys checks the contents.
    private func beginKeysImport() {
        DocumentImport.present(contentTypes: Self.fileImportTypes) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    let count = try WiiUKeys.importKeys(from: url)
                    dlcUpdateSuccessMessage = "Added \(count) key\(count == 1 ? "" : "s"). Games use them the next time you start one. If you've already started a game since opening MuffinEMU, close and reopen MuffinEMU first."
                } catch {
                    dlcImportErrorMessage = error.localizedDescription
                }
            case .failure(let error):
                dlcImportErrorMessage = error.localizedDescription
            }
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
            ZStack {
                MuffinTheme.backgroundGradient.ignoresSafeArea()
                List(games) { game in
                    Button {
                        onPick(game)
                        dismiss()
                    } label: {
                        Text(game.title)
                            .foregroundColor(MuffinTheme.brownDarkest)
                    }
                }
            }
            .navigationTitle("Add \(kind.displayName) to which game?")
            .muffinOpaqueNavigationBar(MuffinTheme.formGround)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
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

struct GameCardOptimized<Options: View>: View {
    let game: GameMetadata
    let onTap: () -> Void
    let onFavoriteTap: () -> Void
    /// What the card's own Play button does. Nil means the same as a tap on the card.
    var onPlay: (() -> Void)?
    /// The per-game menu behind the "..." button (the same one a long-press opens).
    let options: Options

    init(game: GameMetadata, onTap: @escaping () -> Void, onFavoriteTap: @escaping () -> Void,
         onPlay: (() -> Void)? = nil, @ViewBuilder options: () -> Options) {
        self.game = game
        self.onTap = onTap
        self.onFavoriteTap = onFavoriteTap
        self.onPlay = onPlay
        self.options = options()
    }

    private var cardName: (name: String, titleIdText: String?) { game.cardName }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(MuffinTheme.muffinTopGradient)

                if let coverPath = game.coverPath {
                    // scaledToFit, not scaledToFill. A game's own icon is SQUARE and
                    // this well is 3:4, so filling it would crop the top and bottom
                    // quarter off every icon - which on a Wii U icon is usually the
                    // title text. Fitting leaves the muffin gradient showing around it
                    // instead, and box art that is already 3:4 fits exactly either way.
                    CoverImage(path: coverPath, padding: 10)
                        .cornerRadius(16)
                } else {
                    VStack {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 28))
                            .foregroundColor(MuffinTheme.onMuffinTop)
                    }
                }

                VStack {
                    HStack {
                        // Everything long-press offers, where it can be found without knowing to long-press.
                        Menu {
                            options
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(MuffinTheme.sparkleCream)
                                .frame(width: 32, height: 32)
                                .background(Color.black.opacity(0.4))
                                .cornerRadius(10)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("More options for \(cardName.name)")
                        .padding(8)
                        Spacer()
                        Button(action: onFavoriteTap) {
                            Image(systemName: game.isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(game.isFavorite ? MuffinTheme.alertOnDark : MuffinTheme.sparkleCream)
                                .frame(width: 32, height: 32)
                                // Black, not brownDarkest: brownDarkest turns cream in dark
                                // mode, which put a cream heart on a cream patch.
                                .background(Color.black.opacity(0.4))
                                .cornerRadius(10)
                                // The visible circle stays 32x32 - the tappable area
                                // around it grows to the standard 44x44 minimum without
                                // changing how the button looks.
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(game.isFavorite ? "Remove from favourites" : "Add to favourites")
                        .padding(8)
                    }
                    Spacer()
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)

            VStack(alignment: .leading, spacing: 8) {
                Text(cardName.name)
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
                if let label = game.installLabel { LibraryInstallLine(text: label, size: 11) }

                Button(action: onPlay ?? onTap) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Play")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(MuffinPrimaryButtonStyle())

                // The title ID, when the game's name had it in it (kept out of the name above).
                if let titleIdText = cardName.titleIdText {
                    Text(titleIdText)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(MuffinTheme.brownMid)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
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
        // The whole card starts the game, not only the Play button. The heart, the "..." button and Play keep
        // their own taps (a child's gesture wins over this one), and VoiceOver still finds Play as a button.
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onTap)
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
    enum Kind: Equatable {
        case emptyLibrary
        case noFavourites
        case noSearchMatch(String)
    }

    let kind: Kind
    let onImportTapped: () -> Void

    private var symbol: String {
        switch kind {
        case .emptyLibrary: return "doc.questionmark"
        case .noFavourites: return "heart"
        case .noSearchMatch: return "magnifyingglass"
        }
    }

    private var heading: String {
        switch kind {
        case .emptyLibrary: return "No Games Yet"
        case .noFavourites: return "No Favourites Yet"
        case .noSearchMatch: return "No Matches"
        }
    }

    private var lines: [String] {
        switch kind {
        case .emptyLibrary:
            return ["Tap Import a Game, or put game files in Files > On My iPad > MuffinEMU > Roms.",
                    "Games you add there show up when you come back to MuffinEMU."]
        case .noFavourites:
            return ["Tap the heart on a game to add it here."]
        case .noSearchMatch(let text):
            return ["Nothing matches \"\(text)\"."]
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 56, weight: .regular))
                .foregroundColor(MuffinTheme.muffinTopDark.opacity(0.5))
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(heading)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(MuffinTheme.brownDarkest)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .center, spacing: 4) {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(MuffinTheme.brownMid)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
            }

            // Same import flow as the toolbar's menu (GameBrowserView.beginImport) -
            // an empty library used to have no way to start an import except that
            // small menu button up top, which is easy to miss on a screen whose whole
            // point is "there's nothing here yet."
            if kind == .emptyLibrary {
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
    // Observed so flipping Classic UI or Disable Liquid Glass repaints this subtree
    // immediately. MuffinTheme and the shared row/header components read the same store
    // through UIStyle's static accessors, but static reads cannot invalidate a view on
    // their own - something in the tree has to be watching, and this is it.
    @ObservedObject private var uiStyle = UIStyleStore.shared

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
    // The launch intro is several seconds of animation; someone who asked the system to reduce motion gets the
    // plain boot screen instead.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // MeloCafe's EmulationView reads this to pick its phone-portrait-only stacked
    // layout (screensSizeLayout) apart from the ordinary tablet/landscape composition -
    // see screenLayoutComposition below, which is the direct port of that view's body.
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showSkinSelector = false
    /// Turns the pad into something you position rather than something you press. Local
    /// state, not AppStorage: nobody wants to come back to a game and find the controls
    /// still in edit mode because that is how they last left them.
    @State private var isEditingControlLayout = false
    /// Local, not AppStorage - the same reasoning as isEditingControlLayout above:
    /// nobody wants to come back to a game and find the pad missing because that was
    /// how they last left it. For touching the GamePad screen's own touchscreen
    /// unobstructed, where the physical control overlay would otherwise sit on top of
    /// it and eat every touch before it reaches PadMetalViewIOS underneath.
    @State private var padControlsHidden = false
    @State private var isPaused = false
    /// The HOME menu is up (see HomeMenu.swift). The game is paused for as long as it is, through
    /// the same togglePause() as the top bar's button.
    @State private var showHomeMenu = false
    /// padControlsHidden was set by a connected controller (Settings > On-screen Controls), not by
    /// the top bar's hide button. Only a controller disconnecting takes the pad back from it, and
    /// it survives the GamePad screen going off screen, which would otherwise un-hide the pad.
    @State private var padHiddenByController = false
    /// True only when isPaused was set by leaving the foreground, not by the pause
    /// button below. Read on the way back to .active: the app should resume a title
    /// it paused on the way out, but must not resume one the person playing paused
    /// on purpose right before backgrounding it. Both look identical in isPaused
    /// alone, which is exactly why this needs its own bit.
    @State private var pausedByLifecycle = false
    /// cemu_bridge_pause()/resume() suspend or resume every active guest thread under
    /// the core's own scheduler lock (IOSTitlePause.cpp) - a lock plenty of other guest
    /// activity (message queues, alarms, spinlocks) also takes briefly, and calling this
    /// straight from a SwiftUI button's action, or from .onChange(of: scenePhase), runs
    /// it ON THE MAIN THREAD. If a guest thread happens to be holding that lock while
    /// itself waiting on something that only finishes once the main run loop is free -
    /// a Metal command buffer's completion handler, which is commonly dispatched back to
    /// the main queue, is exactly this shape - the main thread blocks waiting on the
    /// guest thread, the guest thread is waiting on the main thread, and neither ever
    /// moves again: not a slow pause, the whole app stops responding to anything, pause
    /// button included, until it is force-quit. Routing the actual bridge call through
    /// this serial queue instead keeps the main thread free to keep pumping the run loop
    /// (and therefore keep servicing that completion handler) while the suspend/resume
    /// runs - a serial queue, not a concurrent one, so a resume dispatched right behind a
    /// pause can never run first and unpause a title the pause never reached.
    private static let titlePauseQueue = DispatchQueue(label: "muffin.title.pause", qos: .userInitiated)
    /// Off by default - see the branch on this flag a few lines below for exactly what
    /// it swaps in and why the shipping path is otherwise untouched.
    @AppStorage(PreviewPadStore.enabledKey) private var previewPadEnabled = PreviewPadStore.defaultEnabled
    @AppStorage(MeloControlsSetting.storageKey) private var useMeloControls = MeloControlsSetting.defaultValue
    /// Read only to size the portrait pad's area (belowPicture). Same key and default as the pad's.
    @AppStorage(ControllerLayoutSettings.joystickKey) private var joystickMode = ControllerLayoutSettings.defaultJoystick
    /// The optional TouchLab control style ("" = MuffinEMU's own pad). See TouchLabPads.swift.
    @AppStorage(TouchLabSettings.schemeKey) private var touchLabScheme = TouchLabSettings.defaultScheme
    /// Where the TV / GamePad views are on screen, reported by the screen views themselves.
    /// Written only when the screen layout changes - never from the input path.
    @State private var touchLabScreens = TouchLabScreenState()
    /// Bottom edge of the top bar, so TouchLab's controls stay clear of Back / pause.
    @State private var topBarHeight: CGFloat = 0
    /// Settings > On-screen Controls > "Hide the top bar while playing". 0 follows the
    /// device default (on); see TopBarAutoHide.
    @AppStorage(TopBarAutoHide.overrideKey) private var topBarAutoHideOverride = TopBarAutoHide.followDevice
    /// The bar is faded out and slid away. `topBarHeight` deliberately keeps its last
    /// measured value while this is true, so the pads, which reserve that band, never move.
    @State private var topBarHidden = false
    /// True while a finger is on the bar. A GestureState, so it also resets if the touch is
    /// cancelled (a scroll takeover, an app switch) and can never leave the bar pinned.
    @GestureState private var topBarTouched = false
    @State private var voiceOverRunning = UIAccessibility.isVoiceOverRunning
    @ObservedObject private var previewPad = PreviewPadStore.shared
    /// Same key Settings > External Display reads. Declared here too, rather than read
    /// once at boot, so turning it off takes effect on the button already on screen
    /// instead of only on the next launch.
    @AppStorage(DisplayLayoutSettings.showSwapButtonKey)
    private var showSwapButton = DisplayLayoutSettings.defaultShowSwapButton
    @ObservedObject private var displayRouter = DisplayRouter.shared

    /// MeloCafe's Screen Layout feature - see DisplayRouter.ScreenLayout's own doc
    /// comment for what each case does and why it's a separate concept from
    /// DisplayLayoutSettings above (a genuine external display) despite living in the
    /// same Settings section.
    // `= ScreenLayout.initialValue`, matching MeloCafe's own EmulationView exactly -
    // see DisplaySettingsSection.swift's identical declaration and ScreenLayout.initialValue's
    // doc comment in DisplayRouter.swift.
    @AppStorage(LocalScreenLayoutSettings.layoutKey)
    private var screenLayout = ScreenLayout.initialValue
    @AppStorage(LocalScreenLayoutSettings.showSwapButtonKey)
    private var showLocalSwapButton = LocalScreenLayoutSettings.defaultShowSwapButton
    /// View-local, matching MeloCafe's own `@State` for this exact flag: which of the
    /// two screens Single Screen mode currently shows resets to TV each fresh launch
    /// rather than being remembered, the same way MeloCafe never persisted it either.
    @State private var localSwapped = false
    // Defaults ON, and must keep matching SettingsView's declaration of the same key -
    // two @AppStorage defaults for one key that disagree means the toggle and the
    // emulator disagree about what is on. See SettingsView for why this flipped.
    @AppStorage(LaunchLogSettings.showKey) private var showLaunchLog = false
    // @State, not @StateObject, and the distinction is the whole point. @StateObject
    // subscribes this view to the store's objectWillChange - and the store publishes on
    // a 0.1s timer for as long as a title is running, so the ENTIRE emulator view, the
    // Metal view and the on-screen pad included, was re-rendering ten times a second
    // just to keep a log nobody may even have open up to date.
    //
    // LaunchLogView already declares `@ObservedObject var store`, so it re-renders on
    // its own and loses nothing. This view only needs to own the object's lifetime and
    // start and stop it, which @State does without subscribing.
    @State private var launchLog = LaunchLogStore()
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

    // MARK: Video stall
    //
    // The bridge's watchdog raises `gameManager.videoStalled` when the picture has stopped
    // but the game is still running. "Keep waiting" hides the card until the stall clears.
    @State private var stallCardDismissed = false
    @State private var stallSaveRequested = false

    // MARK: Save states
    //
    // cemu_bridge_save_state()/cemu_bridge_load_state() (CemuBridge.h) are synchronous
    // and can take up to several seconds - they wait for every CPU core and the GPU
    // command queue to actually go idle before touching guest memory (see
    // IOSSaveState.cpp). Routed through their own serial queue rather than
    // titlePauseQueue above: the two never need to interleave with a pause/resume, and
    // keeping them separate means a save/load in flight can't get stuck behind an
    // unrelated pause call queued just ahead of it.
    private static let saveStateQueue = DispatchQueue(label: "muffin.savestate", qos: .userInitiated)
    @State private var showSaveStates = false
    @State private var saveStateSlots: [SaveStateSlot] = []
    /// Non-nil while a save or load for that slot number is in flight. Nothing else
    /// enqueues onto saveStateQueue while this is set - see the sheet's own busySlot
    /// handling in SaveStateView.swift for why every row disables, not just this one.
    @State private var saveStateBusySlot: Int?
    /// The result of the most recent save/load/delete, shown inside the sheet. This is
    /// the only place a refused load's real reason ("doesn't match this session") is
    /// ever surfaced - without it, a refusal and a tap that did nothing look identical.
    @State private var saveStateStatus: SaveStateStatus?

    // MARK: Microphone
    //
    // With "Use <device> Microphone" on (Settings > Audio) the game hears the real mic, and the
    // Blow button - which fakes a puff into it - has nothing to do, so it is hidden. A denied
    // permission means the real mic can't work, so the button stays.
    @AppStorage(AudioSettings.microphoneEnabledKey) private var realMicEnabled = AudioSettings.defaultMicrophoneEnabled
    private var realMicInUse: Bool { realMicEnabled && MicrophoneAccess.status != .denied }

    // MARK: Emulated devices
    //
    // Skylanders Portal / Disney Infinity Base / LEGO Dimensions Toypad. Read-only here -
    // the switches themselves live in Settings (EmulatedDevicesSettingsSection.swift) -
    // just to decide whether the button below is worth showing at all. Figure management
    // doesn't need a running title (it acts on the core's always-live emulated-device
    // state directly), so unlike Save States this button isn't gated on
    // gameManager.emulationState.
    @AppStorage(EmulatedDevicesSettings.skylanderPortalKey) private var skylanderPortalEnabled = EmulatedDevicesSettings.defaultEnabled
    @AppStorage(EmulatedDevicesSettings.infinityBaseKey) private var infinityBaseEnabled = EmulatedDevicesSettings.defaultEnabled
    @AppStorage(EmulatedDevicesSettings.dimensionsToypadKey) private var dimensionsToypadEnabled = EmulatedDevicesSettings.defaultEnabled
    @State private var showEmulatedDevices = false
    @State private var showAmiibo = false
    private var anyEmulatedDeviceEnabled: Bool {
        skylanderPortalEnabled || infinityBaseEnabled || dimensionsToypadEnabled
    }

    /// What the pad button switches back to when Melo-Controller is on.
    private var otherPadName: String {
        TouchLabSettings.isTouchLab(touchLabScheme) ? "the \(TouchLabSettings.name(touchLabScheme)) controls" : "MuffinEMU's controls"
    }

    /// Which control system is live. One decision, made once.
    ///
    /// This replaces two independent conditions - `previewPadEnabled && !useMeloControls`
    /// for the video/pad composition, and `!previewPadEnabled` for the shipping pad - that
    /// had to agree for exactly one pad to be on screen. They could disagree, and the way
    /// they disagreed was silent: with the preview flag on, the shipping pad's branch was
    /// unreachable, so MuffinEMU's own controls were not mounted at all while
    /// Melo-Controller's branch (which never consulted the preview flag) carried on
    /// working. Controls appear, nothing happens, nothing says why.
    ///
    /// As one enum that state cannot be constructed: there is a single answer, every call
    /// site switches on it, and "preview is off" means the preview system is absent from
    /// the view tree entirely rather than merely not selected.
    private enum PadSystem {
        case melo
        case touchLab
        case preview
        case muffin
    }

    private var padSystem: PadSystem {
        // Melo-Controller wins outright when chosen - it replaces both of MuffinEMU's own
        // pads, exactly as it did before this enum existed.
        if useMeloControls { return .melo }
        // A TouchLab style is an explicit choice, so it beats the experimental preview pad.
        // An empty or unknown stored id is not a TouchLab style and falls through, so a bad
        // value can never leave the player without a pad.
        if TouchLabSettings.isTouchLab(touchLabScheme) { return .touchLab }
        // Off by default, but it works now, and the reason it did not is worth recording
        // because this comment used to give the wrong one.
        //
        // It said the preview pad emitted control ids cemuBridgeButton(forLabel:) did not
        // know, which were dropped as NONE. That is not what was happening: its d-pad
        // emits "up"/"down"/"left"/"right" through PreviewDpadView and its face buttons
        // emit "A"/"B"/"X"/"Y" - all sixteen of the labels the bridge accepts. Only HOME,
        // POWER and TV fell through, and none of those are why a d-pad does nothing.
        //
        // The actual cause was at its mount site: the onInput closure bumped two @State
        // properties of the emulator view on every input, and the preview pad renders
        // INSIDE that view - so every press rebuilt the pad being pressed and released it
        // before it could mean anything. The counters existed to prove whether SwiftUI
        // ever called onInput, and were themselves the reason it looked like it did not.
        if previewPadEnabled { return .preview }
        return .muffin
    }

    /// An iPhone held upright. Same test as screenLayoutComposition's, which this has to agree
    /// with: the picture is stacked along the top exactly when this is true. On iPhone the
    /// vertical size class is regular only in portrait.
    private var isPhonePortrait: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && verticalSizeClass == .regular
    }

    /// Lays a pad out over the whole screen, or - held upright on an iPhone - over just the
    /// area under the picture, so no control sits on it. The area runs from the bottom of the
    /// stacked screens (screensSizeLayout) to the bottom of the safe area, and is never shorter
    /// than the pad needs: with both screens stacked on a small phone, after the GamePad screen
    /// has shrunk as far as it will (portraitScreenHeight), the pad is allowed to cover the
    /// bottom of it rather than shrink to nothing (the "hide controls" button in the top bar
    /// uncovers it). Laid out with a frame, not an offset or a position, so what
    /// is drawn is also what takes touches.
    @ViewBuilder private func belowPicture<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let built = content()
        if isPhonePortrait {
            GeometryReader { geometry in
                let pictures = visibleScreens.reduce(CGFloat(0)) { $0 + portraitScreenHeight(main: $1, in: geometry.size) }
                let needed = ControllerGeometry.Portrait.minimumHeight(joystick: joystickMode)
                let height = min(geometry.size.height, max(geometry.size.height - pictures, needed))
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    built
                        .frame(height: height)
                }
            }
        } else {
            built
        }
    }

    /// True while a title is booting, running or paused and the TV screen is on this device.
    private var nativeOverlayActive: Bool {
        switch gameManager.emulationState {
        case .loading, .running, .paused: return displayRouter.placement != .dualScreen
        case .idle, .error: return false
        }
    }

    /// The name the library card shows. `title` is the dump's file name, which can be a bare
    /// product code, and it used to leak into the top bar and the quit prompt.
    private var gameName: String { game.displayTitle ?? game.title }

    /// Pauses or resumes the title and keeps the screen's idea of "paused" in step with it.
    /// Also lets go of every held button and stick: touches made while paused (the Melo pad
    /// stays live) would otherwise arrive at the game the instant it resumes.
    private func togglePause() {
        isPaused.toggle()
        pausedByLifecycle = false
        cemu_bridge_release_all_buttons()
        setTitlePaused(isPaused)
    }

    /// Sends the pause or resume to the bridge off the main thread. While a save state or
    /// a load is running it goes onto that operation's own queue instead: the operation
    /// pauses and resumes the title itself, so a resume sent from here would let the game
    /// run in the middle of the memory dump (a corrupt save), and a pause would be undone
    /// when the operation finishes and resumes (the game running in the background).
    /// Queued behind it, either lands afterwards, in the right order.
    private func setTitlePaused(_ pause: Bool) {
        let queue = saveStateBusySlot == nil ? Self.titlePauseQueue : Self.saveStateQueue
        queue.async {
            if pause {
                cemu_bridge_pause()
            } else {
                cemu_bridge_resume()
            }
        }
    }

    /// The move-controls panel for whichever pad is live (see LayoutPanels.swift).
    @ViewBuilder private var layoutPanel: some View {
        let gameID = gameManager.currentGame?.settingsKey
        switch padSystem {
        case .melo:
            MeloLayoutPanel(gameID: gameID, onDone: finishEditingLayout)
        case .touchLab:
            TouchLabLayoutPanel(gameID: gameID, onDone: finishEditingLayout)
        case .preview:
            PreviewLayoutPanel(onDone: finishEditingLayout)
        case .muffin:
            MuffinPadLayoutPanel(onDone: finishEditingLayout)
        }
    }

    private func finishEditingLayout() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditingControlLayout = false
        }
    }

    // MARK: Controller auto-hide

    /// Hides or shows the on-screen pad because a controller came or went (the setting is checked
    /// by ControllerAutoHideModifier). Reuses padControlsHidden, so only the pad overlay goes: the
    /// GamePad's picture and its touchscreen are not part of it. Says so with the usual notice
    /// banner, but only when something actually changed, and not over another notice at launch.
    private func setPadHiddenByController(_ hide: Bool, atStart: Bool) {
        if hide {
            guard !padHiddenByController else { return }
            padHiddenByController = true
            if !padControlsHidden {
                padControlsHidden = true
                // A button the pad stops drawing cannot report its own release.
                cemu_bridge_release_all_buttons()
            }
        } else {
            guard padHiddenByController else { return }
            padHiddenByController = false
            padControlsHidden = false
        }
        if atStart && gameManager.launchNotice != nil { return }
        gameManager.showLaunchNotice(hide
            ? "Controller connected. On-screen controls hidden. Press HOME for the menu."
            : "Controller disconnected. On-screen controls shown.")
    }

    // MARK: HOME menu

    /// Opens the slot sheet. Shared by the top bar's button and the HOME menu.
    private func openSaveStates() {
        saveStateSlots = SaveStateStore.slots(for: game.id)
        saveStateStatus = nil
        showSaveStates = true
    }

    /// Pauses the game and opens the HOME menu. Ignored while the title is not running (there is
    /// nothing to pause while it boots, and a pause sent then is dropped) and while the pad is
    /// being moved.
    private func openHomeMenu() {
        guard gameManager.emulationState == .running, !showHomeMenu, !isEditingControlLayout else { return }
        if isPaused {
            // Already paused by the pause button or by leaving the foreground. The menu keeps it
            // paused, and a lifecycle pause must not be undone by the app coming back to the front.
            pausedByLifecycle = false
            cemu_bridge_release_all_buttons()
        } else {
            // The one pause path: togglePause() queues behind a save that is running.
            togglePause()
        }
        withAnimation(.easeInOut(duration: 0.15)) { showHomeMenu = true }
    }

    /// Closes the menu and lets the game run again.
    private func closeHomeMenu() {
        withAnimation(.easeInOut(duration: 0.15)) { showHomeMenu = false }
        if isPaused { togglePause() }
    }

    /// Edit mode is only useful with the game running under the pad, so the menu closes first.
    private func moveControlsFromHomeMenu() {
        closeHomeMenu()
        padControlsHidden = false
        padHiddenByController = false
        withAnimation(.easeInOut(duration: 0.2)) { isEditingControlLayout = true }
        cemu_bridge_release_all_buttons()
    }

    private func swapScreensFromHomeMenu() {
        if displayRouter.placement == .dualScreen {
            DisplayRouter.shared.toggleScreenLayoutFromSwapButton()
        } else {
            localSwapped.toggle()
        }
    }

    /// HOME toggles the menu; B (a controller) backs out of the save-state sheet. Up, down, A and
    /// B inside the menu itself are handled by HomeMenuOverlay. While the controls are being moved,
    /// HOME and B both finish that (a controller has no way to tap Done).
    private func handleHomeMenuEvent(_ event: HomeMenuEvent) {
        if isEditingControlLayout {
            if event == .homeButton || event == .back { finishEditingLayout() }
            return
        }
        switch event {
        case .homeButton:
            if showSaveStates {
                showSaveStates = false
            } else if showEmulatedDevices {
                showEmulatedDevices = false
            } else if showAmiibo {
                showAmiibo = false
            } else if showHomeMenu {
                if !showingBackConfirmation { closeHomeMenu() }
            } else {
                openHomeMenu()
            }
        case .back:
            if showSaveStates { showSaveStates = false }
        case .up, .down, .confirm:
            break
        }
    }

    @ViewBuilder private var homeMenuLayer: some View {
        HomeMenuOverlay(
            gameName: gameName,
            isActive: !showSaveStates && !showingBackConfirmation && !showEmulatedDevices && !showAmiibo,
            screenLayout: $screenLayout,
            isDualScreen: displayRouter.placement == .dualScreen,
            canQuit: saveStateBusySlot == nil,
            actions: HomeMenuActions(
                resume: closeHomeMenu,
                saveStates: openSaveStates,
                moveControls: moveControlsFromHomeMenu,
                // Already confirmed, on the menu's own "Quit game?" page.
                quit: {
                    gameManager.stopEmulation()
                    isRunning = true
                },
                swapScreens: swapScreensFromHomeMenu,
                toggleRecording: { AudioRecorder.shared.toggle(gameName: gameName) },
                scanAmiibo: { showAmiibo = true }
            )
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // The video, as its own base layer beneath everything else in this ZStack -
            // not a member of the VStack of UI chrome below, which used to hold it as its
            // last child. A VStack allocates space top-to-bottom among its own children,
            // so the video was only ever getting "whatever height is left after the top
            // bar", not the full screen .ignoresSafeArea() on a couple of these individual
            // views implied it should have; the top bar is what belongs in a VStack (it
            // has a natural height to lay out), the video does not (it wants the whole
            // screen, with the bar floating over it, not carving into it).
            if padSystem == .preview {
                // Video and pad have to agree on the exact same rect for Native mode
                // to mean anything - a mismatch between two independent resolves
                // would put the picture in one place and the "never overlaps it"
                // guarantee somewhere else. So both are siblings inside ONE
                // GeometryReader here, sharing one PreviewResolved.
                GeometryReader { proxy in
                    let insets = proxy.safeAreaInsets
                    let full = proxy.frame(in: .local)
                    let safeArea = CGRect(x: full.minX + insets.leading, y: full.minY + insets.top,
                                          width: full.width - insets.leading - insets.trailing,
                                          height: full.height - insets.top - insets.bottom)
                    let resolved = previewPad.resolve(container: proxy.size, safeArea: safeArea,
                                                      pointsPerInch: DeviceMetrics.current().pointsPerInch)
                    // Upright on an iPhone that is always Native (see effectiveDisplayMode).
                    let native = previewPad.effectiveDisplayMode(container: proxy.size) == .native
                    ZStack(alignment: .topLeading) {
                        MetalViewIOS(gameManager: gameManager)
                    }
                    .frame(width: native ? resolved.video.width : proxy.size.width,
                          height: native ? resolved.video.height : proxy.size.height)
                    .position(x: native ? resolved.video.midX : proxy.size.width / 2,
                             y: native ? resolved.video.midY : proxy.size.height / 2)
                    .clipped()

                    // Hidden with the rest of the on-screen pad (the top bar's hide button, or a connected
                    // controller with Settings > On-screen Controls > Hide on-screen controls on). The video
                    // above stays.
                    if !padControlsHidden {
                        PreviewControllerPad(
                            store: previewPad,
                            // Recorded through PadDiagnostics, NOT into @State here, and that
                            // is the whole reason this pad never worked.
                            //
                            // These closures used to bump two @State properties of this view
                            // on every single input. The preview pad is rendered INSIDE this
                            // view, so every press rebuilt the pad being pressed - which tore
                            // the control out from under the finger and released it again
                            // before the press could mean anything. The same shape as the bug
                            // in MuffinEMU's own pad, except guaranteed on every event rather
                            // than occasional, which is why this one never worked at all
                            // while the other worked intermittently.
                            //
                            // PadDiagnostics is an ObservableObject that only its own overlay
                            // observes, so recording an input invalidates that overlay and
                            // nothing else. It is also where the real pad already reports, so
                            // both pads now show up in the same readout.
                            onInput: { label, pressed in
                                sendPadButton(label, pressed)
                            },
                            onStick: { stick, position in
                                PadDiagnostics.shared.recordStick(stick, position)
                                cemu_bridge_set_stick_axis(
                                    stick == 0 ? CEMU_BRIDGE_STICK_LEFT : CEMU_BRIDGE_STICK_RIGHT,
                                    Float(position.x), Float(position.y)
                                )
                            },
                            isEditingLayout: $isEditingControlLayout
                        )
                        .onAppear { PadDiagnostics.shared.report(activePad: .preview) }
                        // The stuck-button net, at the level where disappearing is a real
                        // event. HeldControl no longer releases per control - see its own
                        // comment for why that had to go - so the pad as a whole owns it,
                        // exactly as OptimizedControlPanel does.
                        .onDisappear { cemu_bridge_release_all_buttons() }
                    }

                    #if DEBUG
                    // Debug HUD: proves whether SwiftUI ever calls onInput/onStick at
                    // all, which is exactly the question a "controls don't do anything"
                    // report can't answer from the outside. Temporary, and gone the
                    // moment the real bug is found - not something to leave shipping.
                    VStack {
                        Text("PAD DEBUG: \(PadDiagnostics.shared.lastInput) / \(PadDiagnostics.shared.lastStick)")
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
                screenLayoutComposition
            }

            // The core's FPS readout and notifications, drawn here at full screen resolution
            // instead of by ImGui inside the (reduced-scale) game surface. Above the video,
            // below the controls; no layout, no touches. In dual-screen the TV is on another
            // display this layer cannot reach, so it hands back to the core's own drawing.
            NativeCoreOverlayView(active: nativeOverlayActive, topInset: overlayTopInset)

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
                    .buttonStyle(MuffinBarButtonStyle())
                    // Quitting while a save state is being written would tear the title down under the write.
                    .disabled(saveStateBusySlot != nil)
                    // An alert, not a confirmationDialog: on iPad a confirmationDialog is a popover anchored
                    // to this button, and from the in-game top bar it could fail to appear, leaving Back
                    // doing nothing. An alert always presents.
                    .alert(
                        "Quit \(gameName)?",
                        isPresented: $showingBackConfirmation
                    ) {
                        Button("Quit", role: .destructive) {
                            gameManager.stopEmulation()
                            isRunning = true
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Any progress the game itself hasn't saved will be lost. Save states can't be loaded after you quit.")
                    }

                    // Upright there is no room for the name beside the buttons.
                    // The skin's name used to sit under this at 9pt, too small to read; the skin picker shows it.
                    if !isPhonePortrait {
                    Text(gameName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                    }

                    TopBarOverflowScroll {
                    // 2 point gaps: each button is a 44 point target around a smaller visible one.
                    HStack(spacing: 2) {
                        Button(action: { showSkinSelector.toggle() }) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(MuffinBarButtonStyle())
                        .accessibilityLabel("Choose Controller Skin")

                        // Settings > On-Screen Controls already has this toggle;
                        // repeated here for the same reason as the save-state and
                        // hide-controls buttons around it: things you need mid-game
                        // should be reachable without leaving the game, not buried
                        // one menu away. Releases every
                        // held button on the way in: a press in flight when the
                        // overlay it was held on disappears cannot report its own
                        // release any more, and the other pad's own buttons don't
                        // know a press exists that they never started.
                        Button(action: {
                            useMeloControls.toggle()
                            cemu_bridge_release_all_buttons()
                        }) {
                            Image(systemName: useMeloControls ? "checkmark.rectangle.stack.fill" : "rectangle.stack")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(MuffinBarButtonStyle())
                        .accessibilityLabel(useMeloControls ? "Switch to \(otherPadName)" : "Switch to Melo-Controller")

                        // Reachable without leaving the game, same reasoning as the
                        // move-controls and pad-hide buttons around it: reachable
                        // in-game rather than buried in Settings. Hidden outright while
                        // .loading/.error instead of merely disabled: there is no
                        // running session yet for a slot to match against.
                        if gameManager.emulationState == .running {
                            Button(action: openSaveStates) {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(MuffinBarButtonStyle())
                            .accessibilityLabel("Save States")
                        }

                        // Simulated blow into the GamePad mic, for the games that ask for
                        // one (Captain Toad, 3D World, NSMBU, Zelda). Only while a title is
                        // running - the mic can't be open before that - and not at all when
                        // the real microphone is in use instead. Turns itself off when the
                        // title stops or changes (see BlowButton).
                        if gameManager.emulationState == .running && !realMicInUse {
                            BlowButton(titleID: "\(game.id)")
                        }

                        // Same "reachable without leaving the game" reasoning as Save
                        // States above. Only shown once a peripheral is actually turned
                        // on in Settings - ported from MeloCafe's own EmulationView.swift
                        // overlay, which gates its equivalent button the same way.
                        if anyEmulatedDeviceEnabled {
                            Button(action: { showEmulatedDevices = true }) {
                                Image(systemName: "externaldrive.connected.to.line.below")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(MuffinBarButtonStyle())
                            .accessibilityLabel("Emulated Devices")
                        }

                        #if os(iOS)
                        // Was a floating circle over the top-left corner of the game;
                        // moved in here with the rest of the in-game buttons instead,
                        // rather than floating alone on
                        // top of whatever the game is drawing underneath it. Same
                        // action, same gating as before: only means anything in Single
                        // Screen, and only while a real external display isn't already
                        // deciding this for a genuine second screen.
                        if showLocalSwapButton, screenLayout == .singleScreen, displayRouter.placement != .dualScreen {
                            Button(action: { localSwapped.toggle() }) {
                                Image(systemName: "rectangle.2.swap")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(MuffinBarButtonStyle())
                            .accessibilityLabel("Swap TV and GamePad")
                        .accessibilityValue(localSwapped ? "Showing the GamePad screen" : "Showing the TV screen")
                        }

                        // Dual screen: which Wii U screen is on the external display. Lives
                        // in the bar with the other in-game buttons. It used to float in the
                        // top-right corner, which is exactly where the bar's last button and
                        // the frame rate are, so it sat on top of them.
                        if showSwapButton, displayRouter.placement == .dualScreen {
                            Button(action: { DisplayRouter.shared.toggleScreenLayoutFromSwapButton() }) {
                                Image(systemName: "rectangle.2.swap")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(MuffinBarButtonStyle())
                            .accessibilityLabel("Swap TV and GamePad screens")
                        }

                        // Only worth showing while the GamePad's own screen is actually
                        // the one on top - hiding the pad to touch a TV that has no
                        // touchscreen of its own would just take the controls away for
                        // nothing. Releases every held button/stick on the way in, the
                        // same as the edit-layout button above it: a button the overlay
                        // stops drawing cannot report its own release any more, and one
                        // still held inside the title when the overlay vanishes would
                        // stay held.
                        if isPadViewVisible {
                            Button(action: {
                                padControlsHidden.toggle()
                                // The player's own choice now, whatever a controller did before.
                                padHiddenByController = false
                                if padControlsHidden {
                                    cemu_bridge_release_all_buttons()
                                }
                            }) {
                                Image(systemName: padControlsHidden ? "hand.raised.slash.fill" : "hand.raised.fill")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(MuffinBarButtonStyle())
                            .accessibilityLabel(padControlsHidden ? "Show controls" : "Hide controls to touch the GamePad screen")
                        }
                        #endif

                        // The HOME menu, for the pads that have no HOME button of their own (MuffinEMU's
                        // measured layout is the GamePad's, and the console's HOME is not on it).
                        Button(action: openHomeMenu) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(MuffinBarButtonStyle())
                        .disabled(gameManager.emulationState != .running || showHomeMenu || isEditingControlLayout)
                        .accessibilityLabel("HOME menu")

                        // cemu_bridge_pause/resume wrap CafeSystem::PauseTitle()/
                        // ResumeTitle() (and, since the app-lifecycle work, also the
                        // Metal GPU thread's own drawable gate - see CemuBridge.mm).
                        // isPaused is local state rather than a query, because there is
                        // no cemu_bridge_is_paused() to ask. Two things change it now:
                        // this button and the .onChange(of: scenePhase) below - so it is
                        // pausedByLifecycle, not isPaused itself, that keeps the two from
                        // fighting over what a return to .active should do.
                        Button(action: togglePause) {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(MuffinBarButtonStyle())
                        // There is nothing to pause until the title is running, and a pause sent
                        // while it boots is dropped, which left the screen saying PAUSED over a game
                        // that was running.
                        .disabled(gameManager.emulationState != .running)
                        .accessibilityLabel(isPaused ? "Resume" : "Pause")

                        // Reachable without leaving the game, because the only way to
                        // tell whether the pad is in the right place is to have the
                        // game under it while you move it.
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditingControlLayout.toggle()
                            }
                            // There is nothing to move while the pad is hidden.
                            if isEditingControlLayout {
                                padControlsHidden = false
                                padHiddenByController = false
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
                        .buttonStyle(MuffinBarButtonStyle())
                        .accessibilityLabel(isEditingControlLayout ? "Done moving controls" : "Move controls")

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
                        .foregroundColor(gameManager.frameRate >= 20 ? Color.green : MuffinTheme.alertOnDark)
                        .frame(height: 40)
                        .padding(.horizontal, 12)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Frame rate")
                        .accessibilityValue(gameManager.progress.hudText(wholeFramesPerSecond: gameManager.frameRate))
                    }
                    }
                }
                // Sideways it keeps clear of an iPhone's notch side and rounded corners; the
                // game view ignores the safe area, so the window is asked directly.
                .padding(WindowSafeArea.padding(minimum: 12))
                .background(Color.black.opacity(0.5))
                .borderBottom(width: 0.5, color: Color.white.opacity(0.1))
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0).updating($topBarTouched) { _, touched, _ in touched = true }
                )
                // Before the measurement, never after it: see TopBarHidingEffect.
                .topBarAutoHideEffect(hidden: topBarHidden, slideDistance: topBarHeight, slides: !reduceMotion)
                .reportTopBarBottom()
                // The bar and the pads are laid out against measured sizes, so they stop growing at Extra Large.
                .dynamicTypeSize(...DynamicTypeSize.xLarge)

                if showSkinSelector {
                    VStack(spacing: 6) {
                        OrganizedControllerSkinSelector(selectedSkin: $controllerSkin)
                        Text(padSystem == .muffin
                             ? "The skin applies to every game."
                             : "Skins colour MuffinEMU's own pad, which isn't the one in use right now.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.white.opacity(0.65))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.7))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            // Pinned to the top rather than left to fill the ZStack the way a VStack's
            // last-and-only-flexible child would: the video is what wants the whole
            // screen now (see the top of this ZStack), and this is only the bar and
            // whatever drops down from it, sized to its own content and nothing more.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onPreferenceChange(TopBarBottomKey.self) { bottom in
                // Not while hidden: the bar's height is what the pads reserve, and it is
                // only worth re-measuring when the bar is actually there.
                if !topBarHidden, bottom != topBarHeight { topBarHeight = bottom }
            }
            .overlay(alignment: .top) { topBarRevealHandle }
            .onChange(of: isPaused) { paused in
                // Pausing always brings the bar back, whatever hid it.
                if paused, topBarHidden { setTopBarHidden(false) }
            }
            .task(id: topBarHideKey) { await runTopBarAutoHide(topBarHideKey) }
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
                voiceOverRunning = UIAccessibility.isVoiceOverRunning
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
            if !padControlsHidden {
                Group {
                if useMeloControls {
                    // Upright, Melo-Controller gets only the area under the picture; it lays its
                    // buttons out itself, so that is all that can be done for it.
                    belowPicture {
                        MeloControlsOverlay(
                            gameID: gameManager.currentGame?.settingsKey,
                            isEditing: isEditingControlLayout
                        )
                        .onAppear { PadDiagnostics.shared.report(activePad: .melo) }
                    }
                } else if padSystem == .touchLab {
                    TouchLabPadOverlay(
                        schemeID: touchLabScheme,
                        gameID: gameManager.currentGame?.settingsKey,
                        screens: touchLabScreens,
                        enabled: !isPaused && !isEditingControlLayout,
                        // Upright the picture is along the top and the controls go under it.
                        topInset: isPhonePortrait ? 0 : topBarHeight
                    )
                    .onAppear { PadDiagnostics.shared.report(activePad: .touchLab) }
                } else if padSystem == .muffin {
                    belowPicture {
                    OptimizedControlPanel(
                        skin: controllerSkin,
                        onInput: { label, pressed in
                            // Recorded on the path that already runs for every press, so
                            // the overlay can tell "no touch reached the pad" apart from
                            // "the pad fired and the bridge did nothing" - two completely
                            // different bugs that were indistinguishable all day.
                            sendPadButton(label, pressed)
                        },
                        // The axis path. Deliberately not routed through the button call above:
                        // the bridge keeps sticks and buttons apart because the engine does, and
                        // a stick sent as a press reaches VPADRead's button loop, which skips
                        // the stick mappings outright.
                        onStick: { stick, position in
                            PadDiagnostics.shared.recordStick(stick, position)
                            cemu_bridge_set_stick_axis(
                                stick == 0 ? CEMU_BRIDGE_STICK_LEFT : CEMU_BRIDGE_STICK_RIGHT,
                                Float(position.x),
                                Float(position.y)
                            )
                        },
                        isEditingLayout: $isEditingControlLayout,
                        isPaused: isPaused,
                        // Upright, the pad starts under the picture, clear of the bar.
                        topInset: isPhonePortrait ? 0 : topBarHeight,
                        portrait: isPhonePortrait
                    )
                    .onAppear { PadDiagnostics.shared.report(activePad: .muffin) }
                    }
                }
                }
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
            }

            // Last thing added to this ZStack, so it draws over every control and over the
            // video - a diagnostic that can be covered by the thing it is diagnosing is
            // useless. It cannot swallow a touch: the whole overlay is
            // .allowsHitTesting(false).
            if PadDiagnostics.shared.isEnabled {
                VStack {
                    HStack {
                        PadDiagnosticsOverlay(
                            padControlsHidden: padControlsHidden,
                            useMeloControls: useMeloControls,
                            previewPadEnabled: previewPadEnabled,
                            touchLabScheme: touchLabScheme,
                            isEditingLayout: isEditingControlLayout,
                            isPaused: isPaused
                        )
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            // Above the pad (which stays on screen and interactive-looking underneath
            // it) so there is no ambiguity about whether input is actually reaching a
            // paused title - the label is the whole point, not just the pause itself.
            if isPaused && !showHomeMenu {
                VStack(spacing: 10) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 40))
                        .accessibilityHidden(true)
                    Text("PAUSED")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .tracking(2)
                    Text("Tap to resume")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .opacity(0.85)
                }
                .foregroundColor(.white)
                .padding(28)
                .background(Color.black.opacity(0.6))
                .cornerRadius(20)
                .transition(.opacity)
                // Tappable, so a paused game can always be resumed even when the top bar is out of reach.
                .contentShape(RoundedRectangle(cornerRadius: 20))
                .onTapGesture { togglePause() }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Paused. Resume")
            }

            // The Metal view above must mount (so it can register the render
            // surface) before boot() actually runs, so this state genuinely
            // overlaps with an on-screen MetalViewIOS for the first time now -
            // cover it with a status overlay until emulationState flips to .running.
            if gameManager.emulationState == .loading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Starting \(game.title)…")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

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
            // It clears itself when finished, and can be skipped by tap or controller. It
            // does NOT gate .running: the engine flips that on its own schedule and the
            // intro fading out reveals whatever state the emulator has genuinely reached.
            // The one link the other way is that a running game ends the intro early, once
            // it has played about two seconds, so a fast boot isn't held behind it.
            //
            // Hidden while the launch log is up. Someone who has turned that on is
            // diagnosing a boot, and covering the log with an animation would be
            // exactly the wrong call.
            if launchIntroVisible {
                LaunchIntroView(isGameRunning: gameManager.emulationState == .running) { showLaunchIntro = false }
                    .transition(.opacity)
                    .zIndex(10)
            }

            // The cover and the intro hide the top bar, so a launch that never finishes needs its own way out.
            if gameManager.emulationState == .loading {
                BootBackButton {
                    gameManager.stopEmulation()
                    isRunning = true
                }
                .zIndex(11)
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
                        // Stop draining as well as hiding. A dismissed log still polled
                        // the engine every 0.1s and appended to an array nothing was
                        // showing, for the rest of the session.
                        launchLog.stop()
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
            // makes twice. Everything in these panels writes to the same stored values the
            // pad reads, so the change is under the finger as the slider moves.
            if isEditingControlLayout {
                layoutPanel
            }

            // Above everything, the launch intro included.
            if showHomeMenu {
                homeMenuLayer
                    .zIndex(20)
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
        .onAppear {
            if showLaunchLog { launchLog.start() }
            // An iPhone may turn upright for as long as a game is on screen.
            OrientationPolicy.setInGame(true)
        }
        .onDisappear {
            launchLog.stop()
            AudioRecorder.shared.stop()
            OrientationPolicy.setInGame(false)
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
                if gameManager.emulationState == .running { AudioRecorder.shared.autoStartIfEnabled(gameName: gameName) }
                guard pausedByLifecycle else { return }
                pausedByLifecycle = false
                isPaused = false
                setTitlePaused(false)
            } else {
                // A recording ends when the app leaves the foreground, finished properly.
                AudioRecorder.shared.stop()
                // Released on every trip out of .active, paused or not. A touch in
                // progress when the app resigns active is cancelled by UIKit, which does
                // not reliably deliver the gesture's end, so without this a held button or
                // deflected stick would still be held when the game comes back. Not
                // routed through titlePauseQueue: it only touches the input mutex, not
                // the guest scheduler lock cemu_bridge_pause/resume take, so it carries
                // none of the main-thread deadlock risk that sends those two there.
                cemu_bridge_release_all_buttons()
                // The GamePad's touchscreen is the same: a cancelled touch never reports its end.
                cemu_bridge_set_pad_touch(0, 0, false)
                guard !isPaused else { return }
                isPaused = true
                pausedByLifecycle = true
                setTitlePaused(true)
            }
        }
        // A title that finishes booting while the app is away (or that was asked to pause
        // before it existed - there is nothing to suspend while it boots) must still end
        // up paused, or it runs on in the background.
        .onChange(of: gameManager.emulationState) { state in
            guard state == .running else { return }
            if scenePhase == .active { AudioRecorder.shared.autoStartIfEnabled(gameName: gameName) }
            // After the launch intro has had its moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showGamePadHintIfNeeded() }
            if scenePhase != .active && !isPaused {
                isPaused = true
                pausedByLifecycle = true
            }
            if isPaused { setTitlePaused(true) }
        }
        // Scoped to actually looking at the GamePad screen, not a standing setting:
        // hiding the controls to touch it and then swapping back to the TV (or to a
        // layout where the pad isn't shown at all) must bring them back on its own,
        // or a player who forgot the button exists would have no way to control the
        // TV-side game at all until they remembered to look for it again.
        .onChange(of: isPadViewVisible) { visible in
            if !visible && !padHiddenByController { padControlsHidden = false }
            if visible { showGamePadHintIfNeeded() }
        }
        // Keeps the home indicator (and the system's own edge-swipe gestures) from
        // popping up mid-game - a stray swipe near the bottom edge no longer competes
        // with on-screen controls sitting right where it appears.
        .hidingSystemOverlaysDuringPlay()
        .modifier(HeatNoticeModifier { gameManager.showLaunchNotice($0) })
        // Red "Recording 0:42" while Record audio (HOME menu) is on.
        .overlay(alignment: .top) {
            RecordingIndicator()
                .padding(.top, overlayTopInset + 8)
        }
        // Also on while the controls are being moved: a controller's B only reaches the app while it is captured.
        .modifier(HomeMenuEventsModifier(isOpen: showHomeMenu || isEditingControlLayout, onEvent: handleHomeMenuEvent))
        .modifier(ControllerAutoHideModifier(apply: setPadHiddenByController))
        .overlay(alignment: .top) {
            if showsStallCard {
                videoStalledCard
                    // Below the top bar, not on top of Back and the button row.
                    .padding(.top, overlayTopInset + 8)
                    .padding(.horizontal, 16)
                    .transition(.opacity)
            }
        }
        .onChange(of: gameManager.videoStalled) { stalled in
            // Saving pauses the game, which also clears the flag; keep the card up until the save is done.
            if !stalled && saveStateBusySlot == nil {
                stallCardDismissed = false
            }
        }
        .onChange(of: gameManager.videoStallKind) { kind in
            // A new or worse problem is shown even if an earlier card was dismissed.
            if kind != 0 { stallCardDismissed = false }
        }
        .onChange(of: saveStateBusySlot) { slot in
            // After a save from the card, leave the result up for a few seconds, then let it go
            // if the picture is fine again.
            guard slot == nil, stallSaveRequested, !gameManager.videoStalled else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                if saveStateBusySlot == nil && !gameManager.videoStalled { stallSaveRequested = false }
            }
        }
        .sheet(isPresented: $showSaveStates) {
            SaveStateSheet(
                gameTitle: gameName,
                slots: saveStateSlots,
                busySlot: saveStateBusySlot,
                status: saveStateStatus,
                onSave: performSaveState,
                onLoad: performLoadState,
                onDelete: deleteSaveState
            )
        }
        .sheet(isPresented: $showEmulatedDevices) {
            EmulatedDevicesView()
        }
        .sheet(isPresented: $showAmiibo) {
            AmiiboSheet { message in
                // The game has to be running for the reader to hand the tag over.
                showAmiibo = false
                closeHomeMenu()
                gameManager.showLaunchNotice(message)
            }
        }
    }

    /// Writes to `slot`, creating this game's SaveStates folder on first use. `path` is
    /// captured as a plain String before hopping to saveStateQueue - URL itself is not
    /// guaranteed Sendable-safe to touch off the main actor the way its `.path` string is.
    private func performSaveState(slot: Int) {
        guard saveStateBusySlot == nil, gameManager.emulationState == .running else { return }
        let gameID = game.id
        SaveStateStore.ensureDirectoryExists(for: gameID)
        let path = SaveStateStore.fileURL(for: gameID, slot: slot).path
        saveStateBusySlot = slot
        Self.saveStateQueue.async {
            let ok = path.withCString { cemu_bridge_save_state($0) }
            // Read here, on the queue that made the call and before anything else can: the text belongs to the latest save or load.
            let reason = ok ? "" : String(cString: cemu_bridge_save_state_last_error())
            DispatchQueue.main.async {
                saveStateBusySlot = nil
                saveStateSlots = SaveStateStore.slots(for: gameID)
                reportSaveState(ok
                    ? SaveStateStatus(message: "Slot \(slot) saved.", isWarning: false)
                    : SaveStateStatus(message: Self.saveStateFailureMessage("save", slot: slot, reason: reason), isWarning: true))
            }
        }
    }

    /// Loads `slot` back into the CURRENTLY running instance only - see
    /// cemu_bridge_load_state's doc comment in CemuBridge.h. A save from another launch
    /// is not offered for loading at all (the sheet shows it as "From an earlier session");
    /// a refusal that still gets here carries the bridge's own reason.
    private func performLoadState(slot: Int) {
        guard saveStateBusySlot == nil, gameManager.emulationState == .running else { return }
        let gameID = game.id
        let path = SaveStateStore.fileURL(for: gameID, slot: slot).path
        guard FileManager.default.fileExists(atPath: path) else { return }
        saveStateBusySlot = slot
        Self.saveStateQueue.async {
            let ok = path.withCString { cemu_bridge_load_state($0) }
            let reason = ok ? "" : String(cString: cemu_bridge_save_state_last_error())
            DispatchQueue.main.async {
                saveStateBusySlot = nil
                saveStateSlots = SaveStateStore.slots(for: gameID)
                reportSaveState(ok
                    ? SaveStateStatus(message: "Slot \(slot) loaded. Some textures may look wrong for a moment.", isWarning: false)
                    : SaveStateStatus(message: Self.saveStateFailureMessage("load", slot: slot, reason: reason), isWarning: true))
            }
        }
    }

    // MARK: Top bar auto-hide

    private var launchIntroVisible: Bool {
        showLaunchIntro && launchIntroEnabled && !showLaunchLog && !reduceMotion
    }

    /// Where the core's FPS readout and notifications, and the picture-stopped card, start.
    /// They are informational and don't touch input, so they take the freed space. The pads
    /// do not use this: they keep reserving the bar's full height (see TopBarAutoHide.swift).
    /// Kept at the bar's height while the bar is hidden as well: the handle that brings it back
    /// sits up there, and the bar slides back over the same strip, so alerts that moved up into
    /// it were covered either way.
    private var overlayTopInset: CGFloat { topBarHeight }

    /// The bar may go away only while nothing needs it and nothing is covering it: the game
    /// is running and not paused, no menu, sheet, dialog or card is up, the layout isn't
    /// being edited, no finger is on the bar, and VoiceOver is off (it can't find a handle
    /// that isn't there to be found).
    private var topBarMayHide: Bool {
        TopBarAutoHide.isOn(override: topBarAutoHideOverride)
            && !voiceOverRunning
            && gameManager.emulationState == .running
            && !launchIntroVisible
            && !isPaused
            && !showHomeMenu
            && !isEditingControlLayout
            && !showSkinSelector
            && !showSaveStates
            && !showEmulatedDevices
            && !showAmiibo
            && !showingBackConfirmation
            && !showsStallCard
            && saveStateBusySlot == nil
            && !topBarTouched
    }

    private struct TopBarHideKey: Equatable {
        var mayHide: Bool
        var hidden: Bool
    }

    private var topBarHideKey: TopBarHideKey {
        TopBarHideKey(mayHide: topBarMayHide, hidden: topBarHidden)
    }

    /// Re-run whenever the key changes, and cancelled when it does, which is what restarts
    /// the four-second wait after a touch, a reveal or a dialog closing.
    private func runTopBarAutoHide(_ key: TopBarHideKey) async {
        guard key.mayHide else {
            if key.hidden { setTopBarHidden(false) }
            return
        }
        guard !key.hidden else { return }
        try? await Task.sleep(nanoseconds: TopBarAutoHide.hideDelayNanoseconds)
        guard !Task.isCancelled else { return }
        setTopBarHidden(true)
        showHintOnce(Self.topBarHintKey, "Tap the top edge to bring the bar back.")
    }

    // MARK: One-time hints

    private static let topBarHintKey = "muffin.hint.topBarReveal"
    private static let gamePadHintKey = "muffin.hint.gamePadTouch"

    /// Says `text` as a notice the first time only (the key is remembered), and not on top of another notice: if one is
    /// up, it tries again a few seconds later, a few times. `ready` is checked again then.
    private func showHintOnce(_ key: String, _ text: String, attempts: Int = 3, ready: @escaping () -> Bool = { true }) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key), ready() else { return }
        if gameManager.launchNotice != nil {
            guard attempts > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                showHintOnce(key, text, attempts: attempts - 1, ready: ready)
            }
            return
        }
        defaults.set(true, forKey: key)
        gameManager.showLaunchNotice(text)
    }

    /// The first time a GamePad screen is on this device during a running game.
    private func showGamePadHintIfNeeded() {
        #if os(iOS)
        showHintOnce(Self.gamePadHintKey, "Tap the GamePad screen to use it in the game.", ready: {
            gameManager.emulationState == .running && (isPadViewVisible || padIsOnDeviceInDualScreen)
        })
        #endif
    }

    private func setTopBarHidden(_ hidden: Bool) {
        withAnimation(.easeInOut(duration: 0.25)) { topBarHidden = hidden }
    }

    @ViewBuilder private var topBarRevealHandle: some View {
        if topBarHidden {
            // Over a visible GamePad screen the big handle would sit on the part of the touchscreen a game may use,
            // so a compact one takes its place there.
            #if os(iOS)
            if isPadViewVisible || padIsOnDeviceInDualScreen {
                CompactTopBarRevealHandle { setTopBarHidden(false) }
                    .transition(.opacity)
            } else {
                TopBarRevealHandle { setTopBarHidden(false) }
                    .transition(.opacity)
            }
            #else
            TopBarRevealHandle { setTopBarHidden(false) }
                .transition(.opacity)
            #endif
        }
    }

    /// "Couldn't save Slot 2. <the bridge's own reason>". The reason is a full sentence from the bridge (IOSSaveState.cpp:
    /// out of storage, the game still loading, a save from an earlier session ...), so what the player reads is what went
    /// wrong, not a guess that covers every case. A bridge that gave none still gets a plain line.
    private static func saveStateFailureMessage(_ action: String, slot: Int, reason: String) -> String {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Couldn't \(action) Slot \(slot)." }
        return "Couldn't \(action) Slot \(slot). \(trimmed)"
    }

    /// Whether the picture-stopped card is up: while the watchdog says the picture has stopped, and
    /// after a save started from the card, so the result of that save is always seen.
    private var showsStallCard: Bool {
        guard gameManager.emulationState == .running, !stallCardDismissed else { return false }
        return gameManager.videoStalled || stallSaveRequested
    }

    private var stallTitle: String {
        switch gameManager.videoStallKind {
        case 0: return saveStateBusySlot != nil ? "Saving the game" : (saveStateStatus?.isWarning == true ? "Couldn't save" : "Saved")
        case 2: return "Graphics stopped working"
        case 3: return "Out of memory for the picture"
        case 4: return "Memory is running low"
        case 5: return "The screen stopped updating"
        default: return "The picture froze"
        }
    }

    private var stallAdvice: String {
        switch gameManager.videoStallKind {
        case 2: return "iOS stopped running this game's graphics. Tap Save State, then Quit Game. MuffinEMU will then ask you to close and reopen it before the next game."
        case 3: return "Tap Save State, then Quit Game and reopen MuffinEMU. After you quit, a lower Resolution (in Settings, Graphics) uses less memory."
        case 4: return "iOS may close MuffinEMU soon. Tap Save State now. After you quit, a lower Resolution (in Settings, Graphics) uses less memory."
        case 5: return "The game is still running but the screen isn't taking frames. This goes away by itself if it recovers. If it doesn't, tap Save State, then Quit Game and reopen MuffinEMU."
        default: return "The picture has stopped while the game keeps running. This goes away by itself if the picture comes back."
        }
    }

    /// Only a problem that can clear by itself is worth waiting on; the others are a decision to dismiss.
    private var stallDismissTitle: String {
        let kind = gameManager.videoStallKind
        return (kind == 1 || kind == 5) ? "Keep waiting" : "Dismiss"
    }

    /// Small card shown while the picture is stopped. The game's audio and input keep running
    /// in this state, so a save state still works. Only the card itself takes touches; the
    /// rest of the overlay lets them through to the game.
    private var videoStalledCard: some View {
        VStack(spacing: 10) {
            Text(stallTitle)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if gameManager.videoStalled {
                Text(stallAdvice)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if stallSaveRequested {
                Text(saveStateBusySlot != nil ? "Saving..." : (saveStateStatus?.message ?? ""))
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button("Save State") { saveStalledGame() }
                    .disabled(saveStateBusySlot != nil)
                Button("Quit Game") {
                    gameManager.stopEmulation()
                    isRunning = true
                }
                .disabled(saveStateBusySlot != nil)
                Button(stallDismissTitle) {
                    stallCardDismissed = true
                    stallSaveRequested = false
                }
            }
            .buttonStyle(MuffinBarButtonStyle())
        }
        .padding(14)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: 420)
    }

    /// Saves into the first empty slot, or the oldest one when all are used.
    private func saveStalledGame() {
        let slots = SaveStateStore.slots(for: game.id)
        let target = slots.first(where: { !$0.isOccupied })
            ?? slots.min(by: { ($0.savedAt ?? .distantPast) < ($1.savedAt ?? .distantPast) })
        guard let slot = target?.number else { return }
        stallSaveRequested = true
        saveStateStatus = nil
        performSaveState(slot: slot)
    }

    private func deleteSaveState(slot: Int) {
        let gameID = game.id
        SaveStateStore.delete(gameID: gameID, slot: slot)
        saveStateSlots = SaveStateStore.slots(for: gameID)
        reportSaveState(SaveStateStatus(message: "Slot \(slot) deleted.", isWarning: false))
    }

    /// Shows a save, load or delete result and says it aloud for VoiceOver, which would
    /// otherwise never notice a line appearing at the top of the list.
    private func reportSaveState(_ status: SaveStateStatus) {
        saveStateStatus = status
        #if os(iOS)
        UIAccessibility.post(notification: .announcement, argument: status.message)
        #endif
    }

    #if os(iOS)
    /// A true port of MeloCafe's `EmulationView.body` (`UI/Emulation/EmulationView.swift`)
    /// - same `visibleScreens` truth table, same phone-portrait special case
    /// (`screensSizeLayout`), same `smallGamePadTopRight` inset branch, same
    /// portrait/landscape VStack/HStack split. This can conditionally mount and unmount
    /// `MetalViewIOS`/`PadMetalViewIOS` via `ForEach(visibleScreens)`, exactly like
    /// MeloCafe's own `ForEach` mounts/unmounts its two `MetalViewContainer`s, because
    /// `DisplayRouter.sharedDeviceContainer()`/`sharedLocalPadContainer()` now hand back
    /// the same cached container on every `makeUIView()` call instead of a fresh one -
    /// see those two functions' doc comments in DisplayRouter.swift for the black-screen
    /// bug that made an earlier, literal attempt at this unsafe, and why it was fixed at
    /// the container-identity level rather than by keeping both views permanently
    /// mounted and toggling opacity (this file's previous approach).
    ///
    /// Two adaptations from MeloCafe's source, both real incompatibilities, not style
    /// choices:
    /// - MeloCafe's own virtual-controller overlay branch (`ControllerManager`/
    ///   `ControllerView` from Melo_Controller) is dropped entirely. MuffinEMU already
    ///   has its own separate on-screen control system (`OptimizedControlPanel`,
    ///   `MeloControlsOverlay`) layered outside this view in EmulatorViewOptimized's own
    ///   ZStack; duplicating controller rendering in here would fight it.
    /// - MeloCafe's `air.connected` (AirPlay mirroring) becomes
    ///   `displayRouter.placement == .dualScreen`, but NOT as a literal 1:1 substitution
    ///   into `visibleScreens`' `[false]` (pad-only) branch. MeloCafe's `cemuView`/
    ///   `cemuPadView` are two independently addressable Metal views, so showing the pad
    ///   one on-device while `Air.play()` separately mirrors the TV one is coherent.
    ///   MuffinEMU's `.dualScreen` instead reroutes whichever Wii U screen isn't going to
    ///   the external display directly into the EXISTING `deviceContainer` behind
    ///   `MetalViewIOS` (`DisplayRouter.syncPadSurface`, which adds the pad's
    ///   `MetalLayerView` straight into `deviceContainer` when the TV has left for the
    ///   external display) - `syncLocalPadSurface()` is unconditionally gated off by
    ///   `placement != .dualScreen`, so `PadMetalViewIOS`'s own container never gets a
    ///   registered surface in this placement at all. Mapping the pad-only branch onto
    ///   `PadMetalViewIOS` here would therefore mount a container guaranteed to render
    ///   nothing; showing `MetalViewIOS` alone instead displays whatever DisplayRouter
    ///   actually routed into `deviceContainer` for this placement, which is the correct
    ///   real content. (`.dualScreen` itself is unverified on real hardware per
    ///   DisplayRouter's own doc comment, so this path is exercised even less than the
    ///   rest of this feature - flagged, not fixed further, since reconciling on-device
    ///   Screen Layout with dual-screen routing is a separate problem from this port.)
    private var screenLayoutComposition: some View {
        GeometryReader { geometry in
            let portrait = geometry.size.height >= geometry.size.width
            let phonePortrait = UIDevice.current.userInterfaceIdiom == .phone && portrait

            if phonePortrait {
                screensSizeLayout(in: geometry.size)
            } else if screenLayout == .smallGamePadTopRight && displayRouter.placement != .dualScreen {
                let padWidth = geometry.size.width * 0.25
                let padHeight = min(padWidth * 9 / 16, geometry.size.height)

                HStack(alignment: .top, spacing: 0) {
                    MetalViewIOS(gameManager: gameManager)
                        .frame(width: geometry.size.width - padWidth, height: geometry.size.height)
                        .touchLabTVScreen()

                    padScreen
                        .frame(width: padWidth, height: padHeight)
                        // Below the top bar while it is showing, so the bar's buttons don't sit on the GamePad
                        // screen and eat its taps.
                        .padding(.top, topBarHidden ? 0 : max(0, topBarHeight - geometry.frame(in: .global).minY))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: topBarHidden)
                }
            } else if portrait {
                VStack(spacing: 0) { screens }
            } else {
                HStack(spacing: 0) { screens }
            }
        }
        .ignoresSafeArea(.all, edges: verticalSizeClass == .regular ? .horizontal : .all)
        // The picture is letterboxed unless "Frame stretching" is on.
        .trackTouchLabScreens($touchLabScreens, imageIsAspectFit: { !FrameStretch.isEnabled })
        .onAppear { updateVisibleOutputs() }
        .onChange(of: screenLayout) { _ in updateVisibleOutputs() }
        .onChange(of: localSwapped) { _ in updateVisibleOutputs() }
        .onChange(of: displayRouter.placement) { _ in updateVisibleOutputs() }
        .onDisappear {
            // MeloCafe's own onDisappear sets both outputs false outright - not ported
            // literally, because this specific view can disappear for a reason MeloCafe's
            // never could: the previewPad-enabled branch above (`if previewPadEnabled &&
            // !useMeloControls`) is a SIBLING composition over the same still-running
            // title, and visible-outputs is a global engine setting, not scoped to
            // whichever SwiftUI view happens to be on screen. Forcing both false here
            // would black out that other branch's own MetalViewIOS if it's the one still
            // showing. Resetting to TV-only instead - matching this file's own prior
            // behavior - is the safe default for "this composition went away, but the
            // title itself may still be very much running."
            DisplayRouter.shared.updateLocalVisibleOutputs(showTV: true, showPad: false)
            // Mirrors MeloCafe's own `cemuPadView.cancelActiveTouches()` call here -
            // MuffinEMU has no such method, but this is the same cleanup MetalView.swift's
            // touch-cancel path already performs elsewhere (see sendPadTouch below and the
            // pad's own DragGesture): a touch in progress when this view disappears must
            // not leave the GamePad's touchscreen stuck "down" for a title that keeps running.
            cemu_bridge_set_pad_touch(0, 0, false)
        }
    }

    /// Which of the two Wii U screens should be in the tree right now - `true` for the
    /// TV (`MetalViewIOS`), `false` for the GamePad (`PadMetalViewIOS`) - a direct port
    /// of MeloCafe's `EmulationView.visibleScreens`. `ForEach(visibleScreens, id: \.self)`
    /// is safe on a raw `[Bool]` the same way it is in MeloCafe's source: the two
    /// possible elements are always distinct, so there's never a duplicate identity for
    /// SwiftUI to complain about.
    private var visibleScreens: [Bool] {
        if displayRouter.placement == .dualScreen { return [true] }
        if screenLayout.showsBothScreens { return localSwapped ? [false, true] : [true, false] }
        return [!localSwapped]
    }

    /// MeloCafe's own phone-portrait special case: both screens stacked at a fixed 16:9
    /// height each, with whatever space is left over beneath them - MeloCafe fills that
    /// with its virtual controller overlay when one exists and a plain `Spacer`
    /// otherwise; MuffinEMU never mounts a controller overlay in here (see
    /// screenLayoutComposition's doc comment), so it's always the `Spacer`.
    private func screensSizeLayout(in size: CGSize) -> some View {
        return VStack(spacing: 0) {
            ForEach(visibleScreens, id: \.self) { main in
                let height = portraitScreenHeight(main: main, in: size)
                screenView(main: main)
                    .frame(width: height * 16 / 9, height: height)
                    .frame(width: size.width)
            }
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    /// How tall a screen is when the phone is upright. The TV (or the only screen) runs the full
    /// width at 16:9. With both screens up, the GamePad screen under it gives up height to the
    /// controls, down to about half the width, centred; below that the controls cover the bottom
    /// of it instead (see belowPicture) rather than shrink it to a postage stamp.
    private func portraitScreenHeight(main: Bool, in size: CGSize) -> CGFloat {
        let full = size.width * 9.0 / 16.0
        guard !main, visibleScreens.count > 1 else { return full }
        let room = size.height - full - ControllerGeometry.Portrait.minimumHeight(joystick: joystickMode)
        return min(full, max(full * 0.55, room))
    }

    private var screens: some View {
        ForEach(visibleScreens, id: \.self) { main in
            screenView(main: main)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// `main ? MetalViewIOS : PadMetalViewIOS`, matching MeloCafe's own
    /// `main ? cemuView : cemuPadView` - the GamePad's touchscreen gesture lives here
    /// rather than as a modifier applied after the fact in `screens`/`screensSizeLayout`,
    /// since this is the one place both call sites actually construct the pad view.
    @ViewBuilder
    private func screenView(main: Bool) -> some View {
        if main {
            // In dual-screen with the TV on the external display, this view is showing the GamePad screen,
            // so it has to take GamePad touches too (Splatoon's map and super jump, for one). The gesture is
            // always attached and decides per touch, so the view keeps the same identity when that changes.
            MetalViewIOS(gameManager: gameManager)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if padIsOnDeviceInDualScreen { sendPadTouch(value.location, down: true) }
                        }
                        .onEnded { value in
                            if padIsOnDeviceInDualScreen { sendPadTouch(value.location, down: false) }
                        }
                )
                .touchLabTVScreen()
        } else {
            padScreen
        }
    }

    /// Whether this device is showing the GamePad screen in dual-screen, so its touches are the GamePad's:
    /// the other screen when the screens are not swapped, or the same screen when they are.
    private var padIsOnDeviceInDualScreen: Bool {
        displayRouter.gamePadTouchOnDevice
    }

    /// The GamePad's own touchscreen - a real Wii U input distinct from every button on
    /// the pad. Only ever mounted (via `screenView`/the `smallGamePadTopRight` branch)
    /// while it's actually the screen on top, so unlike this file's previous version
    /// there's no `padHidden`/opacity gate to apply here: being in the tree at all now
    /// means being visible and hit-testable. Coordinates are local to this view's own
    /// frame, in points; the bridge wants the same physical-pixel space
    /// `cemu_bridge_resize_render_surface()` already sizes this surface in, so they're
    /// scaled the same way that sizing is - see RenderScale.swift's effectiveRenderScale.
    private var padScreen: some View {
        // Simultaneous, like the TV screen's gesture above. This view's container is cached and
        // re-mounted on every swap; an exclusive minimum-distance-0 drag on it is the prime
        // suspect for every control going dead after swapping to the GamePad screen.
        PadMetalViewIOS()
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in sendPadTouch(value.location, down: true) }
                    .onEnded { value in sendPadTouch(value.location, down: false) }
            )
            // After the gesture, so it reports the same frame the gesture measures in.
            .touchLabGamePadScreen()
    }

    private func sendPadTouch(_ location: CGPoint, down: Bool) {
        // The pad surface is sized at PadSurfaceScale, not at the TV's render scale
        let scale = DisplayRouter.shared.padSurfaceScale
        cemu_bridge_set_pad_touch(Double(location.x) * scale, Double(location.y) * scale, down)
    }

    /// Whether the GamePad screen is currently one of the mounted `visibleScreens` -
    /// drives the "hide controls to touch the GamePad screen" button in the top bar,
    /// which has no `GeometryReader` of its own to derive this from directly.
    private var isPadViewVisible: Bool {
        visibleScreens.contains(false) || padIsOnDeviceInDualScreen
    }

    /// A direct port of MeloCafe's `EmulationView.updateVisibleOutputs()`, using
    /// `DisplayRouter`'s existing `updateLocalVisibleOutputs` wrapper in place of calling
    /// MeloCafe's `CemuUIKit_SetVisibleOutputs` (MuffinEMU's own bridge equivalent is
    /// `cemu_bridge_set_visible_outputs`) directly, so this stays
    /// consistent with `DisplayRouter`'s own bookkeeping (it already no-ops during
    /// `.dualScreen`, matching MeloCafe's reasoning for forcing both outputs on while
    /// `air.connected` - see screenLayoutComposition's doc comment for why that branch of
    /// `visibleScreens` itself still had to change).
    private func updateVisibleOutputs() {
        let both = displayRouter.placement == .dualScreen || screenLayout.showsBothScreens
        DisplayRouter.shared.updateLocalVisibleOutputs(showTV: both || !localSwapped, showPad: both || localSwapped)
        if !both && !localSwapped {
            cemu_bridge_set_pad_touch(0, 0, false)
        }
    }
    #endif
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
/// Where MuffinEMU's own pad and the preview pad send a press. HOME is the app's, not the
/// game's: the core's GamePad mapping has no HOME bit, so it opens the HOME menu instead of
/// reaching the bridge. The label is recorded first, so the diagnostics overlay still shows it.
@MainActor private func sendPadButton(_ label: String, _ pressed: Bool) {
    PadDiagnostics.shared.recordInput(label, pressed)
    if label == "HOME" {
        HomeMenuRouter.shared.padHome(pressed: pressed)
        return
    }
    cemu_bridge_set_button_state(cemuBridgeButton(forLabel: label), pressed)
}

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

    // The preview pad draws the GamePad's own HOME button. sendPadButton above never lets it
    // reach the bridge (it opens the HOME menu), so this only keeps the label from being unknown.
    case "HOME": return CEMU_BRIDGE_BUTTON_HOME

    // "POWER" and "TV" reach here from the preview pad's hardware-accurate face, and
    // they stay unmapped deliberately rather than being pointed at something close.
    // They are console functions, not GamePad buttons: there is no VPAD bit for either,
    // so binding them to anything would be inventing input the Wii U never had.
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
