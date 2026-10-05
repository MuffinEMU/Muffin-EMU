import Foundation
import Combine
#if os(iOS)
import UIKit
// CACurrentMediaTime() for the continuous-resize throttle. UIKit re-exports QuartzCore on
// iOS, so this is belt and braces - but the throttle breaks in a way that looks like a
// layout bug if it ever silently stops resolving, which is worth one explicit import.
import QuartzCore

/// Wii U TV/GamePad screen assignment when a genuine second display is connected
/// (`.dualScreen` in `DisplayRouter` below) - see `DisplaySettingsSection.swift` for the
/// Settings UI these keys back. Read directly from `UserDefaults` rather than
/// `@AppStorage`, because `DisplayRouter` is a plain class, not a View.
enum DisplayLayoutSettings {
    /// false (default): TV screen on the external display, GamePad screen on this
    /// device - how dual-screen was written and documented before this setting existed.
    /// true: swapped, GamePad on the external display, TV on this device.
    static let swapKey = "muffin.display.swapTVPad"
    static let defaultSwap = false

    /// Whether a small on-screen button appears during `.dualScreen` play to flip the
    /// setting above without leaving the game.
    static let showSwapButtonKey = "muffin.display.showSwapButton"
    static let defaultShowSwapButton = true
}

/// Master switch for the whole external-display system above, off by default. With it
/// off, `DisplayRouter.applyPlacement` never looks for a real external screen at all -
/// `placement` can only ever be `.deviceOnly`, exactly as if this feature did not exist,
/// regardless of what's actually plugged in. This is deliberately a separate, coarser
/// gate from `DisplayLayoutSettings` above: those two settings decide HOW a genuine
/// external display is used once the system is on; this decides whether the system runs
/// at all. Off by default because most players never connect a second display, dual-
/// screen output has not been exercised on real hardware yet (see DisplaySettingsSection's
/// footer), and a feature that is silently probing for hardware nobody has is more
/// surface area than a Wii U emulator needs turned on for everyone by default.
enum ExternalDisplaySystemSettings {
    static let enabledKey = "muffin.display.externalDisplaySystemEnabled"
    static let defaultEnabled = false
}

/// How the TV and GamePad screens share this device's own screen: single screen, both
/// screens, or both with a small GamePad in the top-right corner. Applies while `Placement`
/// is not `.dualScreen`. Stored under `muffin.display.screenLayout`.
enum ScreenLayout: String, CaseIterable, Identifiable {
    case singleScreen
    case bothScreens
    case smallGamePadTopRight

    var id: String { rawValue }

    var string: String {
        switch self {
        case .singleScreen: return "Single Screen"
        case .bothScreens: return "Adaptive (Both Screens)"
        case .smallGamePadTopRight: return "Both Screens (GamePad Top Right)"
        }
    }

    var description: String {
        switch self {
        case .singleScreen:
            return "Shows one screen at a time. Tap the swap button to switch between TV and GamePad."
        case .bothScreens:
            return "Shows both screens: stacked in portrait, side by side in landscape."
        case .smallGamePadTopRight:
            return "Shows the TV screen with a small GamePad screen in the top-right corner."
        }
    }

    var showsBothScreens: Bool { self != .singleScreen }

    /// The saved layout, or `.singleScreen` if none has been chosen.
    static var initialValue: ScreenLayout {
        UserDefaults.standard.string(forKey: LocalScreenLayoutSettings.layoutKey)
            .flatMap(ScreenLayout.init(rawValue:)) ?? .singleScreen
    }
}

/// Settings keys for `ScreenLayout` above. Deliberately its own small enum, distinct
/// from `DisplayLayoutSettings`, even though both back controls in the same Settings
/// section - `DisplayLayoutSettings` is about a genuine external display, this is about
/// arranging both Wii U screens on this one, and the two "swap button" features they
/// each carry are honestly different features that happen to share a name.
enum LocalScreenLayoutSettings {
    static let layoutKey = "muffin.display.screenLayout"
    static let defaultLayout = ScreenLayout.singleScreen

    /// Shown only while the layout is `.singleScreen`, the only layout where swapping means anything.
    static let showSwapButtonKey = "muffin.display.showLocalSwapButton"
    static let defaultShowSwapButton = true
}

/// A view whose own backing layer is a `CAMetalLayer`. The core renders into the
/// registered view's layer directly, so the TV and GamePad views must be this type.
final class MetalLayerView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
}

