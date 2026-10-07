import SwiftUI
import UIKit
import Photos

// Store screenshot mode. Settings > Diagnostics > "Capture store screenshots" (Advanced mode) steps the app through the
// screens worth showing on a store listing, with a demo library of well-known titles standing in for the player's own, and
// saves a full-resolution picture of each to Photos > MuffinEMU Screenshots. It only ever starts from that button.
//
// The demo library lives in memory: GameManager swaps it in and puts the real one back (beginDemoLibrary/endDemoLibrary),
// the game data and play history it reads sit in separate in-memory overlays, and the few library preferences it changes
// are saved first and restored afterwards (and restored on the next launch if the app is closed mid-run). Emulation is
// never started.

extension Notification.Name {
    static let muffinStoreShotScrollGamePage = Notification.Name("muffin.storeShots.scrollGamePage")
}

enum StoreShotScrollID {
    static let yourPlay = "storeShot.yourPlay"
    static let end = "storeShot.end"
}

// MARK: - Demo library

struct StoreDemoTitle {
    let slug: String
    let name: String
    let titleID: UInt64
    let tdbID: String
    let developer: String
    let publisher: String
    let genre: String
    let year: Int, month: Int, day: Int
    let localPlayers: Int
    let onlinePlayers: Int
    let synopsis: String
    let plays: Int
    let daysAgo: Int
}

enum StoreDemoLibrary {
    /// Real North American titles. Title IDs come from the game profiles shipped in the app where it has them; GameTDB IDs
    /// are what the covers are fetched under.
    static let titles: [StoreDemoTitle] = [
        StoreDemoTitle(slug: "mk8", name: "Mario Kart 8", titleID: 0x000500001010EC00, tdbID: "AMKE01",
                       developer: "Nintendo EAD", publisher: "Nintendo", genre: "Racing",
                       year: 2014, month: 5, day: 30, localPlayers: 4, onlinePlayers: 12,
                       synopsis: "Race anti-gravity tracks up walls and across ceilings with up to eleven rivals, in a Grand Prix full of shortcuts, items and gliders.",
                       plays: 142, daysAgo: 0),
        StoreDemoTitle(slug: "splatoon", name: "Splatoon", titleID: 0x0005000010176900, tdbID: "AGME01",
                       developer: "Nintendo EAD", publisher: "Nintendo", genre: "Shooter",
                       year: 2015, month: 5, day: 29, localPlayers: 2, onlinePlayers: 8,
                       synopsis: "Cover the arena in your team's ink, swim through it as a squid and win turf wars in a colourful team shooter.",
                       plays: 96, daysAgo: 1),
        StoreDemoTitle(slug: "3dworld", name: "Super Mario 3D World", titleID: 0x0005000010145C00, tdbID: "ARDE01",
                       developer: "Nintendo EAD", publisher: "Nintendo", genre: "Platformer",
                       year: 2013, month: 11, day: 22, localPlayers: 4, onlinePlayers: 0,
                       synopsis: "Run, jump and pounce through the Sprixie Kingdom alone or with three friends, with a cat suit for climbing and a clear pipe around every corner.",
                       plays: 54, daysAgo: 3),
        StoreDemoTitle(slug: "botw", name: "The Legend of Zelda: Breath of the Wild", titleID: 0x00050000101C9400, tdbID: "ALZE01",
                       developer: "Nintendo EPD", publisher: "Nintendo", genre: "Action-adventure",
                       year: 2017, month: 3, day: 3, localPlayers: 1, onlinePlayers: 0,
                       synopsis: "Wake in a ruined kingdom of Hyrule and explore it freely, climbing, gliding and cooking your way toward Calamity Ganon.",
                       plays: 71, daysAgo: 2),
        StoreDemoTitle(slug: "wwhd", name: "The Legend of Zelda: The Wind Waker HD", titleID: 0x0005000010143500, tdbID: "BCZE01",
                       developer: "Nintendo EAD", publisher: "Nintendo", genre: "Action-adventure",
                       year: 2013, month: 10, day: 4, localPlayers: 1, onlinePlayers: 0,
                       synopsis: "Sail a sea of islands as Link in a cel-shaded adventure, rebuilt in high definition with a faster sail and the Swift Sail.",
                       plays: 23, daysAgo: 9),
        StoreDemoTitle(slug: "pikmin3", name: "Pikmin 3", titleID: 0x000500001012BD00, tdbID: "AC3E01",
                       developer: "Nintendo EAD", publisher: "Nintendo", genre: "Strategy",
                       year: 2013, month: 8, day: 4, localPlayers: 2, onlinePlayers: 0,
                       synopsis: "Lead a crew of tiny Pikmin across a strange planet in search of fruit, with three captains to command at once.",
                       plays: 18, daysAgo: 14),
        StoreDemoTitle(slug: "bayo2", name: "Bayonetta 2", titleID: 0x0005000010172600, tdbID: "AQUE01",
                       developer: "PlatinumGames", publisher: "Nintendo", genre: "Action",
                       year: 2014, month: 10, day: 24, localPlayers: 2, onlinePlayers: 2,
                       synopsis: "The witch Bayonetta returns for a fast, stylish brawl through heaven and hell, dodging at the last instant to slow time.",
                       plays: 31, daysAgo: 6),
        StoreDemoTitle(slug: "dkctf", name: "Donkey Kong Country: Tropical Freeze", titleID: 0x0005000010137F00, tdbID: "ARKE01",
                       developer: "Retro Studios", publisher: "Nintendo", genre: "Platformer",
                       year: 2014, month: 2, day: 21, localPlayers: 2, onlinePlayers: 0,
                       synopsis: "Donkey Kong and his crew cross a frozen archipelago in a demanding 2D platformer packed with secrets and barrel blasts.",
                       plays: 27, daysAgo: 11),
        StoreDemoTitle(slug: "xcx", name: "Xenoblade Chronicles X", titleID: 0x00050000101C4D00, tdbID: "AX5E01",
                       developer: "Monolith Soft", publisher: "Nintendo", genre: "Role-playing",
                       year: 2015, month: 12, day: 4, localPlayers: 1, onlinePlayers: 32,
                       synopsis: "Survive on the alien planet Mira in a vast open-world role-playing game, on foot or in a towering Skell.",
                       plays: 44, daysAgo: 5),
        StoreDemoTitle(slug: "smash", name: "Super Smash Bros. for Wii U", titleID: 0x0005000010144F00, tdbID: "AXFE01",
                       developer: "Sora Ltd., Bandai Namco Studios", publisher: "Nintendo", genre: "Fighting",
                       year: 2014, month: 11, day: 21, localPlayers: 8, onlinePlayers: 4,
                       synopsis: "Nintendo's favourite characters battle on stages from across their worlds, for up to eight players at once.",
                       plays: 118, daysAgo: 0),
    ]

