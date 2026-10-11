// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

// Settings and in-game layout-panel UI for the optional TouchLab control styles.
//
// Nothing here imports the package: styles, summaries and options come from
// TouchLabSettings (TouchLabPads.swift), which is the only file that does.

/// Label for a stored style id, in both pickers. "" is MuffinEMU's own pad. Whichever one
/// `TouchLabSettings.defaultScheme` names is marked as the default, so promoting a style
/// later needs no edit here.
func touchLabStyleLabel(_ id: String) -> String {
    let isDefault = id == TouchLabSettings.defaultScheme
    if id.isEmpty { return isDefault ? "MuffinEMU (default)" : "MuffinEMU (classic)" }
    let name = TouchLabSettings.styles.first { $0.id == id }?.name ?? id
    return isDefault ? name + " (default)" : name
}

/// The stored ids in picker order: MuffinEMU's own pad first, then the TouchLab styles.
private var touchLabStyleIDs: [String] { [""] + TouchLabSettings.styles.map(\.id) }

/// Rows for Settings > On-screen Controls, placed at the top of the section.
struct TouchLabStyleSettingsRows: View {
    @AppStorage(TouchLabSettings.schemeKey) private var scheme = TouchLabSettings.defaultScheme
    @AppStorage(MeloControlsSetting.storageKey) private var useMeloControls = MeloControlsSetting.defaultValue
    @AppStorage(TouchLabSettings.floatCameraKey) private var floatCamera = TouchLabSettings.defaultFloatCamera
    @AppStorage(TouchLabSettings.racingAutoAccelerateKey) private var racingAuto = false
    @AppStorage(TouchLabSettings.racingTiltKey) private var racingTilt = false
    @AppStorage(TouchLabSettings.aScaleKey) private var aScale = TouchLabSettings.defaultAScale
    @AppStorage(TouchLabSettings.showcaseColourKey) private var showcaseColour = TouchLabSettings.defaultShowcaseColour
    @AppStorage(TouchLabSettings.showcaseDisplayKey) private var showcaseDisplay = TouchLabSettings.defaultShowcaseDisplay
    @AppStorage(TouchLabSettings.showcaseGlassKey) private var showcaseGlass = false
    @AppStorage(TouchLabSettings.classicColourKey) private var classicColour = TouchLabSettings.defaultClassicColour
    @AppStorage(TouchLabSettings.racingItemPlacementKey) private var racingItemPlacement = TouchLabSettings.defaultRacingItemPlacement
    @AppStorage(TouchLabSettings.racingLargeItemKey) private var racingLargeItem = false
    @State private var showingAdaptiveReset = false
    @State private var showingArcReset = false