/// Decides which physical display each of the Wii U's two screens goes to, and keeps
/// that decision current while the app runs. Cemu keeps a separate `CAMetalLayer` for the TV
/// and the GamePad.
///
/// - `.dualScreen`: an external display is connected and the app has a `UIWindowScene` for it.
///   TV goes to the external display, GamePad stays on the device.
/// - `.deviceMirrored`: an external display is connected without a scene (plain screen
///   mirroring). The TV stays on the device and the GamePad screen is not rendered.
/// - `.deviceOnly`: no external display. TV on the device, GamePad screen not rendered.
///
/// "Not rendered" means no pad surface is registered, so the engine skips pad work
/// (`MetalRenderer::IsPadWindowActive()`). `.deviceOnly` is what runs on a plain iPad;
/// `.dualScreen` has not been tested with a display attached. The log records the placement.
@MainActor
final class DisplayRouter: ObservableObject {
    static let shared = DisplayRouter()

    enum Placement: Equatable {
        case deviceOnly
        case deviceMirrored
        case dualScreen
    }

    // @Published so the on-screen swap button (EmulatorViewOptimized) can show and hide
    // itself as placement changes, instead of polling or needing its own notification.
    @Published private(set) var placement: Placement = .deviceOnly

    /// Whether the GamePad screen is the one on the external display (swapped) rather
    /// than the TV screen (the default, and the only arrangement dual-screen originally
    /// shipped with). Only meaningful in `.dualScreen`; harmless to read otherwise.
    private var swapScreens: Bool {
        UserDefaults.standard.object(forKey: DisplayLayoutSettings.swapKey) as? Bool ?? DisplayLayoutSettings.defaultSwap
    }

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
        let view = MetalLayerView()
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

    /// The scale the GamePad surface was last sized at. Touches on the pad arrive in points and
    /// have to be converted in the same pixel space, so this is what ContentView multiplies by.
    private(set) var padSurfaceScale: Double = 1.0

    /// What the screen layout last asked to be visible on this device (TV, GamePad), so a pad
    /// surface that registers after that call is told instead of defaulting to "both".
    private var localVisibleOutputs: (tv: Bool, pad: Bool)?

    /// The plain SwiftUI-facing container `MetalViewIOS.makeUIView()` hands back, cached
    /// here instead of created fresh every call - see `sharedDeviceContainer()` below.
    private var sharedDeviceContainerStorage: UIView?

    /// The plain SwiftUI-facing container `PadMetalViewIOS.makeUIView()` hands back,
    /// cached for the same reason - see `sharedLocalPadContainer()` below, which is
    /// where the reasoning actually matters.
    private var sharedLocalPadContainerStorage: UIView?

    /// Returns the same `DeviceContainerView` on every call, creating it once on first
    /// use. `attach(deviceContainer:)`/`placeTVOnDevice()` already reparent the real,
    /// persistent `tvRenderView` into whatever container they're handed, regardless of
    /// whether it's a container they've seen before - so this container's own identity
    /// changing was never what put the TV screen at risk from a conditionally-mounted
    /// `MetalViewIOS`. It's cached anyway, for the same reason `tvRenderView` itself is:
    /// a SwiftUI-owned wrapper view that never changes identity is one less thing for a
    /// remount to have to recover from, and it keeps `MetalViewIOS` and `PadMetalViewIOS`
    /// symmetric - see `sharedLocalPadContainer()`, where an equivalent cache is not a
    /// nicety but the actual fix.
    func sharedDeviceContainer() -> UIView {
        if let existing = sharedDeviceContainerStorage { return existing }
        let container = DeviceContainerView()
        container.backgroundColor = .black
        sharedDeviceContainerStorage = container
        return container
    }

    /// Returns the same `PadContainerView` on every call, creating it once on first use.
    /// The pad surface is only created or released by `syncLocalPadSurface()`, not reparented,
    /// so a container that changed identity on remount left a live pad layer in a detached
    /// view and a black screen. A stable container avoids that.
    func sharedLocalPadContainer() -> UIView {
        if let existing = sharedLocalPadContainerStorage { return existing }
        let container = PadContainerView()
        container.backgroundColor = .black
        sharedLocalPadContainerStorage = container
        return container
    }

    /// The on-device area SwiftUI gives us (see `MetalViewIOS`). Weak: SwiftUI owns it.
    private weak var deviceContainer: UIView?

    /// The on-device area SwiftUI gives the GamePad screen (see `PadMetalViewIOS`) when
    /// `ScreenLayout` wants it visible on this device rather than nowhere or on a real
    /// external display. Weak for the same reason as `deviceContainer`. `nil` whenever
    /// no such view is currently mounted, which `syncLocalPadSurface()` treats as "the
    /// current ScreenLayout has nothing local to draw the pad into right now".
    private weak var localPadContainer: UIView?