    static func gameID(_ t: StoreDemoTitle) -> String { "demo-\(t.slug)" }

    /// Where demo covers are kept: the caches folder, never the player's Roms folder.
    static var coverDirectory: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("MuffinStoreScreenshots", isDirectory: true)
    }

    static func info(for t: StoreDemoTitle) -> GameInfo {
        // The stored game data wins when it already holds this title.
        if let stored = GameDataStore.shared.storedInfo(tdbID: t.tdbID) { return stored }
        var info = GameInfo(id: t.tdbID, name: t.name, productCode: String(t.tdbID.prefix(4)), region: "NTSC-U")
        info.languages = ["EN"]
        info.titles = ["EN": t.name]
        info.synopsis = ["EN": t.synopsis]
        info.developer = t.developer
        info.publisher = t.publisher
        info.genres = [t.genre.lowercased()]
        info.releases = [GameTDBRelease(region: "USA", gameID: t.tdbID, year: t.year, month: t.month, day: t.day)]
        info.localPlayers = t.localPlayers
        info.onlinePlayers = t.onlinePlayers
        info.ratingType = "ESRB"
        info.ratingValue = t.slug == "bayo2" ? "M" : (t.slug == "botw" || t.slug == "xcx" || t.slug == "splatoon" ? "T" : "E10+")
        info.controls = [GameTDBControl(type: "pad", required: false), GameTDBControl(type: "procontroller", required: false)]
        return info
    }

    /// The games, without covers yet.
    static func games() -> [GameMetadata] {
        titles.enumerated().map { index, t in
            let id = gameID(t)
            return GameMetadata(
                id: id, title: t.name, romPath: "/Roms/\(id)", coverPath: nil, region: "USA",
                releaseDate: String(format: "%04d-%02d-%02d", t.year, t.month, t.day), genre: t.genre,
                isFavorite: false, titleId: t.titleID, dumpDirectoryPath: nil, displayTitle: t.name,
                addedDate: Date().addingTimeInterval(-Double(index) * 86_400))
        }
    }

    static func playStats() -> [String: LibraryPlayStats.Entry] {
        var out: [String: LibraryPlayStats.Entry] = [:]
        for t in titles {
            let when = Date().addingTimeInterval(-Double(t.daysAgo) * 86_400 - 3_600)
            out[gameID(t)] = LibraryPlayStats.Entry(last: when, count: t.plays)
        }
        return out
    }

    static func overlay() -> [String: (match: GameMatch, info: GameInfo)] {
        var out: [String: (match: GameMatch, info: GameInfo)] = [:]
        for t in titles {
            out[gameID(t)] = (GameMatch(tdbID: t.tdbID, confidence: 1.0, method: "titleId"), info(for: t))
        }
        return out
    }

    /// Fetches each cover the way the library does (GameTDB HQ by ID) into the caches folder, once.
    static func fetchCovers() async {
        let boxart = coverDirectory.appendingPathComponent(".boxart", isDirectory: true)
        try? FileManager.default.createDirectory(at: boxart, withIntermediateDirectories: true)
        await withTaskGroup(of: Void.self) { group in
            for t in titles {
                group.addTask {
                    let id = gameID(t)
                    let have = ["jpg", "png"].contains { FileManager.default.fileExists(atPath: boxart.appendingPathComponent("\(id).hq.\($0)").path) }
                    if have { return }
                    guard let found = try? await CoverArtFetcher.fetchArt(forGameTdbId: t.tdbID) else { return }
                    let name = found.isHQ ? "\(id).hq.\(found.ext)" : "\(id).\(found.ext)"
                    try? found.data.write(to: boxart.appendingPathComponent(name), options: .atomic)
                }
            }
        }
    }

    /// Runs each game through the normal cover chain (an installed or applied art pack, GameTDB HQ, GameTDB standard).
    static func withCovers(_ games: [GameMetadata]) -> [GameMetadata] {
        games.map { game in
            var g = game
            let context = CoverContext(gameID: g.id, romPath: g.romPath, dumpDirectoryPath: nil, libraryDirectory: coverDirectory,
                                       currentCoverPath: nil, region: g.region, titles: [g.displayTitle, g.title].compactMap { $0 })
            g.coverPath = CoverSourceChain.cachedPath(context)
            return g
        }
    }
}

