// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import MetalKit
#if os(iOS)
import UIKit
#endif

/// Plain `UIView` has no bounds-changed notification, so `layoutSubviews()` tells `DisplayRouter`
/// when the container settles into a new size (rotation, iPad Split View / Slide Over resize).
final class DeviceContainerView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        DisplayRouter.shared.deviceContainerDidLayout(self)
    }
}

struct MetalViewIOS: UIViewRepresentable {
    var gameManager: GameManager

    // Returns a plain container view; the view the C++ renderer draws into is
    // DisplayRouter.shared.tvRenderView, added as a subview. That lets DisplayRouter move the
    // TV screen between this device and an external display without destroying its CAMetalLayer.
    //
    // Plain UIView, not MTKView: MTKView would make its own layer an active CAMetalLayer, and
    // the C++ renderer's CAMetalLayer sublayer would then compete with it.
    func makeUIView(context: Context) -> UIView {
        // Returns the same container every time (see DisplayRouter.sharedDeviceContainer()).
        let container = DisplayRouter.shared.sharedDeviceContainer()

        // Arm display detection before registering, so a display connected at launch and one
        // plugged in later take the same path. Registering the surface starts the boot
        // (see GameManager.registerRenderSurface).
        DisplayRouter.shared.startObserving()
        DisplayRouter.shared.attach(deviceContainer: container)
        DisplayRouter.shared.registerSurfaces(with: gameManager)

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Fallback if makeUIView's registration didn't take; both calls are idempotent.
        DisplayRouter.shared.attach(deviceContainer: uiView)
        DisplayRouter.shared.registerSurfaces(with: gameManager)
    }
}

/// `MetalViewIOS`'s pad-screen equivalent (see `DisplayRouter.attachLocalPadContainer` /
/// `localPadContainerDidLayout`). Mounted by `EmulatorViewOptimized` when `ScreenLayout` shows
/// the GamePad screen on this device and `DisplayRouter.placement` is not `.dualScreen`. Safe to
/// mount and unmount repeatedly: `makeUIView()` returns the container `DisplayRouter` caches
/// (`sharedLocalPadContainer()`).
final class PadContainerView: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        DisplayRouter.shared.localPadContainerDidLayout(self)
    }
}

struct PadMetalViewIOS: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = DisplayRouter.shared.sharedLocalPadContainer()
        DisplayRouter.shared.attachLocalPadContainer(container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DisplayRouter.shared.attachLocalPadContainer(uiView)
    }
}