    /// Whichever ScreenLayout is current, read fresh each time - this router does not
    /// cache it, the same reasoning as `swapScreens` above.
    private var screenLayout: ScreenLayout {
        (UserDefaults.standard.string(forKey: LocalScreenLayoutSettings.layoutKey))
            .flatMap(ScreenLayout.init(rawValue:)) ?? LocalScreenLayoutSettings.defaultLayout
    }

    private var externalWindow: UIWindow?
    private var observing = false
    private var tvSurfaceRegistered = false

    // Set for exactly the span of placeTVOnDevice()/placeTVOnExternalDisplay() that
    // removes tvRenderView from one superview and adds it to another. Both already
    // call resizeTVSurfaceIfRegistered() themselves right after settling the move
    // with a geometry they know is current; in case UIKit calls back into
    // deviceContainer's layoutSubviews() as a side effect of the addSubview/
    // removeFromSuperview calls below, this keeps that callback from racing the
    // deliberate resize with a view tree that has not finished moving.
    private var isReparentingTV = false

    // The last size deviceContainerDidLayout() actually acted on. UIKit calls
    // layoutSubviews() on every layout pass, not only the ones where the view's size
    // changed, and most passes have nothing to do with this container getting bigger
    // or smaller - without this check, ordinary layout churn would send a resize to
    // the GPU thread every time.
    private var lastDeviceContainerLayoutSize: CGSize?

    /// State for the continuous-resize throttle - see `deviceContainerDidLayout(_:)`.
    /// Only ever touched on the main actor, which this whole type is isolated to.
    private var pendingContainerResize: DispatchWorkItem?
    private var lastAppliedContainerResize: TimeInterval = 0

    /// Same dedup as `lastDeviceContainerLayoutSize`, for `localPadContainer`.
    private var lastLocalPadContainerLayoutSize: CGSize?

    private init() {}

    // MARK: - Lifecycle

    /// Idempotent. Called as early as the app can manage, so a display that is already
    /// attached at launch and one plugged in later go through exactly the same code.
    func startObserving() {
        guard !observing else { return }
        observing = true

        // On iOS 27 external-display scenes must be registered explicitly. See
        // ExternalDisplayScene.swift; compiled out on older SDKs.
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            ExternalDisplaySceneAccessory.registerIfNeeded()
        }
        #endif

        // Same entry point on purpose: this is called from MetalViewIOS.makeUIView(), so
        // thermal monitoring starts exactly when a render surface first exists and never
        // needs its own lifecycle. Idempotent, like everything else here.
        ThermalMonitor.shared.startObserving()

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