// MARK: - Progress overlay

@MainActor
final class StoreShotProgress: ObservableObject {
    enum Phase: Equatable {
        case preparing
        case capturing(current: Int, total: Int)
        case saving
        case finished(String)
    }
    @Published var phase: Phase = .preparing
    /// True while a picture is being taken, so the overlay is not in it.
    @Published var hidden = false
    var onStop: () -> Void = {}
    var onDone: () -> Void = {}
}

private struct StoreShotOverlayView: View {
    @ObservedObject var model: StoreShotProgress

    var body: some View {
        ZStack {
            switch model.phase {
            case .finished(let message):
                Color.black.opacity(0.45).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text(message)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                    Button("Done") { model.onDone() }
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .padding(.horizontal, 36).padding(.vertical, 10)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundColor(.white)
                }
                .padding(24)
                .frame(maxWidth: 360)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(UIColor.systemBackground)))
                .padding(24)
            default:
                VStack {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(label)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        Button("Stop") { model.onStop() }
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Color(UIColor.systemBackground)).shadow(radius: 6))
                    .padding(.top, 12)
                    Spacer()
                }
                .opacity(model.hidden ? 0 : 1)
            }
        }
    }

    private var label: String {
        switch model.phase {
        case .preparing: return "Preparing demo library"
        case .capturing(let c, let t): return "Capturing \(c) of \(t)"
        case .saving: return "Saving to Photos"
        case .finished: return ""
        }
    }
}

