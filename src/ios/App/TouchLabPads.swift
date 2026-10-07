//
// Everything MuffinEMU needs to offer the TouchLab control styles (Zone, Float, Adaptive,
// Frame) alongside its own pad and Melo-Controller. Written against MuffinEMU/Muffin-EMU
// release/v6.4 @ 4e7223af; see integration/INTEGRATION.md for the ContentView / Settings /
// PadDiagnostics edits that wire it in.
//
// This is the only file that imports TouchLabCore / TouchLabUI. Keeping the imports here
// keeps the package's type names (TouchPad, PadButton, ...) out of ContentView.

import SwiftUI
import TouchLabCore
import TouchLabUI

/// Settings for the TouchLab control styles.
///
/// The TouchLab styles are OPTIONS. MuffinEMU's own pad stays the default: an empty
/// `schemeKey` means "not using TouchLab". Making a TouchLab style the default later is a
/// one-value change to `defaultScheme` (see INTEGRATION.md, "Promoting a style to the
/// default") - deliberately not done yet.
enum TouchLabSettings {
    /// "" (off - MuffinEMU's own pad) or a TouchLab scheme id: "zone", "float",
    /// "adaptive", "frame".
    static let schemeKey = "muffin.pad.touchlabScheme"
    static let defaultScheme = ""

    /// Float's right side: "stick" (floating camera stick) or "swipe".
    static let floatCameraKey = "muffin.touchlab.float.camera"
    static let defaultFloatCamera = FloatPad.Camera.stick.rawValue

    /// Racing's two options: hold A for the player, and steer by turning the device.
    static let racingAutoAccelerateKey = "muffin.touchlab.racing.autoAccelerate"
    static let racingTiltKey = "muffin.touchlab.racing.tilt"

    /// Zone's option: A about 1.4 times its size.
    static let zoneLargeAKey = "muffin.touchlab.zone.largeA"

    /// Bumped by "Reset Adaptive layout" so the live pad rebuilds from the cleared data.
    static let adaptiveResetKey = "muffin.touchlab.adaptive.resetCount"

    /// Adaptive's learned positions are per game - different games, different grips.
    static func adaptiveKey(gameID: String?) -> String {
        "muffin.touchlab.adaptive." + (gameID ?? "default")
    }

    static let schemes: [SchemeInfo] = SchemeCatalog.all

    static func isTouchLab(_ id: String) -> Bool {
        schemes.contains { $0.id == id }
    }

    static func name(_ id: String) -> String {
        schemes.first { $0.id == id }?.name ?? "MuffinEMU"
    }

    /// Moves what Adaptive learned for a game from its file-name key to its title-ID key, unless the title-ID key already has data.
    static func adoptAdaptiveKey(from oldID: String, to newID: String) {
        let d = UserDefaults.standard
        let old = adaptiveKey(gameID: oldID), new = adaptiveKey(gameID: newID)
        guard let learned = d.string(forKey: old), d.object(forKey: new) == nil else { return }
        d.set(learned, forKey: new)
        d.removeObject(forKey: old)
    }

    /// Clears Adaptive's learning for one game and tells a live pad to rebuild.
    static func resetAdaptive(gameID: String?) {
        let d = UserDefaults.standard
        d.removeObject(forKey: adaptiveKey(gameID: gameID))
        d.set(d.integer(forKey: adaptiveResetKey) &+ 1, forKey: adaptiveResetKey)
    }

    /// Clears Adaptive's learning for every game (for Settings, where no game is open).
    static func resetAdaptiveAll() {
        let d = UserDefaults.standard
        let prefix = adaptiveKey(gameID: "")
        for key in d.dictionaryRepresentation().keys where key.hasPrefix(prefix) && key != adaptiveResetKey {
            d.removeObject(forKey: key)
        }
        d.set(d.integer(forKey: adaptiveResetKey) &+ 1, forKey: adaptiveResetKey)
    }

    /// A style as a picker shows it, so the Settings and layout-panel UI needn't import
    /// the package.
    struct Style: Identifiable {
        let id: String
        let name: String
        let summary: String
    }

    static let styles: [Style] = schemes.map { Style(id: $0.id, name: $0.name, summary: $0.summary) }

    static func summary(_ id: String) -> String {
        styles.first { $0.id == id }?.summary ?? ""
    }

