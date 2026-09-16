import SwiftUI
import Combine

/// A small on-screen readout of why the pad is or is not responding.
///
/// # Why this exists
///
/// On 2026-09-16 every on-screen control was reported completely unresponsive while
/// Melo-Controller's pad kept working. That pairing is the whole clue: both overlays mount
/// at the SAME position in the same ZStack under the same `!padControlsHidden` gate, so
/// layering cannot explain it - something is choosing between them, or MuffinEMU's pad is
/// mounted but never reaching the bridge.
///
/// Three rounds of reverting by elimination could not settle which, because none of it is
/// reproducible off-device: there is no iOS SDK on the development machine, only a syntax
/// check, and the last hit-testing bug compiled, shipped and failed only under a real
/// finger. So this replaces guessing with reading the answer off the screen.
///
/// # What it shows, and why each line is here
///
/// **Active pad** - which of the three control systems is actually in the view tree.
/// `EmulatorViewOptimized` picks between them with two nested conditions, and the
/// combination that produces "MuffinEMU's pad is not mounted at all" is easy to reach and
/// invisible from the outside:
///
///     if previewPadEnabled && !useMeloControls  ->  PreviewControllerPad   (unverified)
///     else if useMeloControls                   ->  MeloControlsOverlay
///     else if !previewPadEnabled                ->  OptimizedControlPanel  (the real pad)
///
/// With `previewPadEnabled` ON and Melo-Controller OFF, the third branch is unreachable -
/// `OptimizedControlPanel` never mounts, and what is on screen is the preview pad, whose
/// own Settings footer says it has never run on a real device. Controls appear, nothing
/// happens, and nothing anywhere says why. That is exactly the reported symptom, and this
/// row is what makes it visible in one glance.
///
/// **Gates** - the four flags that decide the above, so a wrong one is readable directly
/// rather than inferred.
///
/// **Inputs** - a live count and the last event. This is the load-bearing line: it
/// separates "the pad is not receiving touches" from "the pad is receiving touches and the
/// bridge is not acting on them", which are completely different bugs and had been
/// indistinguishable all day.
///
/// # Cost
///
/// Off by default, and free when off: the counter is a plain `@Published` int bumped on an
/// event that already happens, and the overlay is not in the tree at all unless the toggle
/// is on. `.allowsHitTesting(false)` throughout - a diagnostic that could itself swallow a
/// touch would be worse than none.
@MainActor
final class PadDiagnostics: ObservableObject {
    static let shared = PadDiagnostics()

    static let enabledKey = "muffin.diagnostics.padOverlay"
    static let defaultEnabled = false

    /// Which control system is mounted. Set by whichever overlay actually appears, so this
    /// reports what IS on screen rather than what the flags imply should be.
    enum ActivePad: String {
        case none = "none mounted"
        case muffin = "MuffinEMU pad"
        case melo = "Melo-Controller"
        case preview = "Preview pad (untested)"
    }

    @Published private(set) var activePad: ActivePad = .none
    @Published private(set) var inputCount = 0
    @Published private(set) var lastInput = "-"
    @Published private(set) var stickCount = 0
    @Published private(set) var lastStick = "-"
    /// Ticks on the raw DragGesture callback inside HeldControl, before the pressed-state
    /// guard. The input counter above only moves when the state actually changes, so a
    /// frozen input count cannot tell "the gesture never fired" apart from "it fired and
    /// the state did not move". This separates them.
    @Published private(set) var rawTouchCount = 0

    /// How the last press ended, and how long it lasted.
    ///
    /// This is the line that settles the argument. A press that reverts on its own looks
    /// identical on screen whether the gesture ended, the view was removed underneath it,
    /// or the control stopped accepting touches - and those are three completely
    /// different bugs. Reading the reason off the screen beats estimating a duration by
    /// eye and reasoning backwards from the number, which is how several wrong theories
    /// got their confidence.
    enum ReleaseReason: String {
        /// DragGesture.onEnded - the ordinary path. The finger lifted, or the system
        /// cancelled the gesture.
        case fingerLifted = "finger lifted"
        /// onDisappear - the control left the view tree mid-press. Nobody touched
        /// anything; SwiftUI rebuilt the pad.
        case viewRemoved = "VIEW REMOVED under the finger"
        /// isInteractive went false - edit mode, or the app resigning active.
        case stoppedAcceptingTouches = "control stopped accepting touches"
    }

