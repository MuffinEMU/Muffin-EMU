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

    /// Called by MetalViewIOS's Coordinator once its view has real, nonzero bounds,
    /// while emulationState == .loading. Registers the render surface (fast, safe to
    /// run synchronously on the calling - main - thread: sets a few WindowSystem
    /// fields and constructs the renderer, doesn't touch the GPU thread), then runs
    /// the actual init/boot on a detached background task so a slow interpreter boot -
    /// or any bug in it - can't freeze the UI, regardless of how well-behaved the C++
    /// side turns out to be.
    #if os(iOS)
    func registerRenderSurface(uiView: UIView, width: Int32, height: Int32, dpiScale: Double) {
        guard emulationState == .loading, !surfaceRegistered,
              let game = currentGame, let engine = emulationEngine else { return }
        surfaceRegistered = true

        // passRetained, not passUnretained - deliberately, permanently leaking this
        // one MTKView for the app's lifetime. Confirmed via a live device SIGSEGV
        // inside MetalRenderer::BeginFrame() -> AcquireDrawable() -> nextDrawable():
        // CreateMetalLayer() (MetalLayer.mm) adds the real CAMetalLayer as a sublayer
        // of this view's CALayer, and the C++ side (MetalLayerHandle) holds a bare,
        // ARC-invisible `CA::MetalLayer*` to it with no retain of its own. If SwiftUI
        // ever tears down and recreates this UIViewRepresentable's underlying MTKView
        // (it's free to do this on essentially any view-hierarchy change, e.g. the
        // .loading -> .running transition removing the "Booting..." overlay), an
        // unretained view here means the view - and therefore its layer, and
        // therefore our sublayer - gets deallocated while the GPU thread still holds
        // a raw pointer to it, and the very next draw call reads freed memory.
        // Retaining forever is a small, deliberate one-object bring-up cost, not a
        // real leak risk (one MTKView per app run) - correct enough for now; the
        // real fix would have the C++ side own this lifetime properly.
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
            }
        }
    }
    #endif

    func stopEmulation() {
        emulationEngine?.stop()
        emulationState = .idle
        currentGame = nil
    }

    func getEmulationEngine() -> EmulationEngine? {
        return emulationEngine
    }

    /// No frames are produced until the native Metal renderer is wired (ROADMAP.md M3).
    func getFrameTexture() -> MTLTexture? {
        return nil
    }

    func getFrameRate() -> Int {
        return 0
    }
}

enum EmulationState {
    case idle
    case loading
    case running
    case paused
    case error
}
