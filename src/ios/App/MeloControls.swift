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

    /// Melo-Controller's OWN size key, driven directly rather than wrapped.
    ///
    /// This used to be a MuffinEMU key backing a `.scaleEffect` around the whole pad, and
    /// that is the wrong tool for the job: scaleEffect multiplies the coordinate system,
    /// so every button's POSITION scales along with its size. Turning the slider up did
    /// not just make the buttons bigger, it pushed the left cluster further left and the
    /// right cluster further right until the outer ones ran off the screen - which is
    /// exactly what was reported. Clipping to the screen was papering over it: the parts
    /// that left the screen were cropped away rather than brought back.
    ///
    /// Melo-Controller already has the right knob. Every ButtonView and JoystickView in
    /// the package reads `@AppStorage("On-ScreenControllerScale")` and multiplies it into
    /// its own frame only (ButtonView.swift: `baseWidth * deviceMultiplier *
    /// scaleMultiplier`), while the gaps between them are literal stack spacings the
    /// scale never touches. So the buttons grow and shrink in place, the spacing stays
    /// put, and the clusters - pinned to the screen edges by Spacers - grow inward
    /// instead of off the edge.
    ///
    /// Pointing our own slider straight at that key rather than syncing two keys means
    /// there is one number, it is the one the package actually reads, and it also moves
    /// when Melo-Controller's own layout editor changes it. Hit-testing follows for free:
    /// these are real frames, not a transform, so touch targets are the buttons.
    static let scaleKey = "On-ScreenControllerScale"
    static let defaultScale: Double = 1.0
    static let minScale: Double = 0.5
    static let maxScale: Double = 1.75
}

/// Melo-Controller's pad, drawn over the game in place of MuffinEMU's own.
struct MeloControlsOverlay: View {
    let gameID: String?
    let isEditing: Bool

    var body: some View {
        Melo_Controller.ControllerView(
            controller: MeloControllerBridge.shared,
            isEditing: isEditing,
            gameId: gameID
        )
        // ControllerView reads isEditing once, into its own @State, so a change has to
        // rebuild it rather than update it.
        .id(isEditing)
        // No .scaleEffect here any more, and no .clipped() to contain one. The size
        // slider writes Melo-Controller's own "On-ScreenControllerScale" instead, which
        // every ButtonView and JoystickView in the package multiplies into its own frame
        // - so the pad resizes itself from the inside and nothing has to be cropped to
        // keep it on screen. See MeloControlsSetting.scaleKey for why the transform was
        // the wrong tool.
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
