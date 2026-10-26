// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

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
    if id.isEmpty { return isDefault ? "MuffinEMU (default)".localized : "MuffinEMU (classic)".localized }
    let name = TouchLabSettings.styles.first { $0.id == id }?.name ?? id
    return isDefault ? String(format: "%@ (default)".localized, name) : name
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
    @AppStorage(TouchLabSettings.showcaseStyleKey) private var showcaseStyle = true
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
                if useMeloControls && MeloControlsSetting.isAvailable {
                    Text(String(format: "Melo-Controller is switched on below, so it is showing instead. Switch it off to use %@.".localized, TouchLabSettings.name(scheme)))
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

                if scheme != TouchLabSettings.showcaseStyleID {
                    Toggle(isOn: $showcaseStyle) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Showcase style")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text("The polished look on every control style: hairline outlines, soft shadows, a lit rim and buttons that sink when pressed. Off keeps the flat look.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(MuffinTheme.pixelBlue)
                }

                if TouchLabSettings.usesClassicLook(scheme) && showcaseStyle {
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
                            Text(String(format: "%d%%".localized, Int((aScale * 100).rounded())))
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reset A button size")
                        .accessibilityValue(String(format: "%d percent".localized, Int((aScale * 100).rounded())))
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
                        DestructiveSettingsLabel(title: "Reset learned layouts".localized, systemImage: "arrow.uturn.backward")
                    }
                }

                // Zone can be edited (its own rows in the in-game panel), so it doesn't get the "no dragging" line.
                Text((scheme == TouchLabSettings.zoneStyleID ? "" : "These styles don't support dragging individual buttons. ".localized) + "Size, opacity, haptics and the stick options below apply to them.".localized)
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
            : "MuffinEMU's measured GamePad layout, which you can also drag around.".localized
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
    // The same look settings as Settings > On-screen Controls, so the change can be judged on the live pad.
    @AppStorage(TouchLabSettings.showcaseStyleKey) private var showcaseStyle = true
    @AppStorage(TouchLabSettings.classicColourKey) private var classicColour = TouchLabSettings.defaultClassicColour
    @AppStorage(TouchLabSettings.showcaseColourKey) private var showcaseColour = TouchLabSettings.defaultShowcaseColour
    @AppStorage(TouchLabSettings.showcaseGlassKey) private var showcaseGlass = false
    @AppStorage(TouchLabSettings.aScaleKey) private var aScale = TouchLabSettings.defaultAScale
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
                    ? "Size, opacity, stick spacing and shoulder height go back to how MuffinEMU ships in every game, and Adaptive forgets where your thumbs land in this game only.".localized
                    : "Size, opacity, stick spacing and shoulder height go back to how MuffinEMU ships, in every game.".localized,
                onReset: resetToDefault,
                onDone: onDone)
        })
    }

    @ViewBuilder private var rows: some View {
        TouchLabStylePicker()

        PanelCaption(text: String(format: scheme == TouchLabSettings.zoneStyleID ? "%@ Nothing here reaches the game.".localized : "%@ These styles don't support dragging individual buttons. Nothing here reaches the game.".localized, TouchLabSettings.summary(scheme)))

        if scheme == TouchLabSettings.zoneStyleID { ZoneEditRows(gameID: gameID) }

        lookRows

        PanelSliderRow("Button size".localized, leadingIcon: "minus.magnifyingglass", trailingIcon: "plus.magnifyingglass",
                       value: $controlScale,
                       range: ControllerLayoutSettings.minScale...ControllerLayoutSettings.maxScale)

        PanelSliderRow("Opacity".localized, leadingIcon: "circle.lefthalf.filled", trailingIcon: "circle.fill",
                       value: $controlOpacity, range: 0.2...1.0)

        // As in Settings: Arc places every button by your reach and Showcase is the GamePad at its real
        // size, so neither has a separate A size. The buttons around A shrink a little to make room.
        if scheme != TouchLabSettings.arcStyleID && scheme != TouchLabSettings.showcaseStyleID {
            PanelSliderRow("A button size".localized, title: "A size".localized, leadingIcon: "a.circle", trailingIcon: "a.circle.fill",
                           value: $aScale, range: TouchLabSettings.aScaleRange, step: 0.01,
                           spokenValue: String(format: "%d percent".localized, Int((aScale * 100).rounded())),
                           readout: String(format: "%d%%".localized, Int((aScale * 100).rounded())))
        }

        // Hand size: both sticks move together, apart or closer. Only the styles with sticks
        // in fixed places have anything for it to move.
        if TouchLabSettings.hasFixedSticks(scheme) {
            PanelSliderRow("Stick spacing".localized,
                           leadingIcon: "arrow.right.and.line.vertical.and.arrow.left",
                           trailingIcon: "arrow.left.and.line.vertical.and.arrow.right",
                           value: $stickSpacing,
                           range: ControllerLayoutSettings.minStickSpacing...ControllerLayoutSettings.maxStickSpacing,
                           step: ControllerLayoutSettings.stickSpacingStep,
                           spokenValue: ControllerLayoutSettings.stickSpacingLabel(stickSpacing))
        }

        // Each stick on its own: deadzones, sensitivity, invert and a test circle.
        FineTuneSticksRow()

        // L, R, ZL and ZR move up or down together. iPad only: an iPhone has no spare height
        // for it. Only the styles with fixed shoulders have anything to move.
        if ControllerLayoutSettings.supportsShoulderOffset && TouchLabSettings.hasMovableShoulders(scheme) {
            PanelSliderRow(shoulderStore.label(in: windowSize.effectiveSize, touchLab: true), title: "L/R".localized, leadingIcon: "arrow.up.and.down",
                           value: shoulderBinding,
                           range: ControllerLayoutSettings.shoulderOffsetRange(touchLab: true, in: windowSize.effectiveSize),
                           step: ControllerLayoutSettings.shoulderOffsetStep,
                           spokenValue: ControllerLayoutSettings.shoulderOffsetLabel(max(0, shoulderBinding.wrappedValue)))
            PanelToggle(title: "Same height in portrait and landscape".localized,
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
            // Calibrating and fine-tuning happen on the pad, so the panel closes first.
            ArcSettingsRows(showResetConfirmation: $showingArcReset, beforeStart: onDone)
                .confirmationDialog("Reset Arc?", isPresented: $showingArcReset, titleVisibility: .visible) {
                    Button("Reset Arc", role: .destructive) { ArcLive.shared.reset() }
                    Button("Cancel", role: .cancel) { }
                }
        }

        PanelCaption(text: isAdaptive
                     ? "These settings apply to every game, except that Adaptive remembers where your thumbs land separately for each game.".localized
                     : "These settings apply to every game.".localized,
                     prominent: false)
    }

    /// Showcase style on or off and its colours, as in Settings. Showcase itself is always in that look,
    /// so it has no switch, only its colour and glass.
    @ViewBuilder private var lookRows: some View {
        if scheme != TouchLabSettings.showcaseStyleID {
            PanelToggle(title: "Showcase style".localized, isOn: $showcaseStyle)
        }
        if TouchLabSettings.usesClassicLook(scheme) && showcaseStyle {
            colourPicker(selection: $classicColour, options: TouchLabSettings.classicColourOptions)
        }
        if scheme == TouchLabSettings.showcaseStyleID {
            colourPicker(selection: $showcaseColour, options: TouchLabSettings.showcaseColourOptions)
            PanelToggle(title: "Glass look".localized, isOn: $showcaseGlass)
        }
    }

    private func colourPicker(selection: Binding<String>, options: [(value: String, title: String)]) -> some View {
        HStack {
            Text("Colour")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            Picker("Colour", selection: selection) {
                ForEach(options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(MuffinTheme.pixelBlue)
        }
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
    /// Runs just before calibration or fine-tuning starts, so the in-game panel can close and leave
    /// the pad free to take the sweep (the panel and the pad would otherwise both be on screen).
    var beforeStart: (() -> Void)? = nil
    @AppStorage(TouchLabSettings.arcOptionsKey) private var optionsRaw = "{}"

    var body: some View {
        let locked = Binding<Bool>(get: { arc.isLocked }, set: { arc.setLocked($0) })
        let swapHands = Binding<Bool>(
            get: { TouchLabSettings.arcSwapHands(optionsRaw) },
            set: { optionsRaw = TouchLabSettings.arcOptions(optionsRaw, swapHands: $0) })
        let fadeWhenIdle = Binding<Bool>(
            get: { TouchLabSettings.arcFadesWhenIdle(optionsRaw) },
            set: { optionsRaw = TouchLabSettings.arcOptions(optionsRaw, fadesWhenIdle: $0) })

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
            guard arc.blocker(for: .calibrate) == nil else { return }
            beforeStart?()
            arc.calibrate()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label("Calibrate Arc", systemImage: "hand.draw")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(arc.blocker(for: .calibrate) ?? "Sweep each thumb once and Arc fits every button to your reach.".localized)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .disabled(arc.blocker(for: .calibrate) != nil)

        Button {
            guard arc.isFineTuning || arc.blocker(for: .fineTune) == nil else { return }
            if !arc.isFineTuning { beforeStart?() }
            arc.setFineTuning(!arc.isFineTuning)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(arc.isFineTuning ? "Done fine-tuning".localized : "Fine-tune positions".localized, systemImage: "hand.point.up.left")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(arc.blocker(for: .fineTune) ?? "Drag a button along its arc, or in and out. Presses do nothing while you do.".localized)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .disabled(!arc.isFineTuning && arc.blocker(for: .fineTune) != nil)

        Button(role: .destructive) { showResetConfirmation = true } label: {
            DestructiveSettingsLabel(title: "Reset Arc".localized, systemImage: "arrow.uturn.backward")
        }
    }
}