/// Lets touches through everywhere except the controls on the overlay.
private final class StoreShotOverlayWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        return hit == rootViewController?.view ? nil : hit
    }
}

// MARK: - A Settings section on its own

private struct StoreShotSectionScreen<Content: View>: View {
    let title: String
    let scrollToEnd: Bool
    let content: Content

    init(title: String, scrollToEnd: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.scrollToEnd = scrollToEnd
        self.content = content()
    }

    var body: some View {
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient.ignoresSafeArea()
                ScrollViewReader { proxy in
                    Form {
                        content
                        Section { Color.clear.frame(height: 1).listRowBackground(Color.clear) }
                            .id(StoreShotScrollID.end)
                    }
                    .foregroundColor(MuffinTheme.brownDarkest)
                    .onAppear {
                        guard scrollToEnd else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            proxy.scrollTo(StoreShotScrollID.end, anchor: .bottom)
                        }
                    }
                }
            }
            .navigationTitle(title)
            .muffinOpaqueNavigationBar(MuffinTheme.formGround)
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Runner

@MainActor
final class StoreScreenshotRunner {
    static let shared = StoreScreenshotRunner()

    weak var gameManager: GameManager?
    private(set) var isRunning = false
    private var stopRequested = false
    private var overlayWindow: UIWindow?
    private let progress = StoreShotProgress()

    static let albumName = "MuffinEMU Screenshots"
    private static let albumIDKey = "muffin.storeShots.albumID"
    private static let restoreKey = "muffin.storeShots.restorePrefs"

    // Library preferences the run changes, put back afterwards.
    private static var changedKeys: [String] {
        [LibraryCardStyle.storageKey, LibraryCardStyle.sizeStorageKey, LibraryGrouping.storageKey,
         LibraryFilter.storageKey, "muffin.library.sortOrder"]
    }

    private struct Step {
        let slug: String
        let run: () async throws -> Void
    }

    // MARK: Entry points

    /// Called from Settings > Diagnostics. The caller closes Settings first.
    func start() {
        guard !isRunning else { return }
        guard let gameManager, gameManager.emulationState == .idle else { return }
        isRunning = true
        stopRequested = false
        Task { await run(gameManager) }
    }

