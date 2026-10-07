// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import Combine

/// Optional on-screen readout for diagnosing controls: which pad is mounted, whether
/// touches arrive, and current bindings. Off by default, and not in the view tree when
/// off. The overlay never takes touches.
@MainActor
final class PadDiagnostics: ObservableObject {
    static let shared = PadDiagnostics()

    static let enabledKey = "muffin.diagnostics.padOverlay"
    static let defaultEnabled = false

    /// Which control system is mounted, set by whichever overlay actually appears.
    enum ActivePad: String {
        case none = "none mounted"
        case muffin = "MuffinEMU pad"
        case melo = "Melo-Controller"
        case touchLab = "TouchLab pad"
        case preview = "Preview pad (untested)"
    }

    @Published private(set) var activePad: ActivePad = .none
    @Published private(set) var inputCount = 0
    @Published private(set) var lastInput = "-"
    @Published private(set) var stickCount = 0
    @Published private(set) var lastStick = "-"
    /// Ticks on every touch callback inside HeldControl, so a frozen input count can be
    /// told apart as "no touches arrived" versus "touches arrived but state didn't change".
    @Published private(set) var rawTouchCount = 0

    /// How the last press ended, and how long it lasted.
    enum ReleaseReason: String {
        /// DragGesture.onEnded - the ordinary path. The finger lifted.
        case fingerLifted = "finger lifted"
        /// The system cancelled the gesture (swipe, banner, app switch) and the press
        /// was released without a lift.
        case gestureCancelled = "gesture cancelled by system"
        /// onDisappear - the control left the view tree mid-press. Nobody touched
        /// anything; SwiftUI rebuilt the pad.
        case viewRemoved = "VIEW REMOVED under the finger"
        /// isInteractive went false - edit mode, or the app resigning active.
        case stoppedAcceptingTouches = "control stopped accepting touches"
    }

    @Published private(set) var lastRelease = "-"

    private init() {}

    func recordPressBegan() {
        // Nothing to publish; kept so the press and release paths are symmetric.
    }

    func recordRelease(_ reason: ReleaseReason, heldSince began: Date) {
        let ms = Int(Date().timeIntervalSince(began) * 1000)
        lastRelease = "\(ms)ms, \(reason.rawValue)"
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? Self.defaultEnabled
    }

    func report(activePad: ActivePad) {
        guard self.activePad != activePad else { return }
        self.activePad = activePad
    }

    /// Called from the pad's onInput closure. If this stays at 0 while buttons are
    /// pressed, touches aren't reaching the pad.
    func recordInput(_ label: String, _ pressed: Bool) {
        inputCount += 1
        lastInput = "\(label) \(pressed ? "down" : "up")"
    }

    func recordRawTouch() {
        rawTouchCount += 1
    }

    func recordStick(_ stick: Int, _ position: CGPoint) {
        stickCount += 1
        lastStick = String(format: "s%d (%.2f, %.2f)", stick, position.x, position.y)
    }
}

/// The overlay itself: plain, and legible over game content.
struct PadDiagnosticsOverlay: View {
    @ObservedObject private var diag = PadDiagnostics.shared

    let padControlsHidden: Bool
    let useMeloControls: Bool
    let previewPadEnabled: Bool
    /// The stored TouchLab control style id; "" means MuffinEMU's own pad.
    var touchLabScheme: String = ""
    let isEditingLayout: Bool
    let isPaused: Bool

    /// Read on every render so a reset shows up immediately.
    private var buttonBindings: Int { Int(cemu_bridge_input_button_mapping_count()) }

    private var bindingsText: String {
        let n = buttonBindings
        if n < 0 { return "no GamePad wired" }
        if n == 0 { return "0 - buttons have no bindings" }
        return "\(n) buttons"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("pad", diag.activePad.rawValue,
                warn: diag.activePad == .none || diag.activePad == .preview)

            row("inputs", "\(diag.inputCount)  last \(diag.lastInput)",
                warn: diag.inputCount == 0)
            row("stick", "\(diag.stickCount)  last \(diag.lastStick)", warn: false)
            // Touches arriving at a button's gesture at all.
            row("touches", "\(diag.rawTouchCount)", warn: diag.rawTouchCount == 0)
            // Yellow when a press ended because the view was removed or stopped accepting
            // touches.
            row("released", diag.lastRelease,
                warn: diag.lastRelease.contains("VIEW REMOVED")
                   || diag.lastRelease.contains("stopped accepting"))

            // Buttons only: axes bypass the mapping table.
            row("bindings", bindingsText, warn: buttonBindings <= 0)
            row("profile", String(cString: cemu_bridge_input_profile_name()), warn: false)

            Divider().background(Color.white.opacity(0.3))

            row("padHidden", padControlsHidden ? "YES" : "no", warn: padControlsHidden)
            row("melo", useMeloControls ? "ON" : "off", warn: false)
            row("previewPad", previewPadEnabled ? "ON" : "off", warn: previewPadEnabled)
            row("touchLab", touchLabScheme.isEmpty ? "off" : touchLabScheme, warn: false)
            row("editing", isEditingLayout ? "YES" : "no", warn: isEditingLayout)
            row("paused", isPaused ? "YES" : "no", warn: isPaused)

            if diag.activePad == .preview {
                Text("The experimental new pad is active. If controls don't respond, turn it off in Settings.")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.yellow)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 240, alignment: .leading)
            } else if buttonBindings == 0 {
                Text("The GamePad has no button bindings, so presses go nowhere while sticks still work. Settings > On-screen Controls > Reset controller bindings.")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.yellow)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 240, alignment: .leading)
            } else if diag.inputCount == 0 && diag.activePad == .muffin {
                Text("Pad is mounted but no touches are reaching it.")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.yellow)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 240, alignment: .leading)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
        .padding(.leading, 8)
        .padding(.top, 8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func row(_ name: String, _ value: String, warn: Bool) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 66, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(warn ? .yellow : .green)
        }
    }
}
