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

    /// Boot a standalone `.rpx`. Returns the real bridge status.
    @discardableResult
    func boot(rpxPath: String) -> CemuBridgeStatus {
        currentGame = URL(fileURLWithPath: rpxPath).lastPathComponent
        let status = EmulationEngine.bootBlocking(rpxPath: rpxPath)
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

    nonisolated static func bootBlocking(rpxPath: String) -> CemuBridgeStatus {
        rpxPath.withCString { cemu_bridge_boot_rpx($0) }
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
