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
    /// Refreshed alongside `frameRate`. See `EmulatorProgress` below for why a second
    /// source of frame information is not redundant with the first.
    @Published private(set) var progress = EmulatorProgress()
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

        // Same treatment for the keys folder, and for the same reason the Roms folder
        // gets it: a folder that does not exist is not a folder anyone can drop a file
        // into. This is the first code to run that touches Documents, so it is what
        // makes Documents/keys visible in the Files app on a fresh install, before any
        // game has been launched and before the engine has ever been initialized.
        WiiUKeys.ensureDirectoryExists()

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: romsPath,
                includingPropertiesForKeys: nil
            )

            var discoveredGames: [GameMetadata] = []

            for item in contents {
                // A Roms entry is either a single-file dump or a dumped game DIRECTORY.
                // For a directory the engine still boots an .rpx, but it must be the one
                // sitting inside code/ so Cemu sees the real layout next to it - boot it
                // from anywhere else and it falls back to standalone mode and logs
                // "incorrect layout or missing meta files", losing the title metadata.
                let gameID: String
                let bootPath: String
                // The dump directory, when the entry is one. Only a directory dump keeps
                // its meta/ on disk where the icon can be read from; a single-file dump
                // keeps meta/ inside the container, where only the engine can reach it.
                let dumpDirectory: URL?

                var isDirectory: ObjCBool = false
                _ = fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory)

                if isDirectory.boolValue {
                    guard Self.looksLikeWiiUDump(item),
                          let rpx = Self.executableInDump(item) else { continue }
                    gameID = item.lastPathComponent
                    bootPath = rpx.path
                    dumpDirectory = item
                } else {
                    let pathExtension = item.pathExtension.lowercased()
                    guard Self.supportedROMExtensions.contains(pathExtension) else { continue }
                    gameID = item.deletingPathExtension().lastPathComponent
                    bootPath = item.path
                    dumpDirectory = nil
                }

                let gameMetadata = GameMetadata(
                    id: gameID,
                    title: gameID,
                    romPath: bootPath,
                    coverPath: findCover(for: gameID, in: romsPath, dump: dumpDirectory),
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

    /// A dumped Wii U title is a directory containing code/, content/ and meta/.
    /// code/ is the one that actually matters (it holds the .rpx we boot); meta/ is
    /// required too because its absence is exactly what makes Cemu drop to standalone.
    static func looksLikeWiiUDump(_ directory: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        for required in ["code", "meta"] {
            let sub = directory.appendingPathComponent(required)
            guard fileManager.fileExists(atPath: sub.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return false
            }
        }
        return true
    }

    /// The .rpx inside a dump's code/ directory. Case matters on nothing here, but the
    /// extension does: code/ also holds .rpl libraries, which are not entry points.
    static func executableInDump(_ directory: URL) -> URL? {
        let codePath = directory.appendingPathComponent("code")
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: codePath,
            includingPropertiesForKeys: nil
        )) ?? []

        return entries
            .filter { $0.pathExtension.lowercased() == "rpx" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    /// Art for a game's card, in the order a person would expect it: whatever they put
    /// there themselves first, then the game's own icon out of the dump.
    ///
    /// Before this, only the first half existed - and nothing in the app ever wrote a
    /// `<gameID>_cover.png`, so every card fell through to the placeholder controller
    /// glyph no matter what was installed. The icon has been sitting inside every
    /// dumped title the whole time at meta/iconTex.tga.
    private func findCover(for gameID: String, in directory: URL, dump: URL?) -> String? {
        let fileManager = FileManager.default

        // A hand-placed cover wins. Someone who dropped a file in specifically to
        // override the icon should not be overruled by the icon.
        for ext in ["jpg", "jpeg", "png"] {
            let coverPath = directory.appendingPathComponent("\(gameID)_cover.\(ext)")
            if fileManager.fileExists(atPath: coverPath.path) {
                return coverPath.path
            }
        }

        if let dump = dump {
            return WiiUIcon.cachedIconPath(for: gameID, dump: dump, in: directory)
        }

        return nil
    }

    enum ROMImportError: LocalizedError {
        case invalidROM
        case notAWiiUDump(String)
        case accessDenied
        case copyFailed(Error)

        var errorDescription: String? {
            switch self {
            case .invalidROM:
                // Deliberately one fixed sentence rather than a per-reason variant. The
                // check runs against the copy we already made, and every way it can fail
                // - unsupported extension, supported extension over the wrong bytes -
                // means the same thing to the person holding the iPad.
                return "This is not a valid Wii U ROM format."
            case .notAWiiUDump(let name):
                return "\"\(name)\" doesn't look like a Wii U dump - a dumped game folder has code/, content/ and meta/ inside it."
            case .accessDenied:
                return "Couldn't access that file."
            case .copyFailed(let error):
                return "Couldn't copy the ROM: \(error.localizedDescription)"
            }
        }
    }

    /// .wux is the compressed dump format most Wii U rips are distributed in and was
    /// missing here, so importing one failed with "isn't a supported ROM format" even
    /// though the picker had happily handed it over.
    static let supportedROMExtensions: Set<String> = ["wux", "wud", "wua", "iso", "rpx"]

    /// Staging directory inside Documents/Roms. A single-file import lands here first
    /// and is only moved up into Roms/ once it has passed validation. Two reasons: a
    /// rejected import can never clobber an existing ROM that happens to share its
    /// filename, and the library scan can never catch a half-copied file mid-import.
    ///
    /// Leading dot so it reads as scratch space. loadGames() skips it regardless - a
    /// directory only counts as a game if it has code and meta subdirectories inside.
    private static let stagingDirectoryName = ".incoming"

    /// First count bytes of url, or nil if they cannot be read (missing, unreadable, or
    /// shorter than count). Only ever called on a file already copied into our own
    /// sandbox, so a failure here says something about the file, not about permissions.
    private static func fileMagic(at url: URL, count: Int = 4) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: count), data.count == count else {
            return nil
        }
        return data
    }

    /// Validates an already-copied ROM file.
    ///
    /// The extension check is mandatory: it is the only signal that exists for every
    /// format we accept. The magic-byte check is an extra gate applied ONLY where there
    /// is a signature worth betting an import on. An .rpx is a Nintendo-flavoured ELF
    /// and keeps the standard ELF e_ident (0x7F 45 4C 46) at offset 0; a .wux opens
    /// with the ASCII magic WUX0.
    ///
    /// A .wud, .wua or .iso passes on the extension alone, on purpose. There is no
    /// offset-0 signature for them reliable enough to reject a real dump over, and
    /// wrongly refusing one is a far worse failure than accepting a mislabelled file
    /// the engine will refuse a moment later anyway. So a renamed archive named
    /// game.rpx or game.wux is caught here; one named game.wud is not.
    static func isValidROMFile(at url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard supportedROMExtensions.contains(ext) else { return false }

        switch ext {
        case "rpx":
            return fileMagic(at: url) == Data([0x7F, 0x45, 0x4C, 0x46])
        case "wux":
            return fileMagic(at: url) == Data([0x57, 0x55, 0x58, 0x30])
        default:
            return true
        }
    }

    /// Copies a user-picked ROM (from .fileImporter, so source is a security-scoped
    /// URL outside our sandbox - Files app, iCloud Drive, another app share sheet)
    /// into Documents/Roms, then reloads the library so it shows up immediately.
    ///
    /// The order is the whole point. The picker now offers every file rather than a
    /// type-filtered list, because iOS has no built-in UTType for .rpx, .wux, .wud or
    /// .wua and any type filter therefore greys out precisely the files we want.
    /// That moves the whole burden of deciding what is a ROM onto this function, and it
    /// cannot be discharged against source: the security scope dies with the picker, and
    /// the magic bytes have to be read from somewhere we are still allowed to read.
    /// So the copy happens first, inside the scope, and the copy is what gets judged -
    /// and deleted again if it fails, leaving nothing behind.
    func importROM(from source: URL) async throws {
        // Security scope has to be claimed BEFORE anything reads the URL. For a folder
        // pick, the scope covers the whole tree, so the recursive copy below inherits
        // it - but only while the claim is held, hence the copy happening inside it.
        guard source.startAccessingSecurityScopedResource() else {
            throw ROMImportError.accessDenied
        }
        defer { source.stopAccessingSecurityScopedResource() }

        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory)
        guard exists else { throw ROMImportError.accessDenied }

        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw ROMImportError.accessDenied
        }

        // Documents/Roms is what loadGames() scans on every launch, so anything that
        // lands here is in the library after the next restart, not just this one.
        let romsPath = documentsPath.appendingPathComponent(romsDirectory)
        try? fileManager.createDirectory(at: romsPath, withIntermediateDirectories: true)

        let destination = romsPath.appendingPathComponent(source.lastPathComponent)

        if isDirectory.boolValue {
            // A dumped game is a directory, not a file, and it is the one case where
            // copy-then-validate is the wrong order: the structural check is free to run
            // against source, whereas copying first would mean recursively duplicating
            // whatever the user tapped - a 30 GB Downloads folder - before earning the
            // right to say no. Check, then copy.
            guard Self.looksLikeWiiUDump(source) else {
                throw ROMImportError.notAWiiUDump(source.lastPathComponent)
            }

            do {
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: source, to: destination)
            } catch {
                throw ROMImportError.copyFailed(error)
            }

            await loadGames()
            return
        }

        // Single file. Copy into staging first - still inside the security scope, which
        // is the only window in which source is readable at all - then validate what
        // actually landed, then promote it.
        let stagingPath = romsPath.appendingPathComponent(Self.stagingDirectoryName)
        try? fileManager.createDirectory(at: stagingPath, withIntermediateDirectories: true)
        let staged = stagingPath.appendingPathComponent(source.lastPathComponent)

        do {
            if fileManager.fileExists(atPath: staged.path) {
                try fileManager.removeItem(at: staged)
            }
            try fileManager.copyItem(at: source, to: staged)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw ROMImportError.copyFailed(error)
        }

        guard Self.isValidROMFile(at: staged) else {
            // Leave no orphans: the copy the user never asked to keep goes away before
            // the error message reaches them, so a rejected import changes nothing on
            // disk and the library looks exactly as it did a second earlier.
            try? fileManager.removeItem(at: staged)
            throw ROMImportError.invalidROM
        }

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            // Same volume, so this is a rename, not a second copy of the bytes.
            try fileManager.moveItem(at: staged, to: destination)
        } catch {
            try? fileManager.removeItem(at: staged)
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

            // After initialize, never before: the engine picks its own timebase default
            // from the CPU mode that launch actually got, and that decision is made
            // inside cemu_bridge_initialize(). This only overrides it when the user has
            // explicitly chosen a value, so someone who never opens Settings keeps the
            // default that was chosen with the CPU mode in hand.
            TimebaseScale.applyStoredChoiceIfAny()

            // Read here rather than only from the switches, because the engine reads both
            // of these once while a title starts and cannot see UserDefaults. A switch
            // that silently reverts on every relaunch is worse than no switch.
            //
            // The recompiler defaults OFF. It is reported to crash on device, and a crash
            // in the emulated CPU makes every other fault impossible to judge.
            cemu_bridge_set_recompiler_enabled(
                UserDefaults.standard.object(forKey: "muffin.cpu.recompiler") as? Bool ?? false)
            cemu_bridge_set_legacy_timebase(
                UserDefaults.standard.object(forKey: "muffin.cpu.legacyTimebase") as? Bool ?? false)
            cemu_bridge_set_async_shader_compile(
                UserDefaults.standard.object(forKey: "muffin.shaders.asyncCompile") as? Bool ?? true)

            cemu_bridge_log_checkpoint("launchGame: about to call engine.boot() [background]")
            let status = EmulationEngine.bootBlocking(path: romPath)
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
        #if os(iOS)
        // engine.stop() is CafeSystem::ShutdownTitle(), which reaches
        // LatteThread_Exit() and `delete renderer` - so every surface registered with
        // the C++ side is gone by the time this returns, and the router has to know
        // that or the next launch would try to reuse a view whose layer no longer has
        // an owner on the C++ side. Ordered after stop() deliberately: the views must
        // outlive the renderer, not the other way round.
        DisplayRouter.shared.titleStopped()
        #endif
        surfaceRegistered = false
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
                let snapshot = EmulatorProgress.read()
                if snapshot != self.progress {
                    self.progress = snapshot
                }
            }
        }
    }

    private func stopFrameRateMonitor() {
        frameRateTimer?.invalidate()
        frameRateTimer = nil
        frameRate = 0
        progress = EmulatorProgress()
    }
}

