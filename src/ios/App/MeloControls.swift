import SwiftUI
import Melo_Controller

/// Melo-Controller (github.com/stossy11/Melo-Controller) as an alternative on-screen pad,
/// behind Settings > On-screen Controls > "Use melo-controls".
///
/// This is the only file that imports the package. It defines very generic names
/// (ControllerView, ButtonView, Controller, Window, LayoutConfig), and keeping them out of
/// ContentView keeps them from ever colliding with MuffinEMU's own. Everything else sees
/// only MeloControlsOverlay and MeloControlsSetting.
///
/// Melo-Controller is GPL-3.0, and it is linked into every build whether or not the switch
/// is on - see the licence note in README.md.
enum MeloControlsSetting {
    static let storageKey = "muffin.pad.useMeloControls"
    static let defaultValue = false

    /// Drives Melo-Controller's own size key so buttons grow in place; a scaleEffect would
    /// move the clusters off screen.
    static let scaleKey = "On-ScreenControllerScale"
    static let defaultScale: Double = 1.0
    static let minScale: Double = 0.5
    static let maxScale: Double = 1.75

    /// Bumped by "Reset to default" so a live pad rebuilds from the cleared layout.
    static let layoutResetKey = "muffin.melo.layoutResetCount"

    /// Copies a game's saved button positions to its title-ID name, unless that one already exists. Copied rather than moved, so
    /// the file under the old name is still there if anything goes wrong.
    static func adoptLayout(from oldID: String, to newID: String) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent("controller_layouts")
        let old = folder.appendingPathComponent("\(oldID).json"), new = folder.appendingPathComponent("\(newID).json")
        guard FileManager.default.fileExists(atPath: old.path), !FileManager.default.fileExists(atPath: new.path) else { return }
        try? FileManager.default.copyItem(at: old, to: new)
    }

    /// Puts this game's button positions back to how Melo-Controller ships them, and the
    /// size with them. The package keeps positions in Documents/controller_layouts/<game
    /// id>.json (default.json with no game) and its LayoutManager isn't public, so this
    /// removes the file it would read.
    static func resetLayout(gameID: String?) {
        let name = gameID.map { $0.isEmpty ? "default.json" : "\($0).json" } ?? "default.json"
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let file = documents.appendingPathComponent("controller_layouts").appendingPathComponent(name)
            try? FileManager.default.removeItem(at: file)
        }
        let defaults = UserDefaults.standard
        defaults.set(defaultScale, forKey: scaleKey)
        defaults.set(defaults.integer(forKey: layoutResetKey) &+ 1, forKey: layoutResetKey)
    }
}

/// Melo-Controller's pad, drawn over the game in place of MuffinEMU's own.
struct MeloControlsOverlay: View {
    let gameID: String?
    let isEditing: Bool
    @AppStorage(MeloControlsSetting.layoutResetKey) private var layoutResetCount = 0

    var body: some View {
        Melo_Controller.ControllerView(
            controller: MeloControllerBridge.shared,
            isEditing: isEditing,
            gameId: gameID
        )
        // ControllerView reads isEditing and its layout once, into its own @State, so a
        // change to either (including a reset) has to rebuild it rather than update it.
        .id("\(isEditing)-\(layoutResetCount)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            // A press in flight when the pad goes away would otherwise stay held.
            cemu_bridge_release_all_buttons()
        }
    }
}

/// Receives Melo-Controller's presses and stick movement and hands them to the same bridge
/// calls MuffinEMU's own pad uses, so the engine cannot tell which pad is on screen.
final class MeloControllerBridge: Melo_Controller.Controller {
    static let shared = MeloControllerBridge()

    func buttonPressed(_ button: VirtualControllerButton) {
        send(button, pressed: true)
    }

    func buttonReleased(_ button: VirtualControllerButton) {
        send(button, pressed: false)
    }

    func joystickMoved(position: CGPoint, right: Bool) {
        // Melo-Controller reports screen coordinates, where down is positive (its own d-pad
        // stick sends up as -1). The bridge takes the console's convention, up positive.
        cemu_bridge_set_stick_axis(
            right ? CEMU_BRIDGE_STICK_RIGHT : CEMU_BRIDGE_STICK_LEFT,
            Float(position.x),
            Float(-position.y)
        )
    }

    private func send(_ button: VirtualControllerButton, pressed: Bool) {
        // The gear button is HOME: it opens the HOME menu (HomeMenu.swift) instead of reaching the bridge.
        if button.id == "guide" {
            HomeMenuRouter.shared.padHome(pressed: pressed)
            return
        }
        guard let mapped = Self.bridgeButtons[button.id] else { return }
        cemu_bridge_set_button_state(mapped, pressed)
    }

    // Melo-Controller's button ids, from its VirtualControllerButton, onto the Wii U
    // GamePad. "guide" is the gear button, which MuffinEMU treats as HOME (send() above routes it to the HOME menu).
    private static let bridgeButtons: [String: CemuBridgeButton] = [
        "A": CEMU_BRIDGE_BUTTON_A,
        "B": CEMU_BRIDGE_BUTTON_B,
        "X": CEMU_BRIDGE_BUTTON_X,
        "Y": CEMU_BRIDGE_BUTTON_Y,
        "leftShoulder": CEMU_BRIDGE_BUTTON_L,
        "rightShoulder": CEMU_BRIDGE_BUTTON_R,
        "leftTrigger": CEMU_BRIDGE_BUTTON_ZL,
        "rightTrigger": CEMU_BRIDGE_BUTTON_ZR,
        "start": CEMU_BRIDGE_BUTTON_PLUS,
        "back": CEMU_BRIDGE_BUTTON_MINUS,
        "guide": CEMU_BRIDGE_BUTTON_HOME,
        "leftStick": CEMU_BRIDGE_BUTTON_STICK_L,
        "rightStick": CEMU_BRIDGE_BUTTON_STICK_R,
        "dPadUp": CEMU_BRIDGE_BUTTON_UP,
        "dPadDown": CEMU_BRIDGE_BUTTON_DOWN,
        "dPadLeft": CEMU_BRIDGE_BUTTON_LEFT,
        "dPadRight": CEMU_BRIDGE_BUTTON_RIGHT,
    ]
}