    /// Registers the TV surface with the engine and kicks off the boot: once per title
    /// launch, and idempotent within one (`titleStopped()` is what re-arms it). Kept
    /// here rather than in `MetalViewIOS` so that surface creation and display routing
    /// cannot disagree about which view the renderer is drawing into.
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
            width: cInt(geometry.size.width),
            height: cInt(geometry.size.height),
            dpiScale: geometry.scale
        ) else { return }

        tvSurfaceRegistered = true
        // The view above may have just been created by the `tvRenderView` accessor, in
        // which case it is not in any hierarchy yet. This one call places it AND syncs
        // the pad surface (a no-op outside .dualScreen, leaving the GamePad screen
        // unrendered, which is intended) - both go through applyPlacement so surface
        // creation and display routing can never disagree about which view is which.
        applyPlacement(reason: "the TV surface was registered")
        log("routing the Wii U TV screen to \(placement == .dualScreen && !swapScreens ? "the external display" : "this device") at \(cInt(geometry.size.width))x\(cInt(geometry.size.height)) points, \(geometry.scale)x scale (placement=\(placementName))")
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
        localVisibleOutputs = nil
        // Reset the layout-size caches with the views they describe, so the next launch's new
        // render views get their first resize.
        lastDeviceContainerLayoutSize = nil
        lastLocalPadContainerLayoutSize = nil
        // A trailing resize scheduled during a drag must not fire into a torn-down
        // surface - and its work item captures self, so leaving it pending would also
        // keep this alive past the point the views it resizes have gone.
        pendingContainerResize?.cancel()
        pendingContainerResize = nil
        lastAppliedContainerResize = 0
        // A thermal throttle left armed across a title stop would leave the user's Render
        // Scale permanently overwritten with battery saver.
        ThermalMonitor.shared.titleStopped()
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
        // The master switch: with the external-display system off, treat every call as
        // if no external screen exists, no matter what `externalScreen()` would actually
        // find. Everything below this line - `desired`, the placeTVOn*/sync* calls - is
        // the exact same logic that already handles "no external display" correctly
        // (including tearing an existing dualScreen session back down to deviceOnly if
        // the switch is flipped off mid-session), so gating the two lookups here is
        // enough to make the whole system inert; nothing downstream needs to know why
        // `external` came back nil.
        let systemEnabled = UserDefaults.standard.bool(forKey: ExternalDisplaySystemSettings.enabledKey)
        let external = systemEnabled ? externalScreen() : nil
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

        // Which Wii U screen goes to the external display. Only meaningful in
        // .dualScreen - the other two placements have nowhere to put a second screen at
        // all, so the GamePad screen stays unrendered exactly as it always did.
        let tvGoesExternal = !(desired == .dualScreen && swapScreens)

        switch desired {
        case .dualScreen:
            if let external, let scene {
                if tvGoesExternal {
                    placeTVOnExternalDisplay(screen: external, scene: scene)
                } else {
                    // Swapped: TV stays on this device, and the external window (built
                    // below for the GamePad screen) must not be torn down as an
                    // unwanted side effect of "TV isn't going there this time".
                    placeTVOnDevice(keepExternalWindow: true)
                }
            }
        case .deviceMirrored, .deviceOnly:
            placeTVOnDevice(keepExternalWindow: false)
        }

        // A pad surface already registered on the WRONG side of a placement change that
        // just crossed the dualScreen boundary (e.g. a real external display connecting
        // while ScreenLayout had a local pad up, or disconnecting while dualScreen had
        // one) - neither sync function below reparents an existing surface, they only
        // create one where there is none and release one that shouldn't exist. Forcing
        // a release here when the existing host disagrees with where `desired` wants
        // the pad lets whichever sync function actually applies recreate it fresh on
        // the right host, the same "release and let re-registration do the placing"
        // approach rerouteForScreenLayoutChange() already uses for the swap button.
        if cemu_bridge_has_pad_render_surface() {
            let padIsLocal = padRenderView?.superview === localPadContainer
            let padShouldBeLocal = tvSurfaceRegistered && desired != .dualScreen
            if padIsLocal != padShouldBeLocal {
                cemu_bridge_release_pad_render_surface()
                padRenderView?.isHidden = true
                padRenderView = nil
            }
        }

        syncPadSurface(tvGoesExternal: tvGoesExternal, external: external, scene: scene)
        // Only one of these two ever actually wants a pad surface at a time: this one
        // only acts outside .dualScreen, the one above only acts inside it, and
        // `desired` just became exactly one or the other.
        syncLocalPadSurface()

        if changed || !tvSurfaceRegistered {
            switch desired {
            case .dualScreen where tvGoesExternal:
                log("display change (\(reason)) -> placement=dualScreen: Wii U TV screen on the external display, GamePad screen on this device")
            case .dualScreen:
                log("display change (\(reason)) -> placement=dualScreen (swapped): Wii U GamePad screen on the external display, TV screen on this device")
            case .deviceMirrored:
                log("display change (\(reason)) -> placement=deviceMirrored: an external display is connected but this app has no window scene for it, which is what AirPlay/screen mirroring looks like from inside the app. The Wii U TV screen stays on this device and reaches the external display through the mirror; the GamePad screen is not rendered.")
            case .deviceOnly:
                log("display change (\(reason)) -> placement=deviceOnly: Wii U TV screen on this device, GamePad screen not rendered")
            }
        }
    }

    /// Re-applies the render scale to the live surfaces without waiting for a layout change.
    /// Does not go through `deviceContainerDidLayout(_:)`, which skips unchanged sizes.
    func reapplyRenderScale(reason: String) {
        resizeTVSurfaceIfRegistered()
        resizePadSurfaceIfRegistered()
        log("render scale re-applied: \(reason)")
    }

    /// Called after the screen-layout setting changes. Only re-routes a title already running in
    /// `.dualScreen`; otherwise the new value applies on the next launch. The pad surface is
    /// released and recreated on the new host rather than moved.
    func rerouteForScreenLayoutChange() {
        guard placement == .dualScreen else { return }
        if cemu_bridge_has_pad_render_surface() {
            cemu_bridge_release_pad_render_surface()
            padRenderView?.isHidden = true
            padRenderView = nil
        }
        applyPlacement(reason: "screen layout changed")
    }

    /// `DisplaySettingsSection`'s "Enable External Display System" toggle calls this on
    /// every flip, in both directions - unlike the settings above, there's no existing
    /// `placement == .dualScreen` session to matter only if it's currently active:
    /// turning the switch ON needs to notice a display that was already connected while
    /// it was off (nothing else will, since `applyPlacement`'s own guard skipped looking
    /// the whole time), and turning it OFF needs to tear an active dualScreen session
    /// back down to deviceOnly right away rather than waiting for the next screen-change
    /// notification that may never come.
    func reapplyForExternalDisplaySystemToggle() {
        applyPlacement(reason: "external display system toggled")
    }

    /// The on-screen swap button's action (EmulatorViewOptimized, gated on
    /// `DisplayLayoutSettings.showSwapButtonKey` and `placement == .dualScreen`). Unlike
    /// the Settings toggle, there is no `@AppStorage` binding to write the flipped value
    /// for it, so this writes it directly before re-routing - `@AppStorage` observes the
    /// same `UserDefaults` key, so Settings shows the change if opened afterward.
    func toggleScreenLayoutFromSwapButton() {
        UserDefaults.standard.set(!swapScreens, forKey: DisplayLayoutSettings.swapKey)
        rerouteForScreenLayoutChange()
    }

    private func placeTVOnDevice(keepExternalWindow: Bool) {
        guard let container = deviceContainer else { return }
        // Only place a view that already exists. Touching `tvRenderView` here would
        // create one between titles, which then gets adopted by the next launch's
        // registration without the router having decided anything about it.
        guard let tvRenderView = tvRenderViewStorage else { return }
        if tvRenderView.superview !== container {
            isReparentingTV = true
            tvRenderView.removeFromSuperview()
            tvRenderView.frame = container.bounds
            container.addSubview(tvRenderView)
            isReparentingTV = false
            resizeTVSurfaceIfRegistered()
        }
        if !keepExternalWindow, let externalWindow {
            externalWindow.isHidden = true
            self.externalWindow = nil
        }
    }

    private func placeTVOnExternalDisplay(screen: UIScreen, scene: UIWindowScene) {
        guard let host = externalDisplayHost(screen: screen, scene: scene) else { return }
        guard let tvRenderView = tvRenderViewStorage else { return }
        if tvRenderView.superview !== host {
            isReparentingTV = true
            tvRenderView.removeFromSuperview()
            tvRenderView.frame = host.bounds
            host.addSubview(tvRenderView)
            isReparentingTV = false
            resizeTVSurfaceIfRegistered()
        }
    }

    /// Mirrors `placeTVOnExternalDisplay` for the GamePad screen - used only when the
    /// screen layout is swapped. `externalWindow` is shared with the TV placement code:
    /// only one of the two Wii U screens is ever on it at a time, so there is one window
    /// to create or reuse regardless of which content ends up in it.
    private func placePadOnExternalDisplay(view: UIView, screen: UIScreen, scene: UIWindowScene) {
        guard let host = externalDisplayHost(screen: screen, scene: scene) else { return }
        if view.superview !== host {
            host.addSubview(view)
        }
    }

    /// Creates or reuses `externalWindow` for the given screen/scene and returns the
    /// plain `UIView` content should be added to. Shared by the TV and GamePad
    /// placement functions so the window itself is never duplicated.
    private func externalDisplayHost(screen: UIScreen, scene: UIWindowScene) -> UIView? {
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
        return externalWindow?.rootViewController?.view
    }

    /// Called by `DeviceContainerView.layoutSubviews()` (see `MetalView.swift`) every
    /// time the container `MetalViewIOS` returns settles into a real size: first
    /// layout, rotation, or - since `UIRequiresFullScreen` is not set in
    /// `project.yml` - an iPad Split View/Slide Over resize. Before this there was no
    /// `layoutSubviews`, `viewDidLayoutSubviews`, bounds observer or
    /// `traitCollectionDidChange` anywhere under `src/ios`, so the registered TV/pad
    /// surfaces kept whatever size `tvGeometry()`/`syncPadSurface()` read once at
    /// registration time for the rest of the session, however the real view around
    /// them changed shape afterwards.
    func deviceContainerDidLayout(_ container: UIView) {
        guard container === deviceContainer else { return }
        guard !isReparentingTV else { return }
        let size = container.bounds.size
        if let lastSize = lastDeviceContainerLayoutSize, lastSize == size { return }
        lastDeviceContainerLayoutSize = size

        // On iOS 27 an iPad app is continuously resizable, so this runs on every frame of a
        // Split View drag. Throttle the drawable reallocation: apply the first change at once and
        // always apply the final size afterwards.
        guard PlatformCapabilities.expectsContinuousIPadResize else {
            applyContainerResize()
            return
        }
        throttleContainerResize()
    }

    /// Minimum gap between applied resizes while a continuous drag is in progress. 1/8s
    /// is slow enough to stop per-frame drawable churn and fast enough that the picture
    /// still tracks the divider rather than snapping at the end.
    private static let continuousResizeInterval: TimeInterval = 0.125

    private func throttleContainerResize() {
        let now = CACurrentMediaTime()
        pendingContainerResize?.cancel()
        pendingContainerResize = nil

        if now - lastAppliedContainerResize >= Self.continuousResizeInterval {
            lastAppliedContainerResize = now
            applyContainerResize()
            return
        }

        // Always schedule the trailing call, even though a leading one may have just run:
        // the leading call used the size as it was THEN, and the drag has moved since.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingContainerResize = nil
            self.lastAppliedContainerResize = CACurrentMediaTime()
            // Re-read the container rather than trusting the size captured when this was
            // scheduled - by the time it fires the drag has almost certainly moved again,
            // and the whole point of the trailing call is to land on the CURRENT size.
            if let container = self.deviceContainer {
                self.lastDeviceContainerLayoutSize = container.bounds.size
            }
            self.applyContainerResize()
        }
        pendingContainerResize = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.continuousResizeInterval, execute: work)
    }

    private func applyContainerResize() {
        resizeTVSurfaceIfRegistered()
        resizePadSurfaceIfRegistered()
    }

    private func resizeTVSurfaceIfRegistered() {
        guard tvSurfaceRegistered else { return }
        // tvRenderView's autoresizingMask (set once, at creation - see `tvRenderView`
        // above) is meant to keep its frame tracking `deviceContainer`'s bounds on its
        // own, the same way it does for the pad's equivalent view. Setting it here too,
        // directly, removes any dependency on that actually firing for every path a
        // SwiftUI-hosted container's bounds can change through - a Single Screen switch
        // among them - rather than trusting it silently did. Cheap and idempotent when
        // the frame was already correct.
        if let container = deviceContainer, let tvRenderView = tvRenderViewStorage,
           tvRenderView.superview === container {
            tvRenderView.frame = container.bounds
        }
        let geometry = tvGeometry()
        cemu_bridge_resize_render_surface(
            cInt(geometry.size.width),
            cInt(geometry.size.height),
            geometry.scale,
            true
        )
    }

    /// Mirrors resizeTVSurfaceIfRegistered() for the GamePad surface. Called from
    /// deviceContainerDidLayout() and localPadContainerDidLayout(), and when render scale changes.
    private func resizePadSurfaceIfRegistered() {
        guard cemu_bridge_has_pad_render_surface() else { return }
        // Re-assert the frame; autoresizing alone is not reliable here.
        if let host = padRenderView?.superview {
            padRenderView?.frame = host.bounds
        }
        let geometry = padGeometry()
        // The bridge's pad resize ignores the scale it is given and sizes the drawable from the
        // layer's own contentsScale, which was fixed when the surface was registered. padGeometry()
        // can now return a different scale for a different size (PadSurfaceScale), and
        // ContentView.sendPadTouch multiplies touches by that scale, so bring the layer in step
        // first or the GamePad touchscreen lands off by the ratio of the two.
        if geometry.scale.isFinite, geometry.scale > 0,
           let layer = padRenderView?.layer as? CAMetalLayer,
           abs(Double(layer.contentsScale) - geometry.scale) > 0.001 {
            layer.contentsScale = CGFloat(geometry.scale)
        }
        cemu_bridge_resize_render_surface(
            cInt(geometry.size.width),
            cInt(geometry.size.height),
            geometry.scale,
            false
        )
    }

    /// The GamePad screen's equivalent of `tvGeometry()`. Reads straight off whichever
    /// view currently hosts `padRenderView` - the external window (dualScreen, swapped),
    /// `deviceContainer` (dualScreen, not swapped), or `localPadContainer` (ScreenLayout
    /// showing the pad on this device outside dualScreen) - rather than re-deriving
    /// which of those three applies from `placement`/`swapScreens`/`screenLayout` a
    /// second time here. One source of truth: whatever `padRenderView` is actually
    /// inside right now IS its geometry.
    private func padGeometry() -> (size: CGSize, scale: Double) {
        // The console's GamePad screen is 854x480, so its surface is capped at about twice that
        // across its long side (PadSurfaceScale) instead of following the TV's render scale.
        // At native scale on a 12.9-inch iPad that is 1708 pixels instead of 2732, per frame.
        guard let host = padRenderView?.superview else {
            let size = UIScreen.main.bounds.size
            let scale = PadSurfaceScale.scale(forPoints: size, renderScale: UIScreen.main.effectiveRenderScale)
            padSurfaceScale = scale
            return (size, scale)
        }
        let size = host.bounds.size == .zero ? UIScreen.main.bounds.size : host.bounds.size
        let renderScale = (host.window?.screen ?? UIScreen.main).effectiveRenderScale
        let scale = PadSurfaceScale.scale(forPoints: size, renderScale: renderScale)
        padSurfaceScale = scale
        return (size, scale)
    }

    /// Creates the GamePad surface when the placement calls for one and drops it when it
    /// does not, on whichever host (this device, or the external display) the current
    /// screen layout puts it on. Both directions go through the bridge, and the release
    /// is deferred to the GPU thread — see `cemu_bridge_release_pad_render_surface`.
    private func syncPadSurface(tvGoesExternal: Bool, external: UIScreen?, scene: UIWindowScene?) {
        guard tvSurfaceRegistered else { return }
        let wantPad = (placement == .dualScreen)
        let padGoesExternal = wantPad && !tvGoesExternal
        let havePad = cemu_bridge_has_pad_render_surface()

        if wantPad, !havePad {
            let view = MetalLayerView()
            view.backgroundColor = .black

            if padGoesExternal {
                guard let external, let scene else { return }
                placePadOnExternalDisplay(view: view, screen: external, scene: scene)
                view.frame = externalWindow?.bounds ?? .zero
            } else {
                guard let container = deviceContainer else { return }
                view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.frame = container.bounds
                container.addSubview(view)
            }
            padRenderView = view

            // Same reason `GameManager.registerRenderSurface` uses passRetained: the C++
            // side holds an ARC-invisible pointer into this view's layer tree from the
            // GPU thread. `padRenderView` above is a strong reference too, but it is
            // cleared on release, and the layer must outlive that.
            let surface = Unmanaged.passRetained(view).toOpaque()
            let geometry = padGeometry()
            cemu_bridge_register_pad_render_surface(surface, cInt(geometry.size.width), cInt(geometry.size.height), geometry.scale)
        } else if !wantPad, havePad {
            cemu_bridge_release_pad_render_surface()
            padRenderView?.isHidden = true
            padRenderView = nil
        }
    }

    // MARK: - On-device screen layout (ScreenLayout, independent of Placement)

    /// Called by `PadMetalViewIOS`, mirroring `attach(deviceContainer:)`. The container
    /// SwiftUI hands this is sized by the composition in `EmulatorViewOptimized` per the
    /// current `ScreenLayout` - single/both/inset - so this router never has to know
    /// which of those is active to place the pad correctly; it only has to put the
    /// surface in whatever container it was given and read that container's own size.
    func attachLocalPadContainer(_ container: UIView) {
        guard localPadContainer !== container else { return }
        localPadContainer = container
        syncLocalPadSurface()
    }

    /// `PadContainerView.layoutSubviews()`'s hook, mirroring
    /// `deviceContainerDidLayout(_:)` for the pad's own container - which can resize
    /// independently of `deviceContainer` (a rotation changes both differently in the
    /// side-by-side/stacked layout, and the inset layout's pad box is never the same
    /// size as the TV region next to it).
    func localPadContainerDidLayout(_ container: UIView) {
        guard container === localPadContainer else { return }
        let size = container.bounds.size
        if let lastSize = lastLocalPadContainerLayoutSize, lastSize == size { return }
        lastLocalPadContainerLayoutSize = size
        resizePadSurfaceIfRegistered()
    }

    /// Registers a pad surface hosted on `localPadContainer` whenever this device is
    /// showing both Wii U screens itself and no real external display is in the way -
    /// releases it otherwise. Placement, not ScreenLayout, decides whether the pad is
    /// visible at all in Single Screen mode; ScreenLayout and the swap button below only
    /// decide which of the two an ALREADY-registered pad/TV pair currently draws to,
    /// via `cemu_bridge_set_visible_outputs` - see `updateLocalVisibleOutputs(showTV:
    /// showPad:)`. Registering it unconditionally (rather than only once Single Screen
    /// has picked the pad) is what makes the swap button instant: there is never a
    /// surface to create or tear down when it is tapped, only which one is visible.
    private func syncLocalPadSurface() {
        let wantLocalPad = tvSurfaceRegistered && placement != .dualScreen
        let havePad = cemu_bridge_has_pad_render_surface()

        if wantLocalPad, !havePad, let container = localPadContainer {
            let view = MetalLayerView()
            view.backgroundColor = .black
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.frame = container.bounds
            container.addSubview(view)
            padRenderView = view

            let surface = Unmanaged.passRetained(view).toOpaque()
            let geometry = padGeometry()
            cemu_bridge_register_pad_render_surface(surface, cInt(geometry.size.width), cInt(geometry.size.height), geometry.scale)
            // Registering makes both outputs visible. Put back what the layout asked for, or the
            // TV-only layouts would keep drawing a GamePad surface nobody can see.
            let visible = localVisibleOutputs ?? (tv: true, pad: false)
            cemu_bridge_set_visible_outputs(visible.tv, visible.pad)
        } else if !wantLocalPad, havePad, padRenderView?.superview === localPadContainer {
            // The `padRenderView?.superview === localPadContainer` guard is what keeps
            // this from releasing a pad surface the OTHER sync function (dualScreen's)
            // just created on a different host in the same call to applyPlacement -
            // syncPadSurface() runs first and, if it just registered one, havePad here
            // would otherwise read true for a surface this function had no part in.
            cemu_bridge_release_pad_render_surface()
            padRenderView?.isHidden = true
            padRenderView = nil
        }
    }

    /// Called by the Single Screen swap button and layout change handlers. Switches which of the
    /// already-registered surfaces the renderer draws to. Releases held buttons when the pad
    /// screen is hidden so an in-flight press still sees its release.
    func updateLocalVisibleOutputs(showTV: Bool, showPad: Bool) {
        guard placement != .dualScreen else { return }
        localVisibleOutputs = (tv: showTV, pad: showPad)
        if !showPad { cemu_bridge_release_all_buttons() }
        cemu_bridge_set_visible_outputs(showTV, showPad)
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

    /// Called by `ExternalDisplaySceneDelegate` when the system connects or disconnects
    /// the non-interactive external scene the accessory asked for (iOS 27+).
    ///
    /// Routed through the same `applyPlacement(reason:)` every other trigger uses rather
    /// than doing placement work here. A scene arriving is exactly the condition
    /// `startObserving()`'s existing comment already anticipated - "a window scene for an
    /// external display can arrive after the screen itself does" - so this is one more
    /// notification into a path built for it, not a new mechanism.
    func externalSceneDidChange(reason: String) {
        applyPlacement(reason: reason)
    }

    private func externalWindowScene(for screen: UIScreen) -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.screen === screen }
    }

    /// Note the `effectiveRenderScale` rather than `scale`: the user's render-scale
    /// setting is applied here, once, at the single point where a backing scale is turned
    /// into a number the C++ side keeps. Everything downstream - `phys_width/phys_height`,
    /// the CAMetalLayer's drawable size, the Vulkan swapchain extent, the letterbox maths
    /// in `LatteRenderTarget_getScreenImageArea` - derives from this one value, so scaling
    /// it here scales all of them consistently and nothing else has to know the setting
    /// exists. See RenderScale.swift for what it does and does not change.
    private func tvGeometry() -> (size: CGSize, scale: Double) {
        // Only when the TV screen is actually the one on the external display - under a
        // swapped screen layout the TV stays on this device and falls through to the
        // device-container path below, same as .deviceOnly/.deviceMirrored.
        if placement == .dualScreen, !swapScreens, let window = externalWindow {
            return (window.bounds.size, window.screen.effectiveRenderScale)
        }
        // Size the layer from the container the emulator view actually occupies, not the whole
        // screen, and fall back to the screen size if SwiftUI has not laid it out yet.
        let containerSize = deviceContainer?.bounds.size ?? .zero
        let size = containerSize == .zero ? UIScreen.main.bounds.size : containerSize
        let scale = (deviceContainer?.window?.screen ?? UIScreen.main).effectiveRenderScale
        return (size, scale)
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

/// Points as a C int. `Int32(someDouble)` traps on NaN, infinity and out-of-range values, and a view that has not
/// been laid out yet can report any of them.
func cInt(_ value: CGFloat) -> Int32 {
    guard value.isFinite else { return 0 }
    return Int32(max(0, min(value, 100_000)))
}
