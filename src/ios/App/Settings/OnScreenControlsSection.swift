import SwiftUI

/// Every on-screen control setting except which cluster sits where - moving a
/// cluster is a thing you can only sensibly do with a game under it, so that lives
/// in the emulator view. Size and opacity are worth setting from here too, and
/// "Reset layout" needs to be reachable from somewhere that is not itself on top of
/// the pad.
struct OnScreenControlsSection: View {
    // Same keys the on-screen pad reads.
    @AppStorage(ControllerLayoutSettings.scaleKey)
    private var controlScale = ControllerLayoutSettings.defaultScale
    @AppStorage(ControllerLayoutSettings.opacityKey)
    private var controlOpacity = ControllerLayoutSettings.defaultOpacity
    // Must keep matching the declaration in ControllerPad and ContentView: one key with
    // two disagreeing @AppStorage defaults means this toggle and the pad disagree about
    // which control scheme is on.
    @AppStorage(ControllerLayoutSettings.joystickKey)
    private var joystickMode = ControllerLayoutSettings.defaultJoystick
    @AppStorage(ControllerLayoutSettings.comfortControlsKey)
    private var comfortControls = ControllerLayoutSettings.defaultComfortControls
    @AppStorage(ControllerLayoutSettings.deadzoneKey)
    private var stickDeadzone = ControllerLayoutSettings.defaultDeadzone
    @AppStorage(ControllerLayoutSettings.stickCurveKey)
    private var stickCurve = ControllerLayoutSettings.defaultStickCurve
    @AppStorage(ControllerLayoutSettings.stickGateKey)
    private var stickGateRaw = ControllerLayoutSettings.defaultStickGateRaw
    @AppStorage(ControllerLayoutSettings.hapticsKey)
    private var hapticsEnabled = ControllerLayoutSettings.defaultHaptics
    @AppStorage(MeloControlsSetting.storageKey)
    private var useMeloControls = MeloControlsSetting.defaultValue

    private var stickGate: ControllerGeometry.StickGate {
        ControllerGeometry.StickGate(rawValue: stickGateRaw) ?? ControllerLayoutSettings.defaultStickGate
    }

    var body: some View {
        Section {
            Toggle(isOn: $useMeloControls) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use melo-controls")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(useMeloControls
                         ? "Melo-Controller, stossy11's touch controller, with its own layout editor. The options below apply to MuffinEMU's pad."
                         : "MuffinEMU's measured GamePad layout.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)

            Toggle(isOn: $joystickMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add analog sticks")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(joystickMode
                         ? "Both sticks shown alongside the d-pad and face buttons, not instead of them."
                         : "Just the d-pad and face buttons, from the measured layout.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)

            // Only while the mode they belong to is on. A deadzone slider
            // under a d-pad is a control with nothing behind it.
            if joystickMode {
                joystickOptions
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Button size")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                HStack(spacing: 10) {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(
                        value: $controlScale,
                        in: ControllerLayoutSettings.minScale...ControllerLayoutSettings.maxScale
                    )
                    Image(systemName: "plus.magnifyingglass")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Opacity")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled")
                    Slider(value: $controlOpacity, in: 0.2...1.0)
                    Image(systemName: "circle.fill")
                }
            }

            Toggle(isOn: $hapticsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Haptic feedback")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("A light tap on press. Turn off if it feels like buzzing rather than a button.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)

            Button(role: .destructive, action: { ControllerLayoutSettings.reset() }) {
                Label("Reset layout", systemImage: "arrow.uturn.backward")
            }
        } header: {
            Text("On-screen Controls")
        } footer: {
            InfoButton.footer(
                "The joystick is analog like the real GamePad's sticks; comfort controls move the shoulder buttons onto it once it's on. MuffinEMU already picks the right button size for your screen - the sliders adjust that choice, not replace it.",
                title: "On-screen Controls",
                text: fullText)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    // Only here, under the sticks: with no sticks on screen there is nothing for
    // L/ZL/minus and R/ZR/plus to move onto, and a deadzone/fine-control slider has
    // nothing to shape either.
    @ViewBuilder private var joystickOptions: some View {
        Toggle(isOn: $comfortControls) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Comfort controls")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(comfortControls
                     ? "L, ZL and minus sit on the left stick; R, ZR and plus sit on the right stick."
                     : "L, ZL and minus stay on the d-pad; R, ZR and plus stay on A/B/X/Y.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .tint(MuffinTheme.pixelBlue)

        // Above the two sliders because it is a different kind of question: the
        // gate is the shape of the stick, and the sliders are how that shape is
        // read.
        VStack(alignment: .leading, spacing: 4) {
            Picker("Gate", selection: $stickGateRaw) {
                ForEach(ControllerGeometry.StickGate.allCases) { gate in
                    Text(gate.title).tag(gate.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text(stickGate.summary)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Stick deadzone")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                // The number, not just the handle. This is the one setting where
                // "how much exactly" is the question being asked, and a bare slider
                // cannot answer it.
                Text(stickDeadzone <= 0.0005
                     ? "off"
                     : "\(Int((stickDeadzone * 100).rounded()))%")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Slider(
                value: $stickDeadzone,
                in: ControllerLayoutSettings.minDeadzone...ControllerLayoutSettings.maxDeadzone
            )
        }

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Fine control")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text(stickCurve <= ControllerLayoutSettings.minStickCurve + 0.005
                     ? "linear"
                     : String(format: "%.1fx", stickCurve))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            Slider(
                value: $stickCurve,
                in: ControllerLayoutSettings.minStickCurve...ControllerLayoutSettings.maxStickCurve
            )
        }
    }

    private var fullText: String {
        "The joystick is analog, like the sticks on the real GamePad: how far you push it is how fast you go, which a d-pad cannot express - it only ever says fully left or nothing. The position your thumb is at is the position the game receives, at full precision and with nothing smoothing it on the way. It takes the d-pad's own footprint, so nothing else on the pad moves, and turning it on also adds a camera stick on the right for the games that look around. Tap the left stick without pushing it to click it in (L3), which is where that button lives in this mode.\n\nThe gate is the shape the stick can reach. The real GamePad's is an octagon, and that is not decoration: only the four cardinals and the four diagonals reach full travel, and the flats between them stop about 8% short - which is the stick Mario Kart's drift and Zelda's walking were tuned against, and the flats are also the only thing telling your thumb where the diagonals are. Round gives the maximum in every direction instead.\n\nDeadzone is how much of the stick around the centre reads as untouched. Everything past it still reaches full speed, so turning it down buys precision near the middle and costs nothing at the top - turn it up only if a resting thumb makes the game drift. Fine control bends the first part of the travel: at linear, halfway is half speed; above it, halfway is slower than half, so small corrections get more of the stick to happen in. Nothing changes at the rim either way.\n\nMuffin picks a button size for the screen it is on and re-picks it whenever that changes, so the pad is already the right size on a phone and on an iPad without being set here. The size and opacity sliders adjust that choice rather than replacing it.\n\nTo move a cluster - either half, or the camera stick - start a game and tap the move button in the top bar; you need the game underneath to judge where the controls should go. The same joystick switch is in that panel."
    }
}