    static let floatStyleID = FloatPad.schemeInfo.id
    static let adaptiveStyleID = AdaptivePad.schemeInfo.id
    static let zoneStyleID = ZonePad.schemeInfo.id
    static let racingStyleID = RacingPad.schemeInfo.id

    /// Styles whose sticks sit in fixed places, so the stick-spacing setting can move them.
    /// Float's sticks appear under the thumb and Frame's live in its side columns.
    static func hasFixedSticks(_ id: String) -> Bool {
        id == zoneStyleID || id == adaptiveStyleID
    }

    /// Styles whose shoulders sit in a fixed place the shoulder-offset setting can move.
    /// Float's are bands whose height is part of its design, and Frame's live in its columns.
    static func hasMovableShoulders(_ id: String) -> Bool {
        id == zoneStyleID || id == adaptiveStyleID
    }

    /// Float's right-hand side options: stored value and label.
    static let cameraOptions: [(value: String, title: String)] = [
        (FloatPad.Camera.stick.rawValue, "Floating stick"),
        (FloatPad.Camera.swipe.rawValue, "Swipe"),
    ]
}

/// The TouchLab pad's output, straight onto the bridge.
///
/// TouchLab's PadMixer has already paired every press with its release and dropped
/// repeats, so this is a pass-through. PadDiagnostics is fed with the same labels the
/// other pads use, so the diagnostics overlay reads the same whichever pad is live.
///
/// NEVER make these callbacks write @State of EmulatorViewOptimized (or anything the pad
/// is rendered inside): that rebuilds the pad under the finger and releases every press -
/// the exact bug that kept the preview pad dead. PadDiagnostics is safe because only its
/// own overlay observes it.
///
/// Main-actor isolated, like PadDiagnostics and DisplayRouter, which it talks to directly.
/// `@preconcurrency` lets it satisfy PadOutput, which isn't isolated: every call comes from
/// TouchPadView's touch handlers and lifecycle observers, all on the main thread.
@MainActor
final class CemuBridgePadOutput: @preconcurrency PadOutput {
    static let shared = CemuBridgePadOutput()

    /// The GamePad VIEW's size in points - set by TouchLabPadOverlay whenever the screen
    /// layout changes. Touches are sent the way padScreen's own DragGesture sends them:
    /// a position inside that view, times the effective render scale.
    var gamepadViewSize: CGSize = .zero

    func setButton(_ button: PadButton, pressed: Bool) {
        PadDiagnostics.shared.recordInput(Self.label(button), pressed)
        // HOME is the app's, not the game's: it opens the HOME menu (HomeMenu.swift) and never reaches
        // the bridge, whose GamePad mapping has no HOME bit. Intercepted here so the vendored TouchLab
        // package stays as it is.
        if button == .home {
            HomeMenuRouter.shared.padHome(pressed: pressed)
            return
        }
        cemu_bridge_set_button_state(Self.bridgeButton(button), pressed)
    }

    func setStick(_ stick: PadStick, _ value: StickValue) {
        // StickValue is already the console's convention (+y up) - no negation here.
        PadDiagnostics.shared.recordStick(stick.rawValue, CGPoint(x: value.x, y: value.y))
        cemu_bridge_set_stick_axis(stick == .left ? CEMU_BRIDGE_STICK_LEFT : CEMU_BRIDGE_STICK_RIGHT,
                                   Float(value.x), Float(value.y))
    }

    /// Where the last touch was, in the GamePad surface's pixels. The lift is reported at this spot
    /// rather than at (0, 0): the core keeps a touch that began and ended between two reads of the
    /// GamePad (a tap) and answers it with the position of the LAST report, so a lift at (0, 0) turned
    /// such a tap into one on the top-left corner of the GamePad screen. padScreen's own touch path
    /// sends the lift at the finger's position for the same reason.
    private var lastTouchPixel: (x: Double, y: Double)?

    func setTouchscreen(_ point: CGPoint?) {
        guard let point, gamepadViewSize.width > 0, gamepadViewSize.height > 0 else {
            if let last = lastTouchPixel {
                cemu_bridge_set_pad_touch(last.x, last.y, false)
                lastTouchPixel = nil
            } else {
                cemu_bridge_set_pad_touch(0, 0, false)
            }
            return
        }
        // The GamePad surface is sized at its own scale (capped, and not the TV's render
        // scale or the screen's), and the core wants touches in that surface's pixels. Read
        // live from the same place padScreen's own touch path reads it, every touch: it
        // changes whenever the surface is re-sized.
        let scale = DisplayRouter.shared.padSurfaceScale
        let x = Double(point.x * gamepadViewSize.width) * scale
        let y = Double(point.y * gamepadViewSize.height) * scale
        lastTouchPixel = (x, y)
        cemu_bridge_set_pad_touch(x, y, true)
    }