    var body: some View {
        // Choosing a style switches melo-controls off, because the player just picked
        // something else. The reverse does not clear the style: while melo-controls is on it
        // simply takes precedence.
        let selection = Binding<String>(
            get: { scheme },
            set: { newValue in
                scheme = newValue
                if TouchLabSettings.isTouchLab(newValue) { useMeloControls = false }
            }
        )

        Group {
            Picker(selection: selection) {
                ForEach(touchLabStyleIDs, id: \.self) { id in
                    Text(touchLabStyleLabel(id)).tag(id)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Control style")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if TouchLabSettings.isTouchLab(scheme) {
                if useMeloControls {
                    Text("Melo-Controller is switched on below, so it is showing instead. Switch it off to use \(TouchLabSettings.name(scheme)).")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if scheme == TouchLabSettings.floatStyleID {
                    Picker("Camera", selection: $floatCamera) {
                        ForEach(TouchLabSettings.cameraOptions, id: \.value) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if TouchLabSettings.usesClassicLook(scheme) {
                    Picker("Colour", selection: $classicColour) {
                        ForEach(TouchLabSettings.classicColourOptions, id: \.value) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                }

                if scheme == TouchLabSettings.showcaseStyleID {
                    Picker("Colour", selection: $showcaseColour) {
                        ForEach(TouchLabSettings.showcaseColourOptions, id: \.value) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                    Toggle(isOn: $showcaseGlass) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Glass look")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text("See-through buttons with a sheen across the top.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(MuffinTheme.pixelBlue)
                    Picker("Display", selection: $showcaseDisplay) {
                        ForEach(TouchLabSettings.showcaseDisplayOptions, id: \.value) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Fit sizes the pad around the picture. Native draws the GamePad at its real size on your screen.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                if scheme == TouchLabSettings.arcStyleID {
                    ArcSettingsRows(showResetConfirmation: $showingArcReset)
                }

                // Arc places every button by your reach and Showcase is the GamePad at its real size, so neither has a separate A size.
                if scheme != TouchLabSettings.arcStyleID && scheme != TouchLabSettings.showcaseStyleID {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("A button size")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Button(action: { aScale = TouchLabSettings.defaultAScale }) {
                            Text("\(Int((aScale * 100).rounded()))%")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reset A button size")
                        .accessibilityValue("\(Int((aScale * 100).rounded())) percent")
                    }
                    HStack(spacing: 8) {
                        Text("100%").font(.system(size: 12)).foregroundColor(.secondary)
                        Slider(value: $aScale, in: TouchLabSettings.aScaleRange, step: 0.01)
                            .tint(MuffinTheme.pixelBlue)
                            .accessibilityLabel("A button size")
                        Text("180%").font(.system(size: 12)).foregroundColor(.secondary)
                    }
                    Text("Makes A bigger and easier to hit. The buttons around it shrink a little. Tap the percentage to reset.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                }

                if scheme == TouchLabSettings.racingStyleID {
                    Toggle(isOn: $racingAuto) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-accelerate")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text("Holds A for you. Touching Brake lets it go.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(MuffinTheme.pixelBlue)

                    Toggle(isOn: $racingTilt) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tilt steering")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text("Turn the device like a wheel. Tap C at the top to set straight ahead.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(MuffinTheme.pixelBlue)

                    Picker("Item button position", selection: $racingItemPlacement) {
                        ForEach(TouchLabSettings.racingItemPlacementOptions, id: \.value) { option in
                            Text(option.title).tag(option.value)
                        }
                    }

                    Toggle(isOn: $racingLargeItem) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Larger item button")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text("Makes the item button bigger, so it is easier to hit without looking.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(MuffinTheme.pixelBlue)
                }

                if scheme == TouchLabSettings.adaptiveStyleID {
                    Button(role: .destructive, action: { showingAdaptiveReset = true }) {
                        DestructiveSettingsLabel(title: "Reset learned layouts", systemImage: "arrow.uturn.backward")
                    }
                }

                Text("These styles don't support dragging individual buttons. Size, opacity, haptics and the stick options below apply to them.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { TouchLabSettings.migrateLegacyLargeA() }
        .confirmationDialog("Reset Arc?", isPresented: $showingArcReset, titleVisibility: .visible) {
            Button("Reset Arc", role: .destructive) { ArcLive.shared.reset() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Arc forgets how your thumbs sweep and every position you fine-tuned, and goes back to its default arc.")
        }
        .confirmationDialog("Reset learned layouts?", isPresented: $showingAdaptiveReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { TouchLabSettings.resetAdaptiveAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Adaptive forgets where your thumbs land, in every game, and starts from its home positions again.")
        }
    }

    private var summary: String {
        TouchLabSettings.isTouchLab(scheme)
            ? TouchLabSettings.summary(scheme)
            : "MuffinEMU's measured GamePad layout, which you can also drag around."
    }
}

/// The in-game control-style switch, at the top of every layout panel that has one. "" is
/// MuffinEMU's own pad. Choosing a style here swaps the pad and the panel under it.
struct TouchLabStylePicker: View {
    @AppStorage(TouchLabSettings.schemeKey) private var scheme = TouchLabSettings.defaultScheme

    var body: some View {
        Picker("Control style", selection: $scheme) {
            ForEach(touchLabStyleIDs, id: \.self) { id in
                Text(id.isEmpty ? "MuffinEMU" : (TouchLabSettings.styles.first { $0.id == id }?.name ?? id))
                    .tag(id)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// The in-game layout panel while a TouchLab style is live. The pad behind it is drawn
/// but inert (see TouchLabPadOverlay's `enabled`), so nothing here can press a button.
struct TouchLabLayoutPanel: View {
    let gameID: String?
    let onDone: () -> Void

    @AppStorage(TouchLabSettings.schemeKey) private var scheme = TouchLabSettings.defaultScheme
    @AppStorage(TouchLabSettings.floatCameraKey) private var floatCamera = TouchLabSettings.defaultFloatCamera
    @AppStorage(ControllerLayoutSettings.scaleKey) private var controlScale = ControllerLayoutSettings.defaultScale
    @AppStorage(ControllerLayoutSettings.opacityKey) private var controlOpacity = ControllerLayoutSettings.defaultOpacity
    @AppStorage(ControllerLayoutSettings.stickSpacingKey) private var stickSpacing = ControllerLayoutSettings.defaultStickSpacing
    private var shoulderStore = ShoulderOffsetStorage()
    @ObservedObject private var windowSize = ControlsWindowSize.shared
    /// The shoulder setting for the orientation the pad is in now (kept apart per orientation),
    /// taken from the same size the pad itself uses.
    private var shoulderBinding: Binding<Double> {
        shoulderStore.binding(in: windowSize.effectiveSize, touchLab: true)
    }

    private var isAdaptive: Bool { scheme == TouchLabSettings.adaptiveStyleID }
    @State private var showingArcReset = false

    var body: some View {
        LayoutPanelCard(rows: { rows }, footer: {
            LayoutPanelFooter(
                resetMessage: isAdaptive
                    ? "Size, opacity, stick spacing and shoulder height go back to how MuffinEMU ships in every game, and Adaptive forgets where your thumbs land in this game only."
                    : "Size, opacity, stick spacing and shoulder height go back to how MuffinEMU ships, in every game.",
                onReset: resetToDefault,
                onDone: onDone)
        })
    }

    @ViewBuilder private var rows: some View {
        TouchLabStylePicker()

        PanelCaption(text: "\(TouchLabSettings.summary(scheme)) These styles don't support dragging individual buttons. Nothing here reaches the game.")

        PanelSliderRow("Button size", leadingIcon: "minus.magnifyingglass", trailingIcon: "plus.magnifyingglass",
                       value: $controlScale,
                       range: ControllerLayoutSettings.minScale...ControllerLayoutSettings.maxScale)

        PanelSliderRow("Opacity", leadingIcon: "circle.lefthalf.filled", trailingIcon: "circle.fill",
                       value: $controlOpacity, range: 0.2...1.0)

        // Hand size: both sticks move together, apart or closer. Only the styles with sticks
        // in fixed places have anything for it to move.
        if TouchLabSettings.hasFixedSticks(scheme) {
            PanelSliderRow("Stick spacing",
                           leadingIcon: "arrow.right.and.line.vertical.and.arrow.left",
                           trailingIcon: "arrow.left.and.line.vertical.and.arrow.right",
                           value: $stickSpacing,
                           range: ControllerLayoutSettings.minStickSpacing...ControllerLayoutSettings.maxStickSpacing,
                           step: ControllerLayoutSettings.stickSpacingStep,
                           spokenValue: ControllerLayoutSettings.stickSpacingLabel(stickSpacing))
        }

        // L, R, ZL and ZR move up or down together. iPad only: an iPhone has no spare height
        // for it. Only the styles with fixed shoulders have anything to move.
        if ControllerLayoutSettings.supportsShoulderOffset && TouchLabSettings.hasMovableShoulders(scheme) {
            PanelSliderRow(shoulderStore.label(in: windowSize.effectiveSize, touchLab: true), title: "L/R", leadingIcon: "arrow.up.and.down",
                           value: shoulderBinding,
                           range: ControllerLayoutSettings.shoulderOffsetRange(touchLab: true, in: windowSize.effectiveSize),
                           step: ControllerLayoutSettings.shoulderOffsetStep,
                           spokenValue: ControllerLayoutSettings.shoulderOffsetLabel(max(0, shoulderBinding.wrappedValue)))
            PanelToggle(title: "Same height in portrait and landscape",
                        isOn: shoulderStore.linkBinding(in: windowSize.effectiveSize, touchLab: true))
        }

        if scheme == TouchLabSettings.floatStyleID {
            Picker("Camera", selection: $floatCamera) {
                ForEach(TouchLabSettings.cameraOptions, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
        }

        if scheme == TouchLabSettings.arcStyleID {
            ArcSettingsRows(showResetConfirmation: $showingArcReset)
                .confirmationDialog("Reset Arc?", isPresented: $showingArcReset, titleVisibility: .visible) {
                    Button("Reset Arc", role: .destructive) { ArcLive.shared.reset() }
                    Button("Cancel", role: .cancel) { }
                }
        }

        PanelCaption(text: isAdaptive
                     ? "These settings apply to every game, except that Adaptive remembers where your thumbs land separately for each game."
                     : "These settings apply to every game.",
                     prominent: false)
    }

    /// Size, opacity, stick spacing and shoulder height are the only placement the fixed styles have.
    /// Adaptive also moves its buttons to where your thumbs land, so for Adaptive this
    /// game's learning goes too.
    private func resetToDefault() {
        controlScale = ControllerLayoutSettings.defaultScale
        controlOpacity = ControllerLayoutSettings.defaultOpacity
        stickSpacing = ControllerLayoutSettings.defaultStickSpacing
        shoulderStore.reset()
        if isAdaptive {
            TouchLabSettings.resetAdaptive(gameID: gameID)
        }
    }
}

/// Arc's own settings: lock, calibrate, fine-tune, reset. Calibrating and fine-tuning work on the
/// live pad, so they are offered while a game is running (the in-game layout panel); the lock and
/// the reset also work from Settings.
struct ArcSettingsRows: View {
    @ObservedObject private var arc = ArcLive.shared
    @Binding var showResetConfirmation: Bool
    @AppStorage(TouchLabSettings.arcOptionsKey) private var optionsRaw = "{}"

    var body: some View {
        let locked = Binding<Bool>(get: { arc.isLocked }, set: { arc.setLocked($0) })
        let swapHands = Binding<Bool>(
            get: { ArcOptions.decode(optionsRaw).swapHands },
            set: { var o = ArcOptions.decode(optionsRaw); o.swapHands = $0; optionsRaw = ArcOptions.encode(o) })
        let fadeWhenIdle = Binding<Bool>(
            get: { ArcOptions.decode(optionsRaw).idleFadeSeconds != nil },
            set: { var o = ArcOptions.decode(optionsRaw)
                   o.idleFadeSeconds = $0 ? TouchLabSettings.arcIdleFadeSeconds : nil
                   optionsRaw = ArcOptions.encode(o) })

        Toggle(isOn: locked) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Lock Arc positions")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Keeps every button exactly where it is. Turns on by itself after your first calibration.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .tint(MuffinTheme.pixelBlue)

        Toggle(isOn: swapHands) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Swap hands")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Mirrors Arc for left-handed play: the d-pad and left stick move to the right, the face buttons and right stick to the left.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .tint(MuffinTheme.pixelBlue)

        Toggle(isOn: fadeWhenIdle) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fade when idle")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("The controls fade almost out after a few seconds without a touch, and come straight back under your thumb.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .tint(MuffinTheme.pixelBlue)

        Button {
            arc.calibrate()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label("Calibrate Arc", systemImage: "hand.draw")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(arc.isLocked ? "Unlock to recalibrate"
                     : (arc.isLive ? "Sweep each thumb once and Arc fits every button to your reach."
                                   : "Open this from a running game to calibrate."))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .disabled(arc.isLocked || !arc.isLive)

        Button {
            arc.setFineTuning(!arc.isFineTuning)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(arc.isFineTuning ? "Done fine-tuning" : "Fine-tune positions", systemImage: "hand.point.up.left")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(arc.isLocked ? "Unlock to fine-tune"
                     : (arc.isLive ? "Drag a button along its arc, or in and out. Presses do nothing while you do."
                                   : "Open this from a running game to fine-tune."))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .disabled(arc.isLocked || !arc.isLive)

        Button(role: .destructive) { showResetConfirmation = true } label: {
            DestructiveSettingsLabel(title: "Reset Arc", systemImage: "arrow.uturn.backward")
        }
    }
}
