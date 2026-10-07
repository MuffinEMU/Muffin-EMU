// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import Foundation
#if os(iOS)
import UIKit
#endif

#if os(iOS)

// Needs the iOS 27 SDK to compile. `#if compiler(>=6.4)` matches
// `PlatformCapabilities.SDK.hasIOS27`; on older toolchains this file is empty.
#if compiler(>=6.4)

/// Delegate for the external-display scene. `DisplayRouter` owns the window and layer;
/// this only tells it when a scene appears or disappears.
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

/// Registers an external-display scene accessory on iOS 27+, where the system no
/// longer offers those scenes automatically. Untested on hardware.
@available(iOS 27.0, *)
@MainActor
enum ExternalDisplaySceneAccessory {

    /// Held for the accessory's lifetime; dropping it unregisters the accessory.
    private static var registration: UISceneAccessoryRegistration?

    private static var isRegistered: Bool { registration != nil }

    /// Idempotent; safe to call on every mount.
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

    /// The scene's root view controller, which owns the accessory registration.
    private static func rootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let active = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return active?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? active?.windows.first?.rootViewController
    }
}

#endif // compiler(>=6.4)
#endif // os(iOS)
