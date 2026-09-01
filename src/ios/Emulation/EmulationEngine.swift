import Foundation

/// Thin, honest wrapper over the real Cemu C++ engine via `CemuBridge`.
///
/// This intentionally does NOT contain an emulator. All emulation is delegated to
/// the genuine Cemu core through the C bridge. Until the core is compiled for iOS
/// (see ROADMAP.md M1), `coreAvailable` is false and boots report the truthful
/// "engine not built yet" state instead of faking execution.
///
/// The previous `WiiUCPU`/`MemoryManager` Swift toy is retired and no longer used.
@MainActor
final class EmulationEngine: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var currentGame: String = ""
    @Published private(set) var statusText: String = ""

    /// True only when the real Cemu engine is compiled and linked into this build.
    let coreAvailable: Bool

    init() {
        coreAvailable = cemu_bridge_core_available()
        statusText = String(cString: cemu_bridge_status_text())
    }

    /// Initialize the engine with the app-sandbox MLC/NAND path.
    func initialize(mlcPath: String) {
        EmulationEngine.initializeBlocking(mlcPath: mlcPath)
        statusText = String(cString: cemu_bridge_status_text())
    }

    /// Boot whatever was picked - an encrypted disc image, a Wii U archive, a dumped
    /// game folder, or a standalone homebrew `.rpx`. Returns the real bridge status.
    @discardableResult
    func boot(path: String) -> CemuBridgeStatus {
        currentGame = URL(fileURLWithPath: path).lastPathComponent
        let status = EmulationEngine.bootBlocking(path: path)
        isRunning = cemu_bridge_is_title_running()
        statusText = String(cString: cemu_bridge_status_text())
        return status
    }

    /// Raw, non-actor-isolated entry points for the two bridge calls that do real
    /// (potentially slow, and historically hang-prone on iOS - see the M2 boot-freeze
    /// investigation) engine work. `initialize`/`boot` above call these directly on
    /// whatever actor they're invoked from (@MainActor by default, since this class
    /// is @MainActor) - fine for callers that are OK blocking the main thread, but
    /// GameManager's real launch path calls these `nonisolated` versions from a
    /// detached background task instead, precisely so a slow interpreter boot (or
    /// any future bug in it) can't freeze the UI no matter how the C++ side behaves.
    /// Must not be called concurrently with any other EmulationEngine bridge call.
    nonisolated static func initializeBlocking(mlcPath: String) {
        mlcPath.withCString { cemu_bridge_initialize($0) }
    }

    nonisolated static func bootBlocking(path: String) -> CemuBridgeStatus {
        path.withCString { cemu_bridge_boot_title($0) }
    }

    /// Number of decryption keys the engine can currently read out of keys.txt.
    ///
    /// This is the engine's own count, not a Swift re-parse of the file: it is the only
    /// answer that means anything, because it is the same parser that will be asked to
    /// open a disc image. 0 means no usable keys, which is a perfectly normal state -
    /// homebrew needs none.
    ///
    /// Only meaningful once initializeBlocking() has run, since keys.txt is resolved
    /// against the user data path that establishes. Returns -1 before then, and -1 in a
    /// build without the core - "cannot answer", which is deliberately not the same
    /// value as 0. Zero is a real answer about a real file that holds no usable keys, so
    /// a caller that collapsed the two would report "no keys" for a keys.txt it had
    /// simply never looked at.
    nonisolated static func reloadAndCountKeys() -> Int {
        Int(cemu_bridge_reload_and_count_keys())
    }

    /// Refreshes published state from the bridge's (fast, non-blocking) getters.
    /// Call after a background bootBlocking()/initializeBlocking() completes.
    func refreshStatus() {
        isRunning = cemu_bridge_is_title_running()
        statusText = String(cString: cemu_bridge_status_text())
    }

    func pause() {
        cemu_bridge_pause()
        isRunning = cemu_bridge_is_title_running()
    }

    func resume() {
        cemu_bridge_resume()
        isRunning = cemu_bridge_is_title_running()
    }

    func stop() {
        cemu_bridge_shutdown_title()
        isRunning = cemu_bridge_is_title_running()
        statusText = String(cString: cemu_bridge_status_text())
    }

    deinit {
        cemu_bridge_shutdown_title()
    }
}
