import Foundation
#if os(iOS)
import UIKit

/// Decides which physical display each of the Wii U's two screens goes to, and keeps
/// that decision current while the app runs.
///
/// The Wii U has two outputs: the TV and the GamePad (DRC). Cemu models them as two
/// windows, and the Metal renderer keeps a separate `CAMetalLayer` for each. Desktop
/// Cemu lets the user open a second OS window for the GamePad; on iOS the only way to
/// genuinely show two screens at once is a second physical display, so that is what
/// this watches for.
///
/// Three placements, and the log always says which one is in force and why:
///
/// - `.dualScreen` — an external display is connected AND the app has a `UIWindowScene`
///   for it, so we can own a window there. TV goes to the external display, GamePad
///   stays on the device. Both Cemu windows get a real layer.
/// - `.deviceMirrored` — an external display is connected but the app has no scene for
///   it, which is what plain AirPlay/screen mirroring looks like from inside the app:
///   the system is already copying the device's screen to the TV, and the app is not
///   given a separate drawing surface. The TV screen stays on the device (and reaches
///   the TV through the mirror). The GamePad screen is not rendered.
/// - `.deviceOnly` — no external display. TV screen on the device, GamePad screen not
///   rendered.
///
/// **"Not rendered" means no pad surface is registered at all**, not a surface that
/// fails. `MetalRenderer::IsPadWindowActive()` is exactly "the pad layer exists", and
/// every renderer entry point that touches the pad window now tests it first, so the
/// engine skips that work instead of reaching `AcquireDrawable()` and finding nothing.
/// That is the whole point of routing this from one place: there is no configuration
/// in which a Cemu window exists without a layer behind it.
///
/// **What is verified and what is not.** Detection and the `.deviceOnly` path are what
/// runs on a plain iPad and are exercised every launch. The `.dualScreen` path is
/// written against the real UIKit API but has never been exercised — nobody has run
/// this with a display attached, and the app ships no external-display scene
/// configuration, so in practice `externalWindowScene(for:)` is expected to come back
/// nil today and the router to land on `.deviceMirrored`. The log line says which
/// branch was taken; do not assume dual-screen works until a device log shows
/// `placement=dualScreen`.
@MainActor
final class DisplayRouter {
    static let shared = DisplayRouter()

    enum Placement: Equatable {
        case deviceOnly
        case deviceMirrored
        case dualScreen
    }

    private(set) var placement: Placement = .deviceOnly

    /// The view the C++ renderer's TV `CAMetalLayer` is a sublayer of.
    ///
    /// One per title launch, not one per process. Within a session it is never
    /// rebuilt - moving the TV screen between displays reparents THIS VIEW rather than
    /// destroying and recreating its layer, so `MetalLayerHandle`'s bare,
    /// ARC-invisible pointer stays valid and there is no teardown for the GPU thread to
    /// race. Across launches it has to be replaced, because `LatteThread_Exit()`
    /// deletes the renderer on title shutdown and takes the layer's C++ handle with it;
    /// reusing the view would stack the next launch's CAMetalLayer on top of the dead
    /// one. `titleStopped()` drops it, and the old view stays alive anyway thanks to the
    /// passRetained in GameManager - which is what keeps the dead layer from being
    /// deallocated out from under anything still holding it.
    private var tvRenderViewStorage: UIView?

    var tvRenderView: UIView {
        if let existing = tvRenderViewStorage {
            return existing
        }
        let view = UIView()
        view.backgroundColor = .black
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tvRenderViewStorage = view
        return view
    }

    /// Host for the GamePad screen, created only when there is somewhere real to show
    /// it. Never reused after a release: `cemu_bridge_release_pad_render_surface()`
    /// only drops the C++ side's retain and deliberately leaves the dead layer as a
    /// sublayer, so a fresh view is the honest way to get a clean one. That leaks one
    /// small view per connect/disconnect cycle, which is the same bounded trade
    /// `CreateMetalLayer()` already documents.
    private var padRenderView: UIView?

    /// The on-device area SwiftUI gives us (see `MetalViewIOS`). Weak: SwiftUI owns it.
    private weak var deviceContainer: UIView?

    private var externalWindow: UIWindow?
    private var observing = false
    private var tvSurfaceRegistered = false

    private init() {}

    // MARK: - Lifecycle

