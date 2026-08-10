import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct GameMetadata: Codable, Identifiable {
    let id: String
    let title: String
    let romPath: String
    let coverPath: String?
    let region: String
    let releaseDate: String
    let genre: String
    var isFavorite: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, romPath, coverPath, region, releaseDate, genre
    }
}

@MainActor
class GameManager: ObservableObject {
    @Published var games: [GameMetadata] = []
    @Published var favorites: [GameMetadata] = []
    @Published var isLoading = false
    @Published var currentGame: GameMetadata?
    @Published var emulationState: EmulationState = .idle
    /// Last human-readable message from the engine bridge (e.g. "engine not built yet").
    @Published var lastStatusMessage: String = ""
    /// Real emulator frame rate, polled from the bridge once a second while a title
    /// is running (see startFrameRateMonitor()). 0 whenever nothing is rendering.
    @Published private(set) var frameRate: Int = 0
    private var frameRateTimer: Timer?

    private let romsDirectory = "Roms"
    private let gameListFile = "games.json"
    private var emulationEngine: EmulationEngine?
    private var surfaceRegistered = false

    init() {
        emulationEngine = EmulationEngine()
        Task {
            await loadGames()
        }
    }

    func loadGames() async {
        isLoading = true
        defer { isLoading = false }

        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let romsPath = documentsPath.appendingPathComponent(romsDirectory)

        try? fileManager.createDirectory(at: romsPath, withIntermediateDirectories: true)

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: romsPath,
                includingPropertiesForKeys: nil
            )

            var discoveredGames: [GameMetadata] = []

            for item in contents {
                let pathExtension = item.pathExtension.lowercased()
                guard ["wua", "wud", "iso", "rpx"].contains(pathExtension) else { continue }

                let gameID = item.deletingPathExtension().lastPathComponent

                let gameMetadata = GameMetadata(
                    id: gameID,
                    title: gameID,
                    romPath: item.path,
                    coverPath: findCover(for: gameID, in: romsPath),
                    region: "Unknown",
                    releaseDate: "Unknown",
                    genre: "Game"
                )

                discoveredGames.append(gameMetadata)
            }