    func releaseAll() {
        cemu_bridge_release_all_buttons()
        lastTouchPixel = nil
        cemu_bridge_set_pad_touch(0, 0, false)
    }

    /// Explicit rather than rawValue-cast: PadButton's raw values do equal
    /// CemuBridgeButton's, but a switch keeps a future renumbering on either side a
    /// compile-visible change instead of a silent wrong button.
    static func bridgeButton(_ b: PadButton) -> CemuBridgeButton {
        switch b {
        case .a: return CEMU_BRIDGE_BUTTON_A
        case .b: return CEMU_BRIDGE_BUTTON_B
        case .x: return CEMU_BRIDGE_BUTTON_X
        case .y: return CEMU_BRIDGE_BUTTON_Y
        case .l: return CEMU_BRIDGE_BUTTON_L
        case .r: return CEMU_BRIDGE_BUTTON_R
        case .zl: return CEMU_BRIDGE_BUTTON_ZL
        case .zr: return CEMU_BRIDGE_BUTTON_ZR
        case .plus: return CEMU_BRIDGE_BUTTON_PLUS
        case .minus: return CEMU_BRIDGE_BUTTON_MINUS
        case .up: return CEMU_BRIDGE_BUTTON_UP
        case .down: return CEMU_BRIDGE_BUTTON_DOWN
        case .left: return CEMU_BRIDGE_BUTTON_LEFT
        case .right: return CEMU_BRIDGE_BUTTON_RIGHT
        case .stickL: return CEMU_BRIDGE_BUTTON_STICK_L
        case .stickR: return CEMU_BRIDGE_BUTTON_STICK_R
        case .home: return CEMU_BRIDGE_BUTTON_HOME
        }
    }

    /// The labels cemuBridgeButton(forLabel:) and PadDiagnostics already use.
    static func label(_ b: PadButton) -> String {
        switch b {
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .l: return "L"
        case .r: return "R"
        case .zl: return "ZL"
        case .zr: return "ZR"
        case .plus: return "plus"
        case .minus: return "minus"
        case .up: return "up"
        case .down: return "down"
        case .left: return "left"
        case .right: return "right"
        case .stickL: return "L3"
        case .stickR: return "R3"
        case .home: return "HOME"
        }
    }
}

/// The TouchLab pad as mounted in EmulatorViewOptimized.
///
/// Reads the SAME size / opacity / haptics / stick keys as MuffinEMU's own pad, so those
/// settings carry over when switching styles.
struct TouchLabPadOverlay: View {
    let schemeID: String
    let gameID: String?
    /// Window-coordinate frames of the TV / GamePad views (from TouchLabScreenFramesKey).
    let screens: TouchLabScreenState
    /// False while paused or while the layout editor is open: drawn, but inert.
    let enabled: Bool
    /// Height reserved for the top bar, so no control lands under Back / pause.
    let topInset: CGFloat

    @AppStorage(ControllerLayoutSettings.scaleKey) private var scale = ControllerLayoutSettings.defaultScale
    @AppStorage(ControllerLayoutSettings.stickSpacingKey) private var stickSpacing = ControllerLayoutSettings.defaultStickSpacing
    @AppStorage(ControllerLayoutSettings.shoulderOffsetKey) private var shoulderOffset = ControllerLayoutSettings.defaultShoulderOffset
    @AppStorage(ControllerLayoutSettings.opacityKey) private var opacity = ControllerLayoutSettings.defaultOpacity
    @AppStorage(ControllerLayoutSettings.hapticsKey) private var haptics = ControllerLayoutSettings.defaultHaptics
    @AppStorage(ControllerLayoutSettings.deadzoneKey) private var deadzone = ControllerLayoutSettings.defaultDeadzone
    @AppStorage(ControllerLayoutSettings.stickCurveKey) private var curve = ControllerLayoutSettings.defaultStickCurve
    @AppStorage(ControllerLayoutSettings.stickGateKey) private var gateRaw = ControllerLayoutSettings.defaultStickGateRaw
    @AppStorage(TouchLabSettings.floatCameraKey) private var cameraRaw = TouchLabSettings.defaultFloatCamera
    @AppStorage(TouchLabSettings.adaptiveResetKey) private var adaptiveResets = 0
    @AppStorage(TouchLabSettings.racingAutoAccelerateKey) private var racingAuto = false
    @AppStorage(TouchLabSettings.racingTiltKey) private var racingTilt = false
    @AppStorage(TouchLabSettings.zoneLargeAKey) private var zoneLargeA = false

