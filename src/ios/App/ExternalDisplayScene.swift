import Foundation
#if os(iOS)
import UIKit
#endif

#if os(iOS)

// Everything below needs the iOS 27.0 SDK to COMPILE, not merely to run.
// `UISceneAccessory`, `UISceneAccessoryRegistration` and
// `UIViewController.registerSceneAccessory(_:)` do not exist in the iOS 26 SDK that CI
// currently builds against (`.github/workflows/build-ios-app.yml` selects Xcode 26.3),
// and `@available(iOS 27.0, *)` does not help with that: it gates when code may RUN,
// while a missing symbol is a compile error regardless of any availability check.
//
// `#if compiler(>=6.4)` is the toolchain gate - Swift 6.4 ships with the Xcode carrying
// the iOS 27 SDK - and it matches `PlatformCapabilities.SDK.hasIOS27`, deliberately, so
// there is one condition for "this build can see iOS 27 API" rather than two that could
// drift apart. On an older toolchain this whole file compiles to nothing and
// `DisplayRouter` takes the pre-27 path it always did.
#if compiler(>=6.4)

/// Delegate for the non-interactive external-display scene the system creates on our
/// behalf once `ExternalDisplaySceneAccessory` registers for one.
///
/// Deliberately does almost nothing. `DisplayRouter` already owns the entire question of
/// what goes on an external display - it finds the scene (`externalWindowScene(for:)`),
/// builds or reuses the window (`externalDisplayHost(screen:scene:)`), and reparents the
/// persistent `MetalLayerView` into it without destroying the CAMetalLayer the GPU thread
/// holds a bare pointer to. Duplicating any of that here would create a second owner for
/// a layer whose whole design is that it has exactly one.
///
/// So this exists only to be a valid `delegateClass` for the scene configuration, and to
/// poke the router when a scene appears or disappears so its existing
/// `applyPlacement(reason:)` re-runs against the new reality.
@available(iOS 27.0, *)
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene,
              willConnectTo session: UISceneSession,
              options connectionOptions: UIScene.ConnectionOptions) {
        DisplayRouter.shared.externalSceneDidChange(reason: "external scene connected")
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        DisplayRouter.shared.externalSceneDidChange(reason: "external scene disconnected")
    }
}

/// iOS 27 stopped handing out external-display scenes on its own.
///
/// From the iOS & iPadOS 27 release notes (177015874): in apps built with the 27.0 SDK,
/// `windowExternalDisplayNonInteractive` scenes "are no longer offered automatically by
/// the system"; an app must call `UIViewController.registerSceneAccessory(_:)` with a
/// `UISceneAccessory.externalNonInteractive` instance.
///
/// This matters here specifically because `DisplayRouter.externalWindowScene(for:)`
/// searches `UIApplication.shared.connectedScenes` for a window scene on the external
/// screen. If the system never offers one, that search returns nil forever and
/// `.dualScreen` silently degrades to `.deviceMirrored` - which is exactly the state
/// DisplayRouter's own doc comment already describes ("nobody has run this with a display
/// attached, and the app ships no external-display scene configuration, so in practice
/// `externalWindowScene(for:)` is expected to come back nil today"). On iOS 26 and
/// earlier that was an unshipped-configuration problem. On iOS 27 it is also an
/// unregistered-accessory problem, and this is the named API that fixes the second half.
///
/// Registering an accessory does not force a display to exist or change anything when
/// none is attached - it tells the system this app is willing to drive a non-interactive
/// external scene if one becomes available.
///
/// # Honesty about what this is and is not
///
/// This is **written against Apple's published signatures, not against a device.**
/// `UISceneAccessory.externalNonInteractive(sceneConfiguration:)` and
/// `UIViewController.registerSceneAccessory(_:) -> UISceneAccessoryRegistration` are the
/// real declarations. But `.dualScreen` has never been exercised on real hardware in this
/// project's history, so this makes a path that definitely could not work potentially
/// able to work. Do not read a successful build as a working external display.
@available(iOS 27.0, *)
@MainActor
enum ExternalDisplaySceneAccessory {

    /// The registration has to be held. It is the handle for the accessory's lifetime;
    /// dropping it on the floor is how this silently stops working later, in a way that
    /// looks exactly like the bug it was written to fix.
    private static var registration: UISceneAccessoryRegistration?

    private static var isRegistered: Bool { registration != nil }

    /// Idempotent - safe to call from anywhere, as often as you like. `DisplayRouter`
    /// calls it from `startObserving()`, which `MetalViewIOS.makeUIView()` already
    /// invokes on every mount, so there is no new lifecycle to get wrong.
    static func registerIfNeeded() {
        guard !isRegistered else { return }
        guard let host = rootViewController() else { return }

        let configuration = UISceneConfiguration(
            name: "MuffinEMU External Display",
            sessionRole: .windowExternalDisplayNonInteractive)
        configuration.delegateClass = ExternalDisplaySceneDelegate.self

        let accessory = UISceneAccessory.externalNonInteractive(sceneConfiguration: configuration)
        registration = host.registerSceneAccessory(accessory)
        cemu_bridge_log_line("iOS display: registered a non-interactive external-display scene accessory (iOS 27+)")
    }

    /// The foreground-active scene's root view controller. `registerSceneAccessory` is a
    /// `UIViewController` method, and this app is SwiftUI, so there is no view controller
    /// of ours to hang it on - the hosting controller the scene already owns is the
    /// honest one to use rather than manufacturing an empty controller purely to own a
    /// registration.
    private static func rootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return active?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? active?.windows.first?.rootViewController
    }
}

#endif // compiler(>=6.4)
#endif // os(iOS)