    /// A run that was cut off by the app closing leaves its saved preferences behind; put them back.
    static func restoreIfInterrupted() {
        let defaults = UserDefaults.standard
        guard let saved = defaults.dictionary(forKey: restoreKey) else { return }
        for key in changedKeys {
            if let value = saved[key], !(value is NSNull) { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: restoreKey)
    }

    // MARK: The run

    private func run(_ gameManager: GameManager) async {
        showOverlay()
        progress.phase = .preparing
        progress.hidden = false
        await sleep(0.8) // Settings is closing
        await dismissAll()

        var images: [(slug: String, data: Data)] = []
        var message = ""
        var demoActive = false
        var savedPrefs = false

        do {
            guard await Self.requestAddOnlyAccess() else {
                throw StoreShotError.message("Photos access is off. Allow adding photos to MuffinEMU in Settings, then try again.")
            }

            // Demo library, in memory only.
            savePreferences(); savedPrefs = true
            let defaults = UserDefaults.standard
            for key in Self.changedKeys where key != LibraryCardStyle.storageKey { defaults.removeObject(forKey: key) }
            GameDataStore.shared.setDemoOverlay(StoreDemoLibrary.overlay())
            LibraryPlayStats.shared.setDemoEntries(StoreDemoLibrary.playStats())
            await StoreDemoLibrary.fetchCovers()
            gameManager.beginDemoLibrary(StoreDemoLibrary.withCovers(StoreDemoLibrary.games()))
            demoActive = true

            let steps = makeSteps(gameManager)
            for (index, step) in steps.enumerated() {
                if stopRequested { break }
                progress.phase = .capturing(current: index + 1, total: steps.count)
                do {
                    try await step.run()
                    await sleep(1.5) // images and layout settle
                    progress.hidden = true
                    await sleep(0.2)
                    let data = captureKeyWindow()
                    progress.hidden = false
                    if let data { images.append((step.slug, data)) }
                } catch {
                    progress.hidden = false // this screen is skipped; carry on
                }
            }

            await dismissAll()
            if !images.isEmpty {
                progress.phase = .saving
                try await Self.saveToPhotos(images.enumerated().map { (i, item) in
                    (name: String(format: "MuffinEMU-%02d-%@.png", i + 1, item.slug), data: item.data)
                })
                message = "Saved \(images.count) screenshots to Photos > \(Self.albumName)"
            } else {
                message = stopRequested ? "Stopped. No screenshots were saved." : "No screenshots could be captured."
            }
        } catch let StoreShotError.message(text) {
            message = text
        } catch {
            message = "Couldn't save the screenshots: \(error.localizedDescription)"
        }

        // Put everything back, whatever happened.
        await dismissAll()
        if demoActive { gameManager.endDemoLibrary() }
        GameDataStore.shared.setDemoOverlay([:])
        LibraryPlayStats.shared.setDemoEntries([:])
        if savedPrefs { Self.restoreIfInterrupted() }

        progress.hidden = false
        progress.phase = .finished(message)
        progress.onDone = { [weak self] in self?.finish() }
    }

    private func finish() {
        overlayWindow?.isHidden = true
        overlayWindow = nil
        isRunning = false
    }

    private enum StoreShotError: Error { case message(String) }

    private func savePreferences() {
        let defaults = UserDefaults.standard
        var saved: [String: Any] = [:]
        for key in Self.changedKeys { saved[key] = defaults.object(forKey: key) ?? NSNull() }
        defaults.set(saved, forKey: Self.restoreKey)
    }

    // MARK: Steps

    private func makeSteps(_ gameManager: GameManager) -> [Step] {
        let mk8 = gameManager.games.first { $0.id == StoreDemoLibrary.gameID(StoreDemoLibrary.titles[0]) }
        let defaults = UserDefaults.standard
        var gamePage: UIViewController?

        func library(_ style: LibraryCardStyle) -> () async throws -> Void {
            { [self] in
                await dismissAll()
                defaults.set(style.rawValue, forKey: LibraryCardStyle.storageKey)
            }
        }
        func presentGamePage() async throws {
            guard let mk8 else { throw StoreShotError.message("no demo game") }
            await dismissAll()
            let page = GamePageView(
                game: mk8, store: PerGameSettingsStore.shared, gameManager: gameManager,
                onPlay: {}, onDecrypt: {}, onImportDLC: {}, onImportUpdate: {},
                onRemoveDLC: {}, onRemoveUpdate: {}, onRemoveGame: {})
            gamePage = await present(page)
        }

        return [
            Step(slug: "library-cards", run: library(.standard)),
            Step(slug: "library-large-covers", run: library(.largeCovers)),
            Step(slug: "library-3d-boxes", run: library(.box3d)),
            Step(slug: "game-page", run: {
                defaults.set(LibraryCardStyle.standard.rawValue, forKey: LibraryCardStyle.storageKey)
                try await presentGamePage()
            }),
            Step(slug: "game-page-your-play", run: { [self] in
                if gamePage == nil || topPresented() !== gamePage { try await presentGamePage(); await sleep(1.0) }
                NotificationCenter.default.post(name: .muffinStoreShotScrollGamePage, object: nil)
                await sleep(0.8)
            }),
            Step(slug: "settings", run: { [self] in
                await dismissAll()
                _ = await present(SettingsView(gameManager: gameManager))
            }),
            Step(slug: "cover-and-data", run: { [self] in
                await dismissAll()
                _ = await present(StoreShotSectionScreen(title: "Cover + data") { CoverDataSettingsSection(gameManager: gameManager) })
            }),
            Step(slug: "on-screen-controls", run: { [self] in
                await dismissAll()
                _ = await present(StoreShotSectionScreen(title: "On-screen controls") { OnScreenControlsSection() })
            }),
            Step(slug: "display", run: { [self] in
                await dismissAll()
                _ = await present(StoreShotSectionScreen(title: "Display", scrollToEnd: true) { DisplaySettingsSection() })
            }),
            Step(slug: "network-service", run: { [self] in
                await dismissAll()
                _ = await present(StoreShotSectionScreen(title: "Network service") { NetworkServiceSettingsSection() })
            }),
            Step(slug: "appearance-themes", run: { [self] in
                await dismissAll()
                _ = await present(ThemePickerView())
            }),
        ]
    }

    // MARK: Windows and presentation

    private var keyWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .filter { !($0 is StoreShotOverlayWindow) }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }

