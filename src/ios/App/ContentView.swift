import SwiftUI
import MetalKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var gameManager = GameManager()
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

    @State private var romImportErrorMessage: String?

    var filteredGames: [GameMetadata] {
        let gamesToShow = showingFavorites ? gameManager.favorites : gameManager.games
        return searchText.isEmpty
            ? gamesToShow
            : gamesToShow.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
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

                            Button(action: { showingFavorites.toggle() }) {
                                Image(systemName: showingFavorites ? "heart.fill" : "heart")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(showingFavorites ? MuffinTheme.blushPink : MuffinTheme.sparkleCream.opacity(0.8))
                            }
                            .frame(width: 44, height: 44)
                            .background(MuffinTheme.sparkleCream.opacity(0.15))
                            .cornerRadius(14)

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
                            } label: {
                                Image(systemName: "doc.badge.plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(MuffinTheme.sparkleCream.opacity(0.8))
                                    .frame(width: 44, height: 44)
                                    .background(MuffinTheme.sparkleCream.opacity(0.15))
                                    .cornerRadius(14)
                            }

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
                    SearchBarPolished(text: $searchText)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                    if gameManager.isLoading {
                        LoadingView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredGames.isEmpty {
                        EmptyGamesView()
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
                                            onDecryptToFiles: { decryptTarget = game }
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
        .alert("Couldn't import ROM", isPresented: .constant(romImportErrorMessage != nil), presenting: romImportErrorMessage) { _ in
            Button("OK") { romImportErrorMessage = nil }
        } message: { message in
            Text(message)
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
                        }
                        .padding(8)
                    }
                    Spacer()
                }
            }
            .aspectRatio(3 / 4, contentMode: .fit)

            VStack(alignment: .leading, spacing: 8) {
                Text(game.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .foregroundColor(MuffinTheme.brownDarkest)

                HStack(spacing: 8) {
                    Label(game.region, systemImage: "globe")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(MuffinTheme.brownMid)
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
                }
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
    @State private var showSkinSelector = false
    /// Turns the pad into something you position rather than something you press. Local
    /// state, not AppStorage: nobody wants to come back to a game and find the controls
    /// still in edit mode because that is how they last left them.
    @State private var isEditingControlLayout = false
    @State private var isPaused = false
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
    /// Same key ControllerPad.swift reads to decide which gesture (if either) a
    /// button/cluster gets. Declared here too so the segmented control below writes to
    /// the thing actually being edited, same reasoning as the two sliders above it.
    @AppStorage(ControllerLayoutSettings.individualEditModeKey)
    private var individualEditMode = ControllerLayoutSettings.defaultIndividualEditMode
    /// Off by default - see the branch on this flag a few lines below for exactly what
    /// it swaps in and why the shipping path is otherwise untouched.
    @AppStorage(PreviewPadStore.enabledKey) private var previewPadEnabled = false
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Button(action: {
                        gameManager.stopEmulation()
                        isRunning = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                    }
                    .buttonStyle(MuffinSecondaryButtonStyle())

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
                        // ResumeTitle(), which already exist and were never called from
                        // anywhere on iOS - this is the first thing to use them.
                        // isPaused is local state rather than a query, because there is
                        // no cemu_bridge_is_paused() to ask - only this button ever
                        // changes it, so it cannot drift out of sync with the engine.
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

                if previewPadEnabled {
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
                                cemu_bridge_set_button_state(cemuBridgeButton(forLabel: label), pressed)
                            },
                            onStick: { stick, position in
                                cemu_bridge_set_stick_axis(
                                    stick == 0 ? CEMU_BRIDGE_STICK_LEFT : CEMU_BRIDGE_STICK_RIGHT,
                                    Float(position.x), Float(position.y)
                                )
                            },
                            isEditingLayout: $isEditingControlLayout
                        )
                    }
                } else {
                    #if os(iOS)
                    MetalViewIOS(gameManager: gameManager)
                        .ignoresSafeArea()
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
            if !previewPadEnabled {
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
