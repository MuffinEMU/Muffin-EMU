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
