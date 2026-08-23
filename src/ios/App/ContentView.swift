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

                Text("Full detail is in log.txt and CemuCrashLog.txt — Files ▸ On My iPad ▸ Cemu.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.45))
                    .multilineTextAlignment(.center)
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
    @State private var showingROMImporter = false
    /// Separate from showingROMImporter on purpose. A document picker only lets you
    /// SELECT a directory when UTType.folder is among its allowed types; with a
    /// file-only type list, tapping a folder navigates into it and there is no way to
    /// choose it. A full Wii U dump IS a directory (code/, content/, meta/), so one
    /// picker cannot serve both without making folder taps ambiguous. Two explicit
    /// entry points, two pickers.
    @State private var showingFolderImporter = false
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
                                    showingROMImporter = true
                                } label: {
                                    Label("Game file (.wux, .wud, .wua, .iso, .rpx)", systemImage: "doc")
                                }
                                Button {
                                    showingFolderImporter = true
                                } label: {
                                    Label("Game folder (code / content / meta)", systemImage: "folder")
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
        // .item, not .data or a list of ROM types. iOS has no built-in UTType for .rpx,
        // .wux, .wud or .wua, so any type-filtered list greys out exactly the files this
        // button exists to import - which is the reported "it only opens folders, you
        // cannot select things". .item is the root of the type hierarchy: everything
        // matches, nothing is greyed out, and GameManager.importROM does the deciding
        // afterwards against its own copy. .data is nearly as permissive but still
        // depends on the provider having resolved a byte-stream type for the file at
        // all; .item does not.
        .fileImporter(
            isPresented: $showingROMImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileImporter(
            isPresented: $showingFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .alert("Couldn't import ROM", isPresented: .constant(romImportErrorMessage != nil), presenting: romImportErrorMessage) { _ in
            Button("OK") { romImportErrorMessage = nil }
        } message: { message in
            Text(message)
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
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .cornerRadius(16)
                        .clipped()
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
                    Text("Add .wux, .wud, .wua, .rpx, or .iso files")
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
    @State private var showControls = true
    @State private var showSkinSelector = false
    @AppStorage(LaunchLogSettings.showKey) private var showLaunchLog = false
    @StateObject private var launchLog = LaunchLogStore()
    @State private var launchLogDismissed = false

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

                        // Reads the @Published frameRate directly rather than calling
                        // getFrameRate(): a plain method call cannot invalidate this
                        // view, so even once the value became real the HUD would only
                        // update when something else happened to redraw it. Until
                        // the emulator reports its first measurement this shows "--",
                        // not "0" - "0 FPS" reads as a measured stall, which is a
                        // different and much more alarming claim than "no reading yet".
                        HStack(spacing: 6) {
                            Image(systemName: "speedometer")
                                .font(.system(size: 12, weight: .semibold))
                            Text(gameManager.frameRate > 0 ? "\(gameManager.frameRate) FPS" : "-- FPS")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
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

                #if os(iOS)
                MetalViewIOS(gameManager: gameManager)
                    .ignoresSafeArea()
                #else
                MetalView(gameManager: gameManager)
                    .ignoresSafeArea()
                #endif

                if showControls {
                    OptimizedControlPanel(
                        skin: controllerSkin,
                        onDPadInput: { _ in },
                        onButtonInput: { _ in }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
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
                    .padding(.bottom, 24)
                }
                .transition(.opacity)
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                showControls.toggle()
            }
        }
        // Tied to this view's lifetime, not the store's: no launch log on screen means
        // nothing draining, and the C ring keeps filling either way so switching the
        // setting on mid-boot still catches up on everything already logged.
        .onAppear { if showLaunchLog { launchLog.start() } }
        .onDisappear { launchLog.stop() }
        .onChange(of: showLaunchLog) { enabled in
            if enabled { launchLog.start() } else { launchLog.stop() }
        }
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