    /// Idempotent. Called as early as the app can manage, so a display that is already
    /// attached at launch and one plugged in later go through exactly the same code.
    func startObserving() {
        guard !observing else { return }
        observing = true

        // A window scene for an external display can arrive after the screen itself
        // does, so UIScene.didActivateNotification is in the list too: a screen-connect
        // notification alone is not enough to conclude that dual-screen is impossible.
        //
        // The observers hop through `Task { @MainActor }` rather than
        // MainActor.assumeIsolated, which needs iOS 17 and would not compile against
        // this target's iOS 15 floor even though the queue really is the main one.
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIScreen.didConnectNotification,
            UIScreen.didDisconnectNotification,
            UIScreen.modeDidChangeNotification,
            UIScene.didActivateNotification,
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                let noteName = note.name
                Task { @MainActor in
                    DisplayRouter.shared.handleScreenChange(noteName)
                }
            }
        }

        log("display routing armed; \(describeScreens())")
    }

    /// Called by `MetalViewIOS`. Takes over placement of `tvRenderView`. Safe to call on
    /// every SwiftUI update pass - it does nothing unless the container really changed,
    /// so it cannot churn the layer tree or spam the log.
    func attach(deviceContainer container: UIView) {
        guard deviceContainer !== container else { return }
        deviceContainer = container
        applyPlacement(reason: "the emulator view mounted")
    }

    /// Registers the TV surface with the engine and kicks off the boot, exactly once.
    /// Kept here rather than in `MetalViewIOS` so that surface creation and display
    /// routing cannot disagree about which view the renderer is drawing into.
    func registerSurfaces(with gameManager: GameManager) {
        guard !tvSurfaceRegistered else { return }

        let geometry = tvGeometry()

        // GameManager owns the "register once, then boot" gate and will refuse unless a
        // game is actually loading. Take its answer rather than assuming: setting the
        // flag optimistically would leave this router convinced a TV surface exists when
        // none does, and syncPadSurface() would then start attaching a second layer to a
        // renderer that has no first one.
        guard gameManager.registerRenderSurface(
            uiView: tvRenderView,
            width: Int32(geometry.size.width),
            height: Int32(geometry.size.height),
            dpiScale: geometry.scale
        ) else { return }

        tvSurfaceRegistered = true
        // The view above may have just been created by the `tvRenderView` accessor, in
        // which case it is not in any hierarchy yet.
        applyPlacement(reason: "the TV surface was registered")
        log("routing the Wii U TV screen to \(placement == .dualScreen ? "the external display" : "this device") at \(Int(geometry.size.width))x\(Int(geometry.size.height)) points, \(geometry.scale)x scale (placement=\(placementName))")

        // Only meaningful in .dualScreen; in the other two placements this is a no-op
        // and the engine is left with no pad window at all, which is the intended
        // "GamePad screen not rendered" state.
        syncPadSurface()
    }

    /// Called when a title stops. `CafeSystem::ShutdownTitle()` -> `LatteThread_Exit()`
    /// deletes the renderer, so every surface this router registered is gone on the C++
    /// side and the next launch must build fresh ones. Views are only detached, never
    /// released: the C++ retain taken at registration outlives them deliberately, and
    /// the dead CAMetalLayer must keep an owner so nothing deallocates it late.
    func titleStopped() {
        tvRenderViewStorage?.removeFromSuperview()
        tvRenderViewStorage = nil
        padRenderView?.removeFromSuperview()
        padRenderView = nil
        externalWindow?.isHidden = true
        externalWindow = nil
        tvSurfaceRegistered = false
        log("title stopped; render surfaces will be rebuilt on the next launch")
    }

    // MARK: - Placement

    private var placementName: String {
        switch placement {
        case .deviceOnly: return "deviceOnly"
        case .deviceMirrored: return "deviceMirrored"
        case .dualScreen: return "dualScreen"
        }
    }

    private func handleScreenChange(_ name: Notification.Name) {
        applyPlacement(reason: "\(name.rawValue); \(describeScreens())")
    }

    private func applyPlacement(reason: String) {
        let external = externalScreen()
        let scene = external.flatMap { externalWindowScene(for: $0) }

        let desired: Placement
        if external != nil && scene != nil {
            desired = .dualScreen
        } else if external != nil {
            desired = .deviceMirrored
        } else {
            desired = .deviceOnly
        }

        let changed = desired != placement
        placement = desired

        switch desired {
        case .dualScreen:
            if let external, let scene {
                placeTVOnExternalDisplay(screen: external, scene: scene)
            }
        case .deviceMirrored, .deviceOnly:
            placeTVOnDevice()
        }

        syncPadSurface()

        if changed || !tvSurfaceRegistered {
            switch desired {
            case .dualScreen:
                log("display change (\(reason)) -> placement=dualScreen: Wii U TV screen on the external display, GamePad screen on this device")
            case .deviceMirrored:
                log("display change (\(reason)) -> placement=deviceMirrored: an external display is connected but this app has no window scene for it, which is what AirPlay/screen mirroring looks like from inside the app. The Wii U TV screen stays on this device and reaches the external display through the mirror; the GamePad screen is not rendered.")
            case .deviceOnly:
                log("display change (\(reason)) -> placement=deviceOnly: Wii U TV screen on this device, GamePad screen not rendered")
            }
        }
    }

    private func placeTVOnDevice() {
        guard let container = deviceContainer else { return }
        // Only place a view that already exists. Touching `tvRenderView` here would
        // create one between titles, which then gets adopted by the next launch's
        // registration without the router having decided anything about it.
        guard let tvRenderView = tvRenderViewStorage else { return }
        if tvRenderView.superview !== container {
            tvRenderView.removeFromSuperview()
            tvRenderView.frame = container.bounds
            container.addSubview(tvRenderView)
            resizeTVSurfaceIfRegistered()
        }
        if let externalWindow {
            externalWindow.isHidden = true
            self.externalWindow = nil
        }
    }

    private func placeTVOnExternalDisplay(screen: UIScreen, scene: UIWindowScene) {
        if externalWindow?.screen !== screen {
            externalWindow?.isHidden = true
            externalWindow = nil
        }
        if externalWindow == nil {
            let window = UIWindow(windowScene: scene)
            window.frame = screen.bounds
            window.backgroundColor = .black
            let root = UIViewController()
            root.view.backgroundColor = .black
            window.rootViewController = root
            window.isHidden = false
            externalWindow = window
        }
        guard let host = externalWindow?.rootViewController?.view else { return }
        guard let tvRenderView = tvRenderViewStorage else { return }
        if tvRenderView.superview !== host {
            tvRenderView.removeFromSuperview()
            tvRenderView.frame = host.bounds
            host.addSubview(tvRenderView)
            resizeTVSurfaceIfRegistered()
        }
    }

    private func resizeTVSurfaceIfRegistered() {
        guard tvSurfaceRegistered else { return }
        let geometry = tvGeometry()
        cemu_bridge_resize_render_surface(
            Int32(geometry.size.width),
            Int32(geometry.size.height),
            geometry.scale,
            true
        )
    }

    /// Creates the GamePad surface when the placement calls for one and drops it when it
    /// does not. Both directions go through the bridge, and the release is deferred to
    /// the GPU thread — see `cemu_bridge_release_pad_render_surface`.
    private func syncPadSurface() {
        guard tvSurfaceRegistered else { return }
        let wantPad = (placement == .dualScreen)
        let havePad = cemu_bridge_has_pad_render_surface()

        if wantPad, !havePad, let container = deviceContainer {
            let view = UIView(frame: container.bounds)
            view.backgroundColor = .black
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(view)
            padRenderView = view

            // Same reason `GameManager.registerRenderSurface` uses passRetained: the C++
            // side holds an ARC-invisible pointer into this view's layer tree from the
            // GPU thread. `padRenderView` above is a strong reference too, but it is
            // cleared on release, and the layer must outlive that.
            let surface = Unmanaged.passRetained(view).toOpaque()
            let size = container.bounds.size == .zero ? UIScreen.main.bounds.size : container.bounds.size
            let scale = Double(container.window?.screen.scale ?? UIScreen.main.scale)
            cemu_bridge_register_pad_render_surface(surface, Int32(size.width), Int32(size.height), scale)
        } else if !wantPad, havePad {
            cemu_bridge_release_pad_render_surface()
            padRenderView?.isHidden = true
            padRenderView = nil
        }
    }

    // MARK: - Screen discovery

    /// `UIScreen.screens` is soft-deprecated in favour of scene APIs, but it is the only
    /// call that still reports a mirrored display, which is precisely the case being
    /// detected here — a mirrored screen produces no scene, so a scene-only search would
    /// conclude there is no TV at all. Deployment target is iOS 15, where this is the
    /// documented API anyway.
    private func externalScreen() -> UIScreen? {
        UIScreen.screens.first { $0 !== UIScreen.main }
    }

    private func externalWindowScene(for screen: UIScreen) -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.screen === screen }
    }

    private func tvGeometry() -> (size: CGSize, scale: Double) {
        if placement == .dualScreen, let window = externalWindow {
            return (window.bounds.size, Double(window.screen.scale))
        }
        // Deliberately the screen's bounds, not the container's, for the on-device case.
        // The container is frequently still CGRectZero when this first runs, and boot
        // waits on registration happening at all — the reasoning is spelled out in
        // MetalViewIOS.makeUIView and has not changed.
        return (UIScreen.main.bounds.size, Double(UIScreen.main.scale))
    }

    private func describeScreens() -> String {
        let parts = UIScreen.screens.map { screen -> String in
            let role = screen === UIScreen.main ? "main" : (screen.mirrored != nil ? "external (mirroring this device)" : "external")
            return "\(role) \(Int(screen.bounds.width))x\(Int(screen.bounds.height))@\(screen.scale)x"
        }
        return "screens: [\(parts.joined(separator: ", "))]"
    }

    private func log(_ message: String) {
        cemu_bridge_log_line("iOS display: " + message)
    }
}
#endif