    var body: some View {
        TouchPad(schemeID: schemeID,
                 output: CemuBridgePadOutput.shared,
                 touchscreenRect: screens.screens.touchscreenRect,
                 videoRects: screens.screens.videoRects,
                 scale: scale,
                 stickSpacing: stickSpacing,
                 // iPad only: the stored value is ignored on iPhone. The layouts ignore a
                 // negative value (the shoulders already start at the top edge).
                 shoulderOffset: CGFloat(ControllerLayoutSettings.effectiveShoulderOffset(shoulderOffset)),
                 opacity: opacity,
                 haptics: haptics,
                 // Rebuild the scheme only when something that shapes it changes - never on
                 // Adaptive's own learning writes (that would drop every held press).
                 revision: revision,
                 enabled: enabled,
                 stickTuning: StickTuning(deadzone: deadzone, curve: curve,
                                          gate: StickTuning.Gate(rawValue: gateRaw) ?? .octagon),
                 rectSpace: .window,
                 extraInsets: Insets(top: topInset),
                 makeScheme: makeScheme)
            .ignoresSafeArea()
            .onAppear { syncGamepadSize() }
            .onChange(of: screens) { _ in syncGamepadSize() }
    }

    private var revision: Int {
        var h = Hasher()
        h.combine(cameraRaw)
        h.combine(gameID)
        h.combine(adaptiveResets)
        h.combine(racingAuto)
        h.combine(racingTilt)
        h.combine(zoneLargeA)
        return h.finalize()
    }

    private func syncGamepadSize() {
        CemuBridgePadOutput.shared.gamepadViewSize = screens.screens.touchscreenRect?.size ?? .zero
    }

    private func makeScheme(_ id: String) -> TouchScheme {
        switch id {
        case FloatPad.schemeInfo.id:
            return FloatPad(camera: FloatPad.Camera(rawValue: cameraRaw) ?? .stick)
        case AdaptivePad.schemeInfo.id:
            let key = TouchLabSettings.adaptiveKey(gameID: gameID)
            let pad = AdaptivePad(learned: AdaptivePad.decode(UserDefaults.standard.string(forKey: key) ?? "{}"))
            pad.onLearned = { UserDefaults.standard.set(AdaptivePad.encode($0), forKey: key) }
            return pad
        case ZonePad.schemeInfo.id:
            return ZonePad(largeA: zoneLargeA)
        case RacingPad.schemeInfo.id:
            return RacingPad(options: RacingPad.Options(autoAccelerate: racingAuto, tilt: racingTilt))
        default:
            return SchemeCatalog.make(id)
        }
    }
}

// MARK: - For ContentView

// ContentView doesn't import the package. It uses the names below instead, so
// `import TouchLabUI` stays in this one file.

/// Where the TV and GamePad views are on screen, as ContentView holds it. A wrapper
/// rather than a typealias: a property of a type that lives in TouchLabUI makes the
/// compiler warn in any file that doesn't import that module.
struct TouchLabScreenState: Equatable {
    fileprivate var screens = TouchLabScreens(frames: [:])
    init() {}
}

extension View {
    /// Marks this view as the one showing the TV picture.
    func touchLabTVScreen() -> some View { touchLabScreenFrame(.tv) }

    /// Marks this view as the one showing the GamePad picture. Apply it AFTER any gesture
    /// on the view, so it measures the same frame the gesture does.
    func touchLabGamePadScreen() -> some View { touchLabScreenFrame(.gamepad) }

    /// Keeps `screens` up to date with the marked views' frames. Writes only when the
    /// layout actually changed, and never from the input path.
    func trackTouchLabScreens(_ screens: Binding<TouchLabScreenState>,
                              imageIsAspectFit: @escaping () -> Bool) -> some View {
        onPreferenceChange(TouchLabScreenFramesKey.self) { frames in
            var next = TouchLabScreenState()
            next.screens = TouchLabScreens(frames: frames, imageIsAspectFit: imageIsAspectFit())
            if next != screens.wrappedValue { screens.wrappedValue = next }
        }
    }
}