    private func topPresented() -> UIViewController? {
        var top = keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top === keyWindow?.rootViewController ? nil : top
    }

    private func dismissAll() async {
        guard let root = keyWindow?.rootViewController, root.presentedViewController != nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            root.dismiss(animated: false) { continuation.resume() }
        }
        await sleep(0.3)
    }

    @discardableResult
    private func present<V: View>(_ view: V) async -> UIViewController? {
        guard let root = keyWindow?.rootViewController else { return nil }
        let host = UIHostingController(rootView: view.muffinScrollEdgeBlurHidden())
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            root.present(host, animated: false) { continuation.resume() }
        }
        return host
    }

    private func showOverlay() {
        guard let scene = keyWindow?.windowScene else { return }
        let window = StoreShotOverlayWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        progress.onStop = { [weak self] in self?.stopRequested = true }
        let host = UIHostingController(rootView: StoreShotOverlayView(model: progress))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false // visible, but never made key: the app's own window stays the key window
        overlayWindow = window
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: Capture

    /// The key window at full native resolution, as PNG.
    private func captureKeyWindow() -> Data? {
        guard let window = keyWindow else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return image.pngData()
    }

    // MARK: Photos

    private static func requestAddOnlyAccess() async -> Bool {
        let status: PHAuthorizationStatus = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
        }
        return status == .authorized || status == .limited
    }

    /// Adds every picture to the "MuffinEMU Screenshots" album, creating it when it isn't there. With add-only access the app
    /// can't always see an album it made on an earlier run, so a missing album may be made again.
    private static func saveToPhotos(_ items: [(name: String, data: Data)]) async throws {
        var foundAlbum: PHAssetCollection?
        let byTitle = PHFetchOptions()
        byTitle.predicate = NSPredicate(format: "title = %@", albumName)
        foundAlbum = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: byTitle).firstObject
        if foundAlbum == nil, let id = UserDefaults.standard.string(forKey: albumIDKey) {
            foundAlbum = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
        }
        let album = foundAlbum

        func perform(_ block: @escaping () -> Void) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges(block) { ok, error in
                    if ok { continuation.resume() } else { continuation.resume(throwing: error ?? StoreShotError.message("Photos refused the pictures.")) }
                }
            }
        }

        var createdAlbumID: String?
        do {
            try await perform {
                var placeholders: [PHObjectPlaceholder] = []
                for item in items {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = item.name
                    request.addResource(with: .photo, data: item.data, options: options)
                    if let placeholder = request.placeholderForCreatedAsset { placeholders.append(placeholder) }
                }
                let albumRequest: PHAssetCollectionChangeRequest?
                if let album {
                    albumRequest = PHAssetCollectionChangeRequest(for: album)
                } else {
                    let creation = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                    createdAlbumID = creation.placeholderForCreatedAssetCollection.localIdentifier
                    albumRequest = creation
                }
                albumRequest?.addAssets(placeholders as NSArray)
            }
            if let createdAlbumID { UserDefaults.standard.set(createdAlbumID, forKey: albumIDKey) }
        } catch {
            // The album step failed: still keep the pictures, one at a time and without it.
            var saved = 0
            for item in items {
                do {
                    try await perform {
                        let request = PHAssetCreationRequest.forAsset()
                        let options = PHAssetResourceCreationOptions()
                        options.originalFilename = item.name
                        request.addResource(with: .photo, data: item.data, options: options)
                    }
                    saved += 1
                } catch { continue }
            }
            if saved == 0 { throw error }
        }
    }
}