            self.games = discoveredGames.sorted { $0.title < $1.title }
            self.favorites = self.games.filter { $0.isFavorite }
        } catch {
            print("Error scanning Roms directory: \(error)")
        }
    }

    private func findCover(for gameID: String, in directory: URL) -> String? {
        let fileManager = FileManager.default

        for ext in ["jpg", "jpeg", "png"] {
            let coverPath = directory.appendingPathComponent("\(gameID)_cover.\(ext)")
            if fileManager.fileExists(atPath: coverPath.path) {
                return coverPath.path
            }
        }

        return nil
    }

    enum ROMImportError: LocalizedError {
        case unsupportedFormat(String)
        case accessDenied
        case copyFailed(Error)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext):
                return "\".\(ext)\" isn't a supported ROM format (wua, wud, iso, rpx)."
            case .accessDenied:
                return "Couldn't access that file."
            case .copyFailed(let error):
                return "Couldn't copy the ROM: \(error.localizedDescription)"
            }
        }
    }

    private static let supportedROMExtensions: Set<String> = ["wua", "wud", "iso", "rpx"]

    /// Copies a user-picked ROM (from .fileImporter, so `source` is a security-scoped
    /// URL outside our sandbox - Files app, iCloud Drive, another app's share sheet)
    /// into Documents/Roms, then reloads the library so it shows up immediately.
    func importROM(from source: URL) async throws {
        let pathExtension = source.pathExtension.lowercased()
        guard Self.supportedROMExtensions.contains(pathExtension) else {
            throw ROMImportError.unsupportedFormat(pathExtension)
        }

        guard source.startAccessingSecurityScopedResource() else {
            throw ROMImportError.accessDenied
        }
        defer { source.stopAccessingSecurityScopedResource() }

        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ROMImportError.accessDenied
        }

        let romsPath = documentsPath.appendingPathComponent(romsDirectory)
        try? fileManager.createDirectory(at: romsPath, withIntermediateDirectories: true)

        let destination = romsPath.appendingPathComponent(source.lastPathComponent)

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw ROMImportError.copyFailed(error)
        }

        await loadGames()
    }

    func toggleFavorite(_ game: GameMetadata) {
        if let index = games.firstIndex(where: { $0.id == game.id }) {
            games[index].isFavorite.toggle()

            if games[index].isFavorite {
                favorites.append(games[index])
            } else {
                favorites.removeAll { $0.id == game.id }
            }
        }
    }

    func launchGame(_ game: GameMetadata) {
        currentGame = game
        emulationState = .loading
        surfaceRegistered = false

        guard let engine = emulationEngine else {
            emulationState = .error
            return
        }

        // Delegate to the real Cemu core via the bridge. Pre-M1 (core not compiled
        // for iOS yet) this honestly reports "engine not built" rather than faking a run.
        guard engine.coreAvailable else {
            lastStatusMessage = engine.statusText
            emulationState = .error
            return
        }

        // Actual init/boot is deferred to registerRenderSurface(...) below, called by
        // MetalViewIOS once its view has mounted while emulationState == .loading (see
        // ContentView.swift). WindowSystem::GetWindowPhysSize() is read synchronously
        // by the GPU thread the instant boot() spawns it (M3, CemuBridge.mm), so a real
        // surface must be registered with the bridge before boot() runs, not after -
        // this view previously only appeared once emulationState == .running, i.e.
        // strictly after boot() had already returned.
    }

    /// Called by DisplayRouter once it has decided which display the Wii U TV screen
    /// belongs on, while emulationState == .loading. Registers the render surface (fast,
    /// safe to run synchronously on the calling - main - thread: sets a few WindowSystem
    /// fields and constructs the renderer, doesn't touch the GPU thread), then runs
    /// the actual init/boot on a detached background task so a slow interpreter boot -
    /// or any bug in it - can't freeze the UI, regardless of how well-behaved the C++
    /// side turns out to be.
    ///
    /// Returns whether this call is the one that registered. The router needs a real
    /// answer rather than an assumption: it only creates a GamePad surface once a TV
    /// surface exists, because InitializeLayer(mainWindow=false) needs the renderer that
    /// the TV registration constructs.
    #if os(iOS)
    @discardableResult
    func registerRenderSurface(uiView: UIView, width: Int32, height: Int32, dpiScale: Double) -> Bool {
        guard emulationState == .loading, !surfaceRegistered,
              let game = currentGame, let engine = emulationEngine else { return false }
        surfaceRegistered = true

        // passRetained, not passUnretained - deliberately keeping this one view alive
        // for the app's lifetime. Confirmed via a live device SIGSEGV inside
        // MetalRenderer::BeginFrame() -> AcquireDrawable() -> nextDrawable():
        // CreateMetalLayer() (MetalLayer.mm) adds the real CAMetalLayer as a sublayer
        // of this view's CALayer, and the C++ side (MetalLayerHandle) holds a bare,
        // ARC-invisible `CA::MetalLayer*` to it with no retain of its own. If the view
        // is deallocated - SwiftUI is free to tear down and rebuild a
        // UIViewRepresentable's underlying view on essentially any hierarchy change,
        // e.g. the .loading -> .running transition removing the "Booting..." overlay -
        // its layer, and therefore our sublayer, goes with it while the GPU thread
        // still holds a raw pointer, and the very next draw call reads freed memory.
        //
        // Belt and braces as of the display-routing work: the view handed in here is
        // DisplayRouter.shared.tvRenderView, which that singleton also holds strongly
        // and which SwiftUI never owns - it is reparented between the on-device
        // container and an external display's window rather than recreated. This
        // retain is now the second reason it survives rather than the only one, and is
        // kept because the C++ side's ownership is still the thing that is wrong; the
        // real fix would have it own this lifetime properly.
        let surfacePtr = Unmanaged.passRetained(uiView).toOpaque()
        cemu_bridge_register_render_surface(surfacePtr, width, height, dpiScale)

        let romPath = game.romPath
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
            let mlcPath = documentsPath.appendingPathComponent("mlc").path
            try? FileManager.default.createDirectory(atPath: mlcPath, withIntermediateDirectories: true)

            cemu_bridge_log_checkpoint("launchGame: about to call engine.initialize() [background]")
            EmulationEngine.initializeBlocking(mlcPath: mlcPath)
            cemu_bridge_log_checkpoint("launchGame: engine.initialize() returned [background]")

            cemu_bridge_log_checkpoint("launchGame: about to call engine.boot() [background]")
            let status = EmulationEngine.bootBlocking(rpxPath: romPath)
            cemu_bridge_log_checkpoint("launchGame: engine.boot() returned [background]")

            await MainActor.run {
                guard let self else { return }
                engine.refreshStatus()
                self.lastStatusMessage = engine.statusText
                self.emulationState = (status == CEMU_BRIDGE_OK) ? .running : .error
                if self.emulationState == .running {
                    self.startFrameRateMonitor()
                }
            }
        }

        return true
    }
    #endif

    func stopEmulation() {
        stopFrameRateMonitor()
        emulationEngine?.stop()
        emulationState = .idle
        currentGame = nil
    }

    func getEmulationEngine() -> EmulationEngine? {
        return emulationEngine
    }

    /// Always nil, and correctly so: the native C++ Metal renderer presents straight
    /// into its own CAMetalLayer (added as a sublayer of the registered UIView by
    /// CreateMetalLayer(), MetalLayer.mm) and never hands a texture back across the
    /// bridge. This exists only for the Swift-side placeholder MTKView renderers
    /// (Rendering/MetalRenderer.swift and MetalView.swift's macOS path), which have
    /// nothing to draw as a result.
    func getFrameTexture() -> MTLTexture? {
        return nil
    }

    /// Real frame rate as measured by the emulator itself, refreshed by
    /// `startFrameRateMonitor()` below. Not a Swift-side estimate: the number comes
    /// from LattePerformanceMonitor via WindowSystem::UpdateWindowTitles().
    /// 0 means "not currently rendering", which is a true statement, not a placeholder.
    func getFrameRate() -> Int {
        return frameRate
    }

    /// The HUD used to call a getFrameRate() that returned a hardcoded 0, so it
    /// permanently read "0 FPS" no matter what the emulator was doing - worse than
    /// showing nothing, because it looked like a live measurement of a stalled
    /// emulator. Poll the bridge instead.
    ///
    /// 1s cadence deliberately: LattePerformanceMonitor only recomputes fps about
    /// once a second, so anything faster would just re-read the same value and churn
    /// SwiftUI. A Timer (rather than reading the bridge inline from `body`) is what
    /// makes the reading actually refresh - `body` is only re-evaluated when
    /// published state changes, which a plain function call cannot trigger.
    private func startFrameRateMonitor() {
        frameRateTimer?.invalidate()
        frameRateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let fps = Int(cemu_bridge_get_fps().rounded())
                if fps != self.frameRate {
                    self.frameRate = fps
                }
            }
        }
    }

    private func stopFrameRateMonitor() {
        frameRateTimer?.invalidate()
        frameRateTimer = nil
        frameRate = 0
    }
}

enum EmulationState {
    case idle
    case loading
    case running
    case paused
    case error
}
