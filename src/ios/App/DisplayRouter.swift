import Foundation
import Combine
#if os(iOS)
import UIKit

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

/// How the TV and GamePad screens share THIS device's own screen - a true port of
/// MeloCafe's `ScreenLayout` (Common/Models/ScreenLayout.swift): same cases, same
/// wording, same `initialValue` migration shape, because this is literally that
/// feature and nothing here is invented. Independent of `DisplayRouter.Placement`
/// above, which is about routing to a genuine SECOND physical display - this instead
/// decides how the two Wii U screens are arranged on the ONE screen most people are
/// actually using, and only applies while `Placement` is not `.dualScreen` (a real
/// external display still takes the TV, exactly as before this feature existed).
///
/// One deliberate departure from MeloCafe's literal source: `initialValue` reads/writes
/// `LocalScreenLayoutSettings.layoutKey` ("muffin.display.screenLayout"), not MeloCafe's
/// bare "screenLayout" - every other MuffinEMU setting is namespaced `muffin.*`, and
/// this is the one place that convention actually matters (a bare "screenLayout" key
/// could collide with something else reading/writing UserDefaults directly).
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
            return "Only the selected screen renders. Use the swap button to switch between TV and GamePad."
        case .bothScreens:
            return "TV and GamePad automatically adjust: stacked in portrait and side by side in landscape."
        case .smallGamePadTopRight:
            return "A small GamePad appears at the top right in its own column beside the TV View."
        }
    }

    var showsBothScreens: Bool { self != .singleScreen }

    /// MeloCafe's own migration path from its pre-`ScreenLayout` era, when this was two
    /// separate booleans (`showBothScreens`/`smallGamePadTopRight`). MuffinEMU never had
    /// those keys - this feature is new here, not migrated from an older one - so in
    /// practice the `defaults.bool(forKey:)` reads below always come back `false` and
    /// this always lands on `.singleScreen` the first time. Ported anyway rather than
    /// simplified away: it costs nothing, it's the actual shape MeloCafe's own
    /// `EmulationView`/`SettingsView` initialize `screenLayout` from
    /// (`@AppStorage("screenLayout") private var screenLayout = ScreenLayout.initialValue`),
    /// and simplifying it here would be exactly the kind of "equivalent but hand-rewritten"
    /// substitution this port is deliberately avoiding.
    static var initialValue: ScreenLayout {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: LocalScreenLayoutSettings.layoutKey),
           let layout = ScreenLayout(rawValue: stored) {
            return layout
        }
        let layout: ScreenLayout = defaults.bool(forKey: "showBothScreens") ? (defaults.bool(forKey: "smallGamePadTopRight") ? .smallGamePadTopRight : .bothScreens) : .singleScreen
        defaults.set(layout.rawValue, forKey: LocalScreenLayoutSettings.layoutKey)
        return layout
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

    /// Shown only while `layoutKey` is `.singleScreen` - the only layout where exactly
    /// one of the two screens is on screen at a time and swapping which one means
    /// anything. On by default, matching MeloCafe.
    static let showSwapButtonKey = "muffin.display.showLocalSwapButton"
    static let defaultShowSwapButton = true
}

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
/// A view whose own backing layer is a `CAMetalLayer`. The core's window system renders
/// into the registered view's layer itself (Metal draws into it, MoltenVK builds its Vulkan
/// surface from it), so the TV and GamePad views must be this, not a plain `UIView` with a
/// sublayer added later.
final class MetalLayerView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
}

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
    /// This is the actual fix that makes it safe to mount `PadMetalViewIOS` the way
    /// MeloCafe's real `EmulationView` mounts its GamePad view: conditionally, via
    /// `ForEach(visibleScreens)`, added and removed from the tree as Screen Layout and
    /// the swap state change.
    ///
    /// Before this cache existed, `PadMetalViewIOS.makeUIView()` returned a brand new
    /// `PadContainerView()` on every call. `attachLocalPadContainer(_:)` only updates
    /// `localPadContainer` and re-runs `syncLocalPadSurface()` when the container it's
    /// handed is a genuinely different object; `syncLocalPadSurface()` in turn only ever
    /// CREATES a pad surface when none is registered yet, or RELEASES one when none
    /// should exist any more - it has no third branch that reparents an
    /// already-registered surface onto a newly-handed container (unlike
    /// `placeTVOnDevice()`, which explicitly checks `tvRenderView.superview !== container`
    /// and moves it every time). So the moment SwiftUI dropped `PadMetalViewIOS` from the
    /// tree - Screen Layout swapping away from showing the pad - and later re-added it,
    /// `attachLocalPadContainer` saw a container that was not `localPadContainer`, set it
    /// as the new one, `syncLocalPadSurface()` saw `havePad == true` already (the surface
    /// was still registered, just hosted in the OLD, now-detached container) and did
    /// nothing, and the live pad `CAMetalLayer` was left a subview of a container with no
    /// superview of its own - a silent black screen the next time the layout swapped back
    /// to showing the pad. That was the real, sole cause of the black-screen regression a
    /// literal port of MeloCafe's conditionally-mounted `ForEach` hit before.
    ///
    /// Caching the container here closes the gap at its actual source rather than
    /// teaching `syncLocalPadSurface()` a third branch: `makeUIView()` now hands back the
    /// same object every time, so `attachLocalPadContainer` never sees a "different"
    /// container to begin with, and the reparent-on-remount case above is simply never
    /// reached. `attach(deviceContainer:)`, `attachLocalPadContainer(_:)`,
    /// `syncPadSurface()` and `syncLocalPadSurface()` are unchanged - their own
    /// idempotent, ignore-if-already-attached logic is exactly what lets a stable,
    /// cached container flow through them unchanged.
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

    /// Same dedup as `lastDeviceContainerLayoutSize`, for `localPadContainer`.
    private var lastLocalPadContainerLayoutSize: CGSize?

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
            width: Int32(geometry.size.width),
            height: Int32(geometry.size.height),
            dpiScale: geometry.scale
        ) else { return }

        tvSurfaceRegistered = true
        // The view above may have just been created by the `tvRenderView` accessor, in
        // which case it is not in any hierarchy yet. This one call places it AND syncs
        // the pad surface (a no-op outside .dualScreen, leaving the GamePad screen
        // unrendered, which is intended) - both go through applyPlacement so surface
        // creation and display routing can never disagree about which view is which.
        applyPlacement(reason: "the TV surface was registered")
        log("routing the Wii U TV screen to \(placement == .dualScreen && !swapScreens ? "the external display" : "this device") at \(Int(geometry.size.width))x\(Int(geometry.size.height)) points, \(geometry.scale)x scale (placement=\(placementName))")
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
        // Both layout-size caches have to go with the views they describe. They exist to
        // skip redundant resizes while ONE set of surfaces is alive; they are not
        // statements about the container, which is process-lifetime-cached
        // (sharedDeviceContainer()) and keeps whatever size it already had across a title
        // stop. Leaving them set means the next launch's brand-new render views can be
        // met by `lastSize == size` on the very first layout pass and never get their
        // one resize - so launch #2 in a session behaves differently from launch #1 for
        // no reason visible at the call site. Separate from the MetalLayerHandle scale
        // bug; found while diagnosing it.
        lastDeviceContainerLayoutSize = nil
        lastLocalPadContainerLayoutSize = nil
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

    /// Called after `DisplaySettingsSection`'s own `@AppStorage` binding has already
    /// written the new screen-layout value - this only re-routes a title that's
    /// already running in `.dualScreen`; outside that placement the new value simply
    /// takes effect the next time one starts, and there's nothing to move yet.
    ///
    /// The pad surface is released first rather than reparented in place: unlike
    /// `tvRenderView`, which `placeTVOnDevice`/`placeTVOnExternalDisplay` already know
    /// how to move between hosts while live, the pad surface has only ever been
    /// created or torn down whole, never moved. Releasing it here and letting
    /// `applyPlacement` -> `syncPadSurface` recreate it fresh on the new host reuses
    /// that already-correct creation path instead of adding a third, parallel "move"
    /// path for one setting.
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
            Int32(geometry.size.width),
            Int32(geometry.size.height),
            geometry.scale,
            true
        )
    }

    /// Mirrors resizeTVSurfaceIfRegistered() for the GamePad surface. The only caller
    /// today is deviceContainerDidLayout(): a registered pad surface is always
    /// hosted on this device (syncPadSurface() below only ever creates one in
    /// .dualScreen, where the TV moves to the external display and the pad stays
    /// here), so it is sized from the same container as the TV surface and needs the
    /// same layout-triggered resize.
    private func resizePadSurfaceIfRegistered() {
        guard cemu_bridge_has_pad_render_surface() else { return }
        // Same defensive direct sync as resizeTVSurfaceIfRegistered() now does for
        // tvRenderView, applied here too even though the report that started that fix
        // was TV-only: padRenderView's frame is set once, at creation, exactly the same
        // way tvRenderView's was, and nothing else here re-asserts it on an ordinary
        // resize - it was relying on the same autoresizingMask-alone assumption that
        // turned out not to be trustworthy for the TV. Costs nothing when the frame was
        // already correct.
        if let host = padRenderView?.superview {
            padRenderView?.frame = host.bounds
        }
        let geometry = padGeometry()
        cemu_bridge_resize_render_surface(
            Int32(geometry.size.width),
            Int32(geometry.size.height),
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
        guard let host = padRenderView?.superview else {
            return (UIScreen.main.bounds.size, UIScreen.main.effectiveRenderScale)
        }
        let size = host.bounds.size == .zero ? UIScreen.main.bounds.size : host.bounds.size
        let scale = (host.window?.screen ?? UIScreen.main).effectiveRenderScale
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
            cemu_bridge_register_pad_render_surface(surface, Int32(geometry.size.width), Int32(geometry.size.height), geometry.scale)
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
            cemu_bridge_register_pad_render_surface(surface, Int32(geometry.size.width), Int32(geometry.size.height), geometry.scale)
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

    /// `EmulatorViewOptimized`'s Single Screen swap button and its `.onChange(of:)`
    /// handlers for `screenLayout`/local-swap state call this - it only ever changes
    /// which of the two ALREADY-registered surfaces (see `syncLocalPadSurface()` above)
    /// the renderer actually draws to, via `cemu_bridge_set_visible_outputs`, the same
    /// register-once/toggle-visibility split MeloCafe's own `updateVisibleOutputs()`
    /// uses. Releases every held button when the pad screen is the one being hidden -
    /// same reasoning as the edit-layout toggle button already uses
    /// (`cemu_bridge_release_all_buttons()`): a press in flight on a screen about to
    /// disappear would otherwise never see its release.
    func updateLocalVisibleOutputs(showTV: Bool, showPad: Bool) {
        guard placement != .dualScreen else { return }
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
        // This used to return UIScreen.main.bounds unconditionally - the WHOLE
        // screen, including the header bar area that is not part of
        // `deviceContainer` (the area MetalViewIOS actually carves out for the
        // emulator view - see MetalView.swift). CreateMetalLayer() sizes the TV
        // CAMetalLayer from this value and adds it as a sublayer of tvRenderView,
        // which IS sized to deviceContainer (placeTVOnDevice() below sets
        // `tvRenderView.frame = container.bounds`). CALayer does not clip an
        // oversized sublayer, and the shipping SwiftUI path did not call .clipped()
        // either, so a sublayer taller than the view hosting it simply rendered past
        // that view's - and the screen's - bottom edge. The letterboxing inside that
        // sublayer (LatteRenderTarget_getScreenImageArea) was never the problem; it
        // was centering the image correctly inside a canvas that was the wrong size.
        //
        // Same `bounds == .zero ? screen : bounds` fallback syncPadSurface() already
        // uses below, and for the same reason: this runs from registerSurfaces(),
        // called from MetalViewIOS.makeUIView() before SwiftUI has necessarily laid
        // deviceContainer out, and boot depends on registration happening at all
        // rather than waiting for a nonzero size. Kept deliberately.
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
