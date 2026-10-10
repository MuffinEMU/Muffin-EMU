// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

/// Every on-screen control setting except which cluster sits where - moving a
/// cluster is a thing you can only sensibly do with a game under it, so that lives
/// in the emulator view. Size and opacity are worth setting from here too, and
/// "Reset controls to default" needs to be reachable from somewhere that is not itself on top of
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
    @AppStorage(ControllerLayoutSettings.autoHideWithControllerKey)
    private var autoHideWithController = ControllerLayoutSettings.defaultAutoHideWithController
    @AppStorage(HiddenScreenSettings.hideControlsInHomeMenuKey)
    private var hideControlsInHomeMenu = false
    @AppStorage(MeloControlsSetting.storageKey)
    private var useMeloControls = MeloControlsSetting.defaultValue
    @AppStorage(TouchLabSettings.schemeKey)
    private var touchLabScheme = TouchLabSettings.defaultScheme
    @AppStorage(ControllerLayoutSettings.touchToleranceKey)
    private var touchTolerance = TouchTolerance.defaultValue.rawValue
    @AppStorage(ControllerLayoutSettings.stickSpacingKey)
    private var stickSpacing = ControllerLayoutSettings.defaultStickSpacing
    private var shoulderStore = ShoulderOffsetStorage()
    @ObservedObject private var windowSize = ControlsWindowSize.shared
    /// The shoulder setting for the orientation the pad is in now (kept apart per orientation),
    /// taken from the same size the pad itself uses.
    private var shoulderBinding: Binding<Double> {
        shoulderStore.binding(upright: ControllerLayoutSettings.isUpright(windowSize.effectiveSize))
    }
    /// 0 follows the default (on; see TopBarAutoHide.deviceDefault). Read by the in-game top bar.
    @AppStorage(TopBarAutoHide.overrideKey)
    private var topBarAutoHideOverride = TopBarAutoHide.followDevice
    @AppStorage(SettingsMode.storageKey)
    private var settingsModeRaw = SettingsMode.defaultValue.rawValue
    @AppStorage(TopBarAutoHide.hideDelayKey)
    private var topBarHideDelay = TopBarAutoHide.defaultHideDelaySeconds
    @AppStorage(TopBarAutoHide.handleSizeKey)
    private var topBarHandleSize = TopBarAutoHide.defaultHandleSize.rawValue
    @State private var showingResetLayoutConfirmation = false
    @State private var showingResetBindingsConfirmation = false
    /// Shows the binding count so a reset can be confirmed.
    @State private var bindingsResetResult: String?

    private var stickGate: ControllerGeometry.StickGate {
        ControllerGeometry.StickGate(rawValue: stickGateRaw) ?? ControllerLayoutSettings.defaultStickGate
    }

    private var advanced: Bool { SettingsMode.isAdvanced(raw: settingsModeRaw) }

    /// A TouchLab style is chosen. It carries its own layout, so the rows that only apply to
    /// MuffinEMU's pad (analog-stick mode, comfort controls) are hidden.
    private var usingTouchLab: Bool { TouchLabSettings.isTouchLab(touchLabScheme) }

    private var hideTopBar: Binding<Bool> {
        Binding(
            get: { TopBarAutoHide.isOn(override: topBarAutoHideOverride) },
            set: { topBarAutoHideOverride = TopBarAutoHide.override(forChoice: $0) }
        )
    }

    var body: some View {
        Section {
            TouchLabStyleSettingsRows()

            Toggle(isOn: $useMeloControls) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use Melo-Controller")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(useMeloControls
                         ? "Melo-Controller by stossy11, with its own layout editor. The options below are for MuffinEMU's pad."
                         : "MuffinEMU's measured GamePad layout.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)

            if !usingTouchLab {
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
            }

            // Only while the mode they belong to is on. A deadzone slider
            // under a d-pad is a control with nothing behind it. The TouchLab styles always
            // have sticks, and read the same gate, deadzone and curve.
            if joystickMode || usingTouchLab {
                // Gate, deadzone, curve and spacing live on their own page so this section
                // stays a short list of the things most people change.
                NavigationLink {
                    Form { Section { joystickOptions } }
                        .navigationTitle("Stick tuning")
                } label: {
                    Label("Stick tuning", systemImage: "dial.medium")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }

            // iPad only: an iPhone has no spare height to move them in. Applies to MuffinEMU's
            // pad and to the TouchLab styles whose shoulders are fixed.
            if ControllerLayoutSettings.supportsShoulderOffset
                && (!usingTouchLab || TouchLabSettings.hasMovableShoulders(touchLabScheme)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("L, R, ZL and ZR height")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Spacer()
                        // The TouchLab styles can only move them down, so a "higher" left over from
                        // MuffinEMU's pad would describe nothing on screen.
                        Text(ControllerLayoutSettings.shoulderOffsetLabel(usingTouchLab ? max(0, shoulderBinding.wrappedValue) : shoulderBinding.wrappedValue))
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.and.down")
                            .accessibilityHidden(true)
                        Slider(
                            value: shoulderBinding,
                            in: ControllerLayoutSettings.shoulderOffsetRange(touchLab: usingTouchLab, in: windowSize.effectiveSize),
                            step: ControllerLayoutSettings.shoulderOffsetStep
                        )
                        .accessibilityLabel("Shoulder button height")
                        .accessibilityValue(ControllerLayoutSettings.shoulderOffsetLabel(usingTouchLab ? max(0, shoulderBinding.wrappedValue) : shoulderBinding.wrappedValue))
                    }
                    Text("Moves the four shoulder buttons up or down together. They stop before they would leave the screen or touch the sticks and buttons.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // One Group: the Section stays under ViewBuilder's ten direct children.
            Group {
            VStack(alignment: .leading, spacing: 4) {
                Text("Button size")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                HStack(spacing: 10) {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(
                        value: $controlScale,
                        in: ControllerLayoutSettings.minScale...ControllerLayoutSettings.maxScale
                    )
                    .accessibilityLabel("Button size")
                    Image(systemName: "plus.magnifyingglass")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Opacity")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled")
                    Slider(value: $controlOpacity, in: 0.2...1.0)
                        .accessibilityLabel("Opacity")
                    Image(systemName: "circle.fill")
                }
            }

            Picker(selection: $touchTolerance) {
                ForEach(TouchTolerance.allCases) { Text($0.title).tag($0.rawValue) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Touch tolerance")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("How far from a button a press still counts. Go higher if presses miss.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
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

            Toggle(isOn: hideTopBar) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide the top bar while playing")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("The bar fades away a few seconds after you last touch it. Tap the small handle at the top of the screen, or swipe down from it, to bring it back. It stays up while paused, in menus, and with VoiceOver on. On by default.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(MuffinTheme.pixelBlue)

            // How long the bar waits, and how big the handle is: Advanced mode only (see AdvancedSettings).
            if advanced && hideTopBar.wrappedValue {
                topBarOptions
            }

            if !usingTouchLab && !useMeloControls {
                NavigationLink {
                    ClusterPlacementSettings(
                        upright: UIDevice.current.userInterfaceIdiom == .phone && ControllerLayoutSettings.isUpright(windowSize.size))
                        .id(ControllerLayoutSettings.isUpright(windowSize.size))
                } label: {
                    Label("Left and right buttons", systemImage: "arrow.left.and.right.square")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
            }

            NavigationLink {
                Form { PreviewPadSection() }
                    .navigationTitle("New pad system (preview)")
            } label: {
                Label("New pad system (preview)", systemImage: "sparkles")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }

            Toggle(isOn: $hideControlsInHomeMenu) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide the on-screen controls in the home menu")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("The controls disappear while the home menu is open and come back when it closes.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)

            Toggle(isOn: $autoHideWithController) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide on-screen controls when a controller is connected")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("The controls come back when it disconnects. The GamePad's screen stays, so you can still touch it.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)
            }

            // Resets MuffinEMU's own pad (size, opacity, stick spacing, moved buttons), which is
            // also what the TouchLab styles read for size, opacity and stick spacing.
            Button(role: .destructive, action: { showingResetLayoutConfirmation = true }) {
                DestructiveSettingsLabel(title: "Reset controls to default", systemImage: "arrow.uturn.backward")
            }

            // Separate from the reset above: that moves buttons on screen, this repairs what
            // a press is wired to.
            Button(role: .destructive, action: { showingResetBindingsConfirmation = true }) {
                DestructiveSettingsLabel(title: "Reset controller bindings", systemImage: "gamecontroller.fill")
            }

            if let bindingsResetResult {
                Text(bindingsResetResult)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        } header: {
            SettingsSectionHeader("On-screen Controls", icon: "gamecontroller", accent: .io)
        } footer: {
            InfoButton.footer(
                "Sticks are analog like the real GamePad. Comfort controls move the shoulder buttons onto the sticks.",
                title: "On-screen Controls",
                text: fullText)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .confirmationDialog("Reset controls to default?", isPresented: $showingResetLayoutConfirmation, titleVisibility: .visible) {
            Button("Reset to default", role: .destructive) {
                ControllerLayoutSettings.reset()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Button size, opacity, stick spacing, shoulder height and every button you've moved go back to how MuffinEMU ships.")
        }
        .confirmationDialog("Reset controller bindings?", isPresented: $showingResetBindingsConfirmation, titleVisibility: .visible) {
            Button("Reset bindings", role: .destructive) {
                let ok = cemu_bridge_reset_controller_bindings()
                let count = Int(cemu_bridge_input_button_mapping_count())
                bindingsResetResult = ok
                    ? "Reset. The GamePad now has \(count) button bindings."
                    : (count < 0
                        ? "No GamePad is wired yet - start a game, then try again."
                        : "Reset, but the GamePad still has no button bindings.")
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Rebuilds the default button bindings. Use this if some buttons do nothing while the sticks still work. Any buttons you remapped go back to default.")
        }
    }

    @ViewBuilder private var topBarOptions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top bar hides after")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Picker("Top bar hides after", selection: $topBarHideDelay) {
                ForEach(TopBarAutoHide.hideDelayChoices, id: \.self) { seconds in
                    Text("\(seconds) s").tag(seconds)
                }
            }
            .pickerStyle(.segmented)
        }

        VStack(alignment: .leading, spacing: 4) {
            Text("Reveal handle")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Picker("Reveal handle", selection: $topBarHandleSize) {
                ForEach(TopBarAutoHide.HandleSize.allCases) { size in
                    Text(size.title).tag(size.rawValue)
                }
            }
            .pickerStyle(.segmented)
            Text("The area you tap to bring the bar back. Large is easier to hit, but it can take touches meant for the GamePad screen at the top of the picture.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Shown only with sticks on, since these options have nothing to act on otherwise.
    @ViewBuilder private var joystickOptions: some View {
        if !usingTouchLab {
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
        }

        // Hand size. Only where the sticks sit in fixed places: MuffinEMU's pad, Zone
        // and Adaptive.
        if !usingTouchLab || TouchLabSettings.hasFixedSticks(touchLabScheme) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Stick spacing")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer()
                    Text(ControllerLayoutSettings.stickSpacingLabel(stickSpacing))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.and.line.vertical.and.arrow.left")
                        .accessibilityHidden(true)
                    Slider(
                        value: $stickSpacing,
                        in: ControllerLayoutSettings.minStickSpacing...ControllerLayoutSettings.maxStickSpacing,
                        step: ControllerLayoutSettings.stickSpacingStep
                    )
                    .accessibilityLabel("Stick spacing")
                    .accessibilityValue(ControllerLayoutSettings.stickSpacingLabel(stickSpacing))
                    Image(systemName: "arrow.left.and.line.vertical.and.arrow.right")
                        .accessibilityHidden(true)
                }
                Text("Moves both sticks closer together or further apart, to fit your hands.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        // Stick feel is Advanced mode only (see AdvancedSettings).
        if advanced {
            // Above the two sliders because it is a different kind of question: the
            // gate is the shape of the stick, and the sliders are how that shape is
            // read.
            VStack(alignment: .leading, spacing: 4) {
                Picker("Stick gate", selection: $stickGateRaw) {
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
                .accessibilityLabel("Stick deadzone")
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
                .accessibilityLabel("Fine control")
            }
        }
    }

    private var fullText: String {
        "Add analog sticks puts both sticks on screen alongside the d-pad and face buttons. Push further for more speed.\n\nGate is the shape the stick can reach. Octagon matches the real GamePad; Round reaches full travel in every direction.\n\nDeadzone is how far you can move before the game notices. Turn it up only if a resting thumb makes the game drift.\n\nFine control makes small movements gentler: at linear, halfway is half speed; higher values make halfway slower.\n\nStick spacing moves both sticks closer together or further apart, for smaller or bigger hands. On a narrow screen it stops before the sticks would touch.\n\nOn iPad, L, R, ZL and ZR height moves the four shoulder buttons up or down together, stopping before they would leave the screen or touch a stick or button.\n\nButton size and opacity adjust the size MuffinEMU picks for your screen.\n\nHide the top bar while playing fades the Back and pause bar out a few seconds after you last touch it, so it stops covering the picture. A small handle stays at the top centre of the screen: tap it, or swipe down from it, to bring the bar back. The bar stays up while the game is paused, a menu is open, or VoiceOver is on.\n\nIn Advanced mode, Top bar hides after sets the wait (2, 4 or 8 seconds) and Reveal handle sets the size of the area you tap to bring the bar back. Normal is the default; Large is easier to hit but can take touches meant for the GamePad screen at the top of the picture.\n\nHide on-screen controls when a controller is connected takes the controls off the screen while a controller is paired, and puts them back when it disconnects. It is off by default. The GamePad's screen stays visible and touchable either way.\n\nThese settings apply to every game. Two things are kept per game instead: Adaptive remembers where your thumbs land, and Melo-Controller remembers where you moved its buttons.\n\nTo move a cluster, start a game and tap the move button in the top bar. There you can also switch control style without leaving the game."
    }
}
