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
    @State private var showingAdaptiveReset = false

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
    @AppStorage(ControllerLayoutSettings.shoulderOffsetKey) private var shoulderOffset = ControllerLayoutSettings.defaultShoulderOffset
    @State private var showingResetConfirmation = false

    var body: some View {
        VStack {
            VStack(spacing: 10) {
                Picker("Control style", selection: $scheme) {
                    ForEach(touchLabStyleIDs, id: \.self) { id in
                        Text(id.isEmpty ? "MuffinEMU" : (TouchLabSettings.styles.first { $0.id == id }?.name ?? id))
                            .tag(id)
                    }
                }
                .pickerStyle(.segmented)

                Text("\(TouchLabSettings.summary(scheme)) These styles don't support dragging individual buttons. Nothing here reaches the game.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                    Slider(
                        value: $controlScale,
                        in: ControllerLayoutSettings.minScale...ControllerLayoutSettings.maxScale
                    )
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }

                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                    Slider(value: $controlOpacity, in: 0.2...1.0)
                    Image(systemName: "circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }

                // Hand size: both sticks move together, apart or closer. Only the styles
                // with sticks in fixed places have anything for it to move.
                if TouchLabSettings.hasFixedSticks(scheme) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.right.and.line.vertical.and.arrow.left")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                            .accessibilityHidden(true)
                        Slider(
                            value: $stickSpacing,
                            in: ControllerLayoutSettings.minStickSpacing...ControllerLayoutSettings.maxStickSpacing,
                            step: ControllerLayoutSettings.stickSpacingStep
                        )
                        .accessibilityLabel("Stick spacing")
                        .accessibilityValue(ControllerLayoutSettings.stickSpacingLabel(stickSpacing))
                        Image(systemName: "arrow.left.and.line.vertical.and.arrow.right")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                            .accessibilityHidden(true)
                    }
                }

                // L, R, ZL and ZR move up or down together. iPad only: an iPhone has no spare
                // height for it. Only the styles with fixed shoulders have anything to move.
                if ControllerLayoutSettings.supportsShoulderOffset && TouchLabSettings.hasMovableShoulders(scheme) {
                    HStack(spacing: 10) {
                        Text("L/R")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                        Image(systemName: "arrow.up.and.down")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                            .accessibilityHidden(true)
                        Slider(
                            value: $shoulderOffset,
                            in: ControllerLayoutSettings.shoulderOffsetRange(touchLab: true),
                            step: ControllerLayoutSettings.shoulderOffsetStep
                        )
                        .accessibilityLabel("Shoulder button height")
                        .accessibilityValue(ControllerLayoutSettings.shoulderOffsetLabel(shoulderOffset))
                    }
                }

                if scheme == TouchLabSettings.floatStyleID {
                    Picker("Camera", selection: $floatCamera) {
                        ForEach(TouchLabSettings.cameraOptions, id: \.value) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack(spacing: 12) {
                    Button("Reset to default") { showingResetConfirmation = true }
                        .buttonStyle(MuffinSecondaryButtonStyle())
                        .confirmationDialog("Reset controls to default?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
                            Button("Reset to default", role: .destructive, action: resetToDefault)
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text(scheme == TouchLabSettings.adaptiveStyleID
                                 ? "Size, opacity, stick spacing and shoulder height go back to how MuffinEMU ships, and Adaptive forgets where your thumbs land in this game."
                                 : "Size, opacity, stick spacing and shoulder height go back to how MuffinEMU ships.")
                        }

                    Button("Done", action: onDone)
                        .buttonStyle(MuffinSecondaryButtonStyle())
                }
            }
            .padding(14)
            .frame(maxWidth: 420)
            .background(Color.black.opacity(0.82))
            .cornerRadius(14)
            .padding(.top, 12)

            Spacer()
        }
        .transition(.opacity)
    }

    /// Size, opacity, stick spacing and shoulder height are the only placement the fixed styles have.
    /// Adaptive also moves its buttons to where your thumbs land, so for Adaptive this
    /// game's learning goes too.
    private func resetToDefault() {
        controlScale = ControllerLayoutSettings.defaultScale
        controlOpacity = ControllerLayoutSettings.defaultOpacity
        stickSpacing = ControllerLayoutSettings.defaultStickSpacing
        shoulderOffset = ControllerLayoutSettings.defaultShoulderOffset
        if scheme == TouchLabSettings.adaptiveStyleID {
            TouchLabSettings.resetAdaptive(gameID: gameID)
        }
    }
}