/// The engine's own progress counters, as the heartbeat measures them.
///
/// The reason this exists next to `frameRate` rather than replacing it: `frameRate`
/// comes from LattePerformanceMonitor, which reports whole frames per second. Every rate
/// this port has actually produced under the interpreter rounds to zero there, so the
/// HUD read "-- FPS" during runs that were genuinely rendering - the same readout it
/// shows for a title that has stopped dead. These counters tell those two apart, on the
/// device, without anyone exporting log.txt and mailing it anywhere.
struct EmulatorProgress: Equatable {
    var gx2InitReached: Bool = false
    var gx2FrameCount: UInt64 = 0
    /// Fractional on purpose. 0.4 frames per second is the answer, and rounding it to
    /// "0 FPS" destroys exactly the information being asked for.
    var gx2FramesPerSecond: Double = 0
    var osScreenScanouts: UInt64 = 0
    var guestFlipRequests: UInt32 = 0

    static func read() -> EmulatorProgress {
        var raw = CemuBridgeProgress()
        cemu_bridge_get_progress(&raw)
        return EmulatorProgress(
            gx2InitReached: raw.gx2_init_reached,
            gx2FrameCount: raw.gx2_frame_count,
            gx2FramesPerSecond: raw.gx2_frames_per_second,
            osScreenScanouts: raw.os_screen_scanouts,
            guestFlipRequests: raw.guest_flip_requests)
    }

