// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI

/// Every on-screen control setting except which cluster sits where - moving a
/// cluster is a thing you can only sensibly do with a game under it, so that lives
/// in the emulator view. The section itself is a short list (style, sticks on or off, the
/// resets); the rest sits on pages of their own: Size and feel, Sticks, During play. Size and opacity are worth setting from here too, and
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
    @AppStorage(ControllerLayoutSettings.pauseWhileEditingKey)
    private var pauseWhileEditing = ControllerLayoutSettings.defaultPauseWhileEditing
    @AppStorage(HiddenScreenSettings.hideControlsInHomeMenuKey)
    private var hideControlsInHomeMenu = false
    @AppStorage(PreviewPadStore.enabledKey)
    private var previewPadEnabled = PreviewPadStore.defaultEnabled
    @AppStorage(ControllerLayoutSettings.stickCalibrationLeftKey)
    private var calibrationLeft = ""
    @AppStorage(ControllerLayoutSettings.stickCalibrationRightKey)
    private var calibrationRight = ""
    @AppStorage(MeloControlsSetting.storageKey)
    private var useMeloControls = MeloControlsSetting.defaultValue
    @AppStorage(TouchLabSettings.schemeKey)
    private var touchLabScheme = TouchLabSettings.defaultScheme
    @AppStorage(TouchLabSettings.stickFollowKey)
    private var stickFollowsThumb = false
    @AppStorage(TouchLabSettings.stickRelativeKey)
    private var stickRelative = false
    @AppStorage(ControllerLayoutSettings.stickSpacingKey)
    private var stickSpacing = ControllerLayoutSettings.defaultStickSpacing
    private var shoulderStore = ShoulderOffsetStorage()
    @ObservedObject private var windowSize = ControlsWindowSize.shared
    /// The shoulder setting for the orientation the pad is in now (kept apart per orientation),
    /// taken from the same size the pad itself uses.
    private var shoulderBinding: Binding<Double> {
        shoulderStore.binding(in: windowSize.effectiveSize, touchLab: usingTouchLab)
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

            if MeloControlsSetting.isAvailable {
                Toggle(isOn: $useMeloControls) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Melo-Controller")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(useMeloControls
                             ? "Melo-Controller by stossy11, with its own layout editor. The options below don't apply to it."
                             : "MuffinEMU's own GamePad layout.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .tint(MuffinTheme.pixelBlue)
            }

            if !usingTouchLab {
                Toggle(isOn: $joystickMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add analog sticks")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(joystickMode
                             ? "Both sticks shown alongside the d-pad and face buttons, not instead of them."
                             : "Just the d-pad and face buttons, as on the real GamePad.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .tint(MuffinTheme.pixelBlue)
            }

            // The rest is grouped on pages of its own, so this section stays a short list you can
            // read at a glance: what each page holds is said under its name.
            subPageLink("Size and feel", systemImage: "hand.point.up.left", summary: sizeAndFeelSummary) {
                subPage("Size and feel", footer: "Reset controls to default, on the On-screen controls list, puts these back.") {
                    sizeAndFeelRows
                }
            }

            // Only while the mode they belong to is on. A deadzone slider
            // under a d-pad is a control with nothing behind it. The TouchLab styles always
            // have sticks, and read the same gate, deadzone and curve.
            if joystickMode || usingTouchLab || previewPadEnabled {
                subPageLink("Sticks", systemImage: "dial.medium",
                            summary: "Calibration, spacing and how the sticks feel. Applies to every control style.") {
                    subPage("Sticks", footer: "Calibration applies to every control style: this pad, the new pad (preview) and each TouchLab style.") {
                        joystickOptions
                    }
                }
            }

            subPageLink("During play", systemImage: "play.rectangle",
                        summary: "The top bar, and when the controls hide or pause the game.") {
                subPage("During play", footer: "To move buttons, start a game and tap the move button in the top bar.") {
                    duringPlayRows
                }
            }

            subPageLink("New pad (preview)", systemImage: "sparkles", summary: "Try the pad that's being built.") {
                ZStack {
                    MuffinTheme.backgroundGradient.ignoresSafeArea()
                    Form { Group { PreviewPadSection() }.muffinGlassRows()}.muffinGlassFormGround()
                }
                .navigationTitle("New pad (preview)")
                .foregroundColor(MuffinTheme.brownDarkest)
            }

            Group {
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
            }
        } header: {
            SettingsSectionHeader("On-screen controls", icon: "gamecontroller", accent: .io)
        } footer: {
            InfoButton.footer(
                "To move buttons, start a game and tap the move button in the top bar.",
                title: "On-screen controls",
                text: fullText)
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .confirmationDialog("Reset controls to default?", isPresented: $showingResetLayoutConfirmation, titleVisibility: .visible) {
            Button("Reset to default", role: .destructive) {
                ControllerLayoutSettings.reset()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Button size, opacity, stick spacing, shoulder height and every button you've moved go back to their defaults.")
        }
        .confirmationDialog("Reset controller bindings?", isPresented: $showingResetBindingsConfirmation, titleVisibility: .visible) {
            Button("Reset bindings", role: .destructive) {
                let ok = cemu_bridge_reset_controller_bindings()
                let count = Int(cemu_bridge_input_button_mapping_count())
                bindingsResetResult = ok
                    ? "Reset. The GamePad now has \(count) button bindings."
                    : (count < 0
                        ? "No GamePad is connected yet. Start a game, then try again."
                        : "Reset, but the GamePad still has no button bindings.")
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Rebuilds the default button bindings. Use this if some buttons do nothing while the sticks still work. Any buttons you remapped go back to default.")
        }
    }

    // MARK: Pages

    private var sizeAndFeelSummary: String {
        ControllerLayoutSettings.supportsShoulderOffset
            ? "Button size, opacity, haptic feedback and shoulder button height."
            : "Button size, opacity and haptic feedback."
    }

    /// A row that opens one of this section's pages, with a line saying what's on it.
    private func subPageLink<Destination: View>(_ title: String, systemImage: String, summary: String,
                                                @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(summary)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One of this section's pages: its rows in one Section on the Settings background.
    private func subPage<Content: View>(_ title: String, footer: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            MuffinTheme.backgroundGradient.ignoresSafeArea()
            Form { Group {
                Section {
                    content()
                } footer: {
                    InfoButton.footer(footer)
                }
            }.muffinGlassRows()}.muffinGlassFormGround()
        }
        .navigationTitle(title)
        .foregroundColor(MuffinTheme.brownDarkest)
    }

    @ViewBuilder private var sizeAndFeelRows: some View {
        // iPad only: an iPhone has no spare height to move them in. Applies to MuffinEMU's
        // pad and to the TouchLab styles whose shoulders are fixed.
        if ControllerLayoutSettings.supportsShoulderOffset
            && (!usingTouchLab || TouchLabSettings.hasMovableShoulders(touchLabScheme)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(shoulderStore.label(in: windowSize.effectiveSize, touchLab: usingTouchLab))
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
                Toggle("Same height in portrait and landscape",
                       isOn: shoulderStore.linkBinding(in: windowSize.effectiveSize, touchLab: usingTouchLab))
                    .font(.system(size: 13, design: .rounded))
                Text("Moves L, R, ZL and ZR up or down together.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

        Toggle(isOn: $hapticsEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Haptic feedback")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("A light tap when you press a button. Turn off if it feels like buzzing.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .tint(MuffinTheme.pixelBlue)

    }

    @ViewBuilder private var duringPlayRows: some View {
        Toggle(isOn: hideTopBar) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hide the top bar while playing")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Fades the top bar out a few seconds after you touch it. Tap the handle at the top, or swipe down from it, to bring it back. On by default.")
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

        Toggle(isOn: $pauseWhileEditing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pause while moving the controls")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("The game waits while you move or adjust the on-screen controls, and carries on when you tap Done.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .tint(MuffinTheme.pixelBlue)

        Toggle(isOn: $hideControlsInHomeMenu) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hide on-screen controls in the HOME menu")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("The controls disappear while the HOME menu is open and come back when it closes.")
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
            Text("The area you tap to bring the bar back. Large is easier to hit but can block touches meant for the GamePad screen.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // Shown only with sticks on, since these options have nothing to act on otherwise.
    @ViewBuilder private var joystickOptions: some View {
        // One calibration for every control style: this pad, the new pad (preview) and each TouchLab style.
        NavigationLink {
            StickCalibrationView()
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label("Calibrate sticks", systemImage: "scope")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(calibrationLeft.isEmpty && calibrationRight.isEmpty
                     ? "Rest your thumb, push to every edge, let go. Matches the sticks to your reach, in every control style."
                     : "Calibrated. Applies to every control style.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        if !(calibrationLeft.isEmpty && calibrationRight.isEmpty) {
            Button(role: .destructive) { SharedStick.resetCalibration() } label: {
                DestructiveSettingsLabel(title: "Reset stick calibration", systemImage: "arrow.uturn.backward")
            }
        }

        // Each stick on its own: deadzones, sensitivity, invert and a test circle. Advanced, like
        // the deadzone and fine control sliders it extends.
        if advanced {
            NavigationLink {
                StickFineTuneView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Tune each stick", systemImage: "dial.medium")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Deadzones, sensitivity and invert for each stick, with a test circle. Applies to every control style.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }

        if usingTouchLab {
            Toggle(isOn: $stickFollowsThumb) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stick follows thumb")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("The stick moves with your thumb if you slide past the ring, so turning back is quick.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)

            Toggle(isOn: $stickRelative) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Relative stick")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("The stick centres wherever you first touch, so the first touch doesn't move it.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .tint(MuffinTheme.pixelBlue)
        }

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
                // Sets both sticks, so a stick's own value is dropped.
                .onChange(of: stickDeadzone) { _ in SharedStick.clearInnerAndCurveOverrides() }
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
                .onChange(of: stickCurve) { _ in SharedStick.clearInnerAndCurveOverrides() }
            }
        }
    }

    private var fullText: String {
        "Add analog sticks shows both sticks alongside the d-pad and face buttons. The rest is on three pages.\n\nSize and feel: button size, opacity and haptic feedback, and on iPad, Shoulder button height, which moves L, R, ZL and ZR up or down together.\n\nSticks has Calibrate sticks (rest your thumb, push to each edge, let go, so the sticks fit your reach) and Stick spacing, which moves the sticks closer together or further apart. In Advanced mode it also has Tune each stick, Stick gate, Stick deadzone and Fine control. Stick gate is the shape the stick can reach: Octagon matches the real GamePad, Round reaches full travel in every direction. Deadzone is how far you can move before the game notices; raise it only if a resting thumb makes the game drift. Fine control makes small movements gentler.\n\nDuring play: Hide the top bar while playing fades the Back and pause bar out a few seconds after you last touch it. Tap the small handle at the top, or swipe down from it, to bring it back. The bar stays visible when the game is paused, a menu is open or VoiceOver is on. In Advanced mode you can set how long it waits and how big the handle is. Large is easier to tap but can block touches meant for the GamePad screen. The same page has pausing while you move the controls, and hiding them in the HOME menu or while a controller is connected (off by default).\n\nThese settings apply to every game. Adaptive remembers where your thumbs land, and Melo-Controller remembers where you moved its buttons, for each game separately.\n\nTo move buttons, start a game and tap the move button in the top bar. You can also switch control style there."
    }
}
