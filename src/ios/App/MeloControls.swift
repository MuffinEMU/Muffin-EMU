import SwiftUI
import Melo_Controller

/// Melo-Controller (github.com/stossy11/Melo-Controller) as an alternative on-screen pad,
/// behind Settings > On-screen Controls > "Use melo-controls". It is stossy11's touch
/// controller, the one MeloCafe ships: its own button art, layout editor and per-game layouts.
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

    /// Melo-Controller's own layout editor moves and resizes individual buttons; it has
    /// no control for scaling the WHOLE pad evenly, which is what this key backs -
    /// applied as one `.scaleEffect` around the pad as a whole in MeloControlsOverlay
    /// below, the same "one AppStorage key, one slider in the in-game panel" shape
    /// ControllerLayoutSettings.scaleKey already uses for MuffinEMU's own pad.
    static let scaleKey = "muffin.pad.meloControlsScale"
    static let defaultScale: Double = 1.0
    static let minScale: Double = 0.5
    static let maxScale: Double = 1.75
}

/// Melo-Controller's pad, drawn over the game in place of MuffinEMU's own.
struct MeloControlsOverlay: View {
    let gameID: String?
    let isEditing: Bool

    @AppStorage(MeloControlsSetting.scaleKey) private var scale = MeloControlsSetting.defaultScale

    var body: some View {
        Melo_Controller.ControllerView(
            controller: MeloControllerBridge.shared,
            isEditing: isEditing,
            gameId: gameID
        )
        // ControllerView reads isEditing once, into its own @State, so a change has to
        // rebuild it rather than update it.
        .id(isEditing)
        // Scales the whole pad evenly around its own center, on top of whatever
        // Melo-Controller's own layout editor already positioned - a uniform view
        // transform rather than a setting Melo-Controller itself exposes, so it works
        // the same regardless of how any individual button was moved or resized.
        // SwiftUI scales hit-testing along with the visuals, so touch targets grow and
        // shrink with what's drawn rather than drifting out of registration with it.
        .scaleEffect(scale)
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
        guard let mapped = Self.bridgeButtons[button.id] else { return }
        cemu_bridge_set_button_state(mapped, pressed)
    }

    // Melo-Controller's button ids, from its VirtualControllerButton, onto the Wii U
    // GamePad. "guide" is the gear button, which MuffinEMU treats as HOME.
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