    @Published private(set) var lastRelease = "-"

    private init() {}

    func recordPressBegan() {
        // Nothing to publish yet; the interesting half is how it ends. Kept as its own
        // call so the press path reads symmetrically and a future counter has a home.
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

    /// Called from the pad's own onInput closure, on the path that already runs for every
    /// press - so if this number stays at 0 while buttons are being pressed, the touches
    /// are not reaching the pad at all, and the bug is above it in the view tree.
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

/// The overlay itself. Deliberately plain - this is a diagnostic, not a design exercise,
/// and it has to stay legible over arbitrary game content.
struct PadDiagnosticsOverlay: View {
    @ObservedObject private var diag = PadDiagnostics.shared

    let padControlsHidden: Bool
    let useMeloControls: Bool
    let previewPadEnabled: Bool
    let isEditingLayout: Bool
    let isPaused: Bool

    /// The specific combination that silently unmounts MuffinEMU's pad. Called out
    /// explicitly because every flag in it is individually reasonable - it is only the
    /// pairing that breaks, which is precisely the kind of thing a list of booleans does
    /// not make obvious.
    private var padSilentlyUnmounted: Bool {
        previewPadEnabled && !useMeloControls
    }

    /// Read once per render rather than cached: it is a couple of map lookups, it has to
    /// reflect a reset taking effect immediately, and a stale "0 bindings" would send
    /// someone chasing a bug that had already been fixed.
    private var buttonBindings: Int { Int(cemu_bridge_input_button_mapping_count()) }

    private var bindingsText: String {
        let n = buttonBindings
        if n < 0 { return "no GamePad wired" }
        if n == 0 { return "0 - THIS is why buttons are dead" }
        return "\(n) buttons"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("pad", diag.activePad.rawValue,
                warn: diag.activePad == .none || diag.activePad == .preview)

            row("inputs", "\(diag.inputCount)  last \(diag.lastInput)",
                warn: diag.inputCount == 0)
            row("stick", "\(diag.stickCount)  last \(diag.lastStick)", warn: false)
            // The decisive row: touches arriving at a button's gesture at all.
            row("touches", "\(diag.rawTouchCount)", warn: diag.rawTouchCount == 0)
            // Yellow whenever a press ended for any reason other than a finger coming
            // off, because that is always a bug and never a normal press.
            row("released", diag.lastRelease,
                warn: diag.lastRelease.contains("VIEW REMOVED")
                   || diag.lastRelease.contains("stopped accepting"))

            // The line that would have ended a day of debugging in one glance. Buttons
            // only - axes bypass the mapping table entirely, so counting them would show a
            // healthy number for exactly the broken case (sticks bound, buttons not).
            row("bindings", bindingsText, warn: buttonBindings <= 0)
            row("profile", String(cString: cemu_bridge_input_profile_name()), warn: false)

            Divider().background(Color.white.opacity(0.3))

            row("padHidden", padControlsHidden ? "YES" : "no", warn: padControlsHidden)
            row("melo", useMeloControls ? "ON" : "off", warn: false)
            row("previewPad", previewPadEnabled ? "ON" : "off", warn: previewPadEnabled)
            row("editing", isEditingLayout ? "YES" : "no", warn: isEditingLayout)
            row("paused", isPaused ? "YES" : "no", warn: isPaused)

            if padSilentlyUnmounted {
                Text("Preview pad is ON and Melo is OFF, so MuffinEMU's own pad is not mounted. Turn off Settings > Preview: New Pad System.")
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
                Text("Pad is mounted but no touch has reached it. Something above it in the view tree is taking them.")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.yellow)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 240, alignment: .leading)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.72))
        .cornerRadius(8)
        .padding(.leading, 8)
        .padding(.top, 8)
        // A diagnostic that could swallow a touch would be worse than no diagnostic.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func row(_ name: String, _ value: String, warn: Bool) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.55))
                .frame(width: 66, alignment: .leading)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(warn ? .yellow : .green)
        }
    }
}