    /// What the HUD shows, and the whole point of the struct: one short string that
    /// distinguishes slow from stuck.
    ///
    /// `wholeFramesPerSecond` is LattePerformanceMonitor's number and stays in charge
    /// whenever it is non-zero, so a build that reaches a normal frame rate reads exactly
    /// as it always did.
    func hudText(wholeFramesPerSecond: Int) -> String {
        if wholeFramesPerSecond > 0 {
            return "\(wholeFramesPerSecond) FPS"
        }
        if gx2FrameCount > 0 {
            // Running past the first frame, just below one frame per second. Show the
            // rate AND the count: the rate says how slow, the count is the thing whose
            // movement proves it is not stuck.
            if gx2FramesPerSecond > 0 {
                return String(format: "%.2f fps · %llu frames", gx2FramesPerSecond, gx2FrameCount)
            }
            return String(format: "%llu frames", gx2FrameCount)
        }
        if gx2InitReached {
            // Past handover with nothing drawn. This is the case that is a real bug
            // rather than a slow one, so it says so instead of showing a rate of zero.
            return "GX2 · no frames yet"
        }
        if osScreenScanouts > 0 || guestFlipRequests > 0 {
            return "Booting · \(osScreenScanouts) scanouts"
        }
        return "-- FPS"
    }
}

enum EmulationState {
    case idle
    case loading
    case running
    case paused
    case error
}
