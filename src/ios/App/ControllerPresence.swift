import SwiftUI
import GameController

/// Whether a physical game controller is connected, by the same test the bridge uses to pick the
/// one it drives the GamePad with (an extended gamepad). Read-only: the bridge owns the
/// controller's handlers (CemuBridge.mm), and this only looks.
enum ControllerPresence {
    /// `excluding` is for a disconnect notification, which can arrive while the departing controller is still listed.
    static func isConnected(excluding departing: GCController? = nil) -> Bool {
        GCController.controllers().contains { $0 !== departing && $0.extendedGamepad != nil }
    }
}

/// Tells the emulator view when to hide or show the on-screen pad because a controller came or
/// went. One modifier so the view's body does not grow another stack of observers.
///
/// `apply(hide, atStart)`: `hide` is the state the pad should be in, `atStart` is true for the
/// reading taken when the game view appears and false for a connect, a disconnect or the setting
/// changing.
struct ControllerAutoHideModifier: ViewModifier {
    @AppStorage(ControllerLayoutSettings.autoHideWithControllerKey)
    private var autoHide = ControllerLayoutSettings.defaultAutoHideWithController
    let apply: (_ hide: Bool, _ atStart: Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { evaluate(departing: nil, atStart: true) }
            .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { _ in
                evaluate(departing: nil, atStart: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { note in
                evaluate(departing: note.object as? GCController, atStart: false)
            }
            .onChange(of: autoHide) { _ in evaluate(departing: nil, atStart: false) }
    }

    private func evaluate(departing: GCController?, atStart: Bool) {
        apply(autoHide && ControllerPresence.isConnected(excluding: departing), atStart)
    }
}
