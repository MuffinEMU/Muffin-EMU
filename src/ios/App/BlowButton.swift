import SwiftUI
import AVFoundation
import UIKit

/// Microphone permission, in one place: the Audio settings toggle asks through `request`, and
/// the in-game top bar reads `status` to decide whether real-mic mode is actually usable.
enum MicrophoneAccess {
    static var status: AVAudioSession.RecordPermission {
        AVAudioSession.sharedInstance().recordPermission
    }

    /// Calls `completion` on the main queue. Shows the system prompt only the first time
    /// (status undetermined); afterwards iOS answers from the stored decision.
    static func request(_ completion: @escaping (Bool) -> Void) {
        switch status {
        case .granted:
            DispatchQueue.main.async { completion(true) }
        case .denied:
            DispatchQueue.main.async { completion(false) }
        default:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        }
    }

    static func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// The in-game "Blow" control: simulates blowing into the GamePad microphone (Captain Toad,
/// Super Mario 3D World, NSMBU, Zelda...). Styled as one of the top bar's secondary buttons.
///
/// Gesture rule: a short tap latches blowing on or off; pressing and holding for
/// `holdThreshold` blows only while the finger stays down and stops on release. A hold never
/// changes the latch, and a press that turns into a scroll (the top bar scrolls when it
/// overflows) does nothing.
///
/// Implemented as a Button with an empty action plus a simultaneous zero-distance drag, not
/// as the Button's own action: a Button fires its action on release even after a long press,
/// which would latch at the end of every hold. The drag drives a @GestureState, which iOS
/// resets on cancellation as well as on release, so a press that is interrupted (app
/// switch, scroll takeover) can't leave the blow stuck on.
struct BlowButton: View {
    /// Identifies the running title; a change means the old title (and its mic) is gone.
    let titleID: String

    private static let holdThreshold: TimeInterval = 0.35
    private static let moveTolerance: CGFloat = 12

    private struct Press: Equatable {
        var down = false
        var moved = false
    }

    @GestureState private var press = Press()
    @State private var latched = false
    @State private var momentary = false
    @State private var cancelledByMove = false
    @State private var holdWork: DispatchWorkItem?

    private let syncTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    private var active: Bool { latched || momentary }

    var body: some View {
        Button(action: {}) {
            Image(systemName: "wind")
                .font(.system(size: 12, weight: .semibold))
                // Against the button's cream at text strength, so the icon still reads
                // once the on-state tint below darkens or lightens what is behind it.
                .foregroundColor(active
                                 ? LegibleInk.ensure(MuffinTheme.pixelBlue, on: MuffinTheme.cream)
                                 : MuffinTheme.brownDark)
        }
        // The on state is a tint inside the style, over the button's own fill, so it still
        // follows the theme and the pressed/disabled treatment, and stays the size of the
        // button rather than the larger touch target around it.
        .buttonStyle(MuffinBarButtonStyle(highlighted: active))
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($press) { value, state, _ in
                    state.down = true
                    if hypot(value.translation.width, value.translation.height) > Self.moveTolerance {
                        state.moved = true
                    }
                }
        )
        .onChange(of: press.down) { down in
            down ? pressBegan() : pressEnded()
        }
        .onChange(of: press.moved) { moved in
            if moved { cancelledByMove = true; cancelPendingHold() }
        }
        .onChange(of: titleID) { _ in reset() }
        .onDisappear { reset() }
        // The core clears the blow when the title that owned the mic goes away. Pick that up
        // so the button doesn't keep showing "on" for a blow nothing is feeding.
        .onReceive(syncTimer) { _ in
            if latched && !cemu_bridge_mic_blow() { latched = false }
        }
        .accessibilityLabel("Blow")
        .accessibilityValue(active ? "On" : "Off")
        .accessibilityHint("Simulates blowing into the GamePad microphone. Tap to turn blowing on or off. Touch and hold to blow only while you hold.")
        .accessibilityAddTraits(active ? .isSelected : [])
        // VoiceOver users can't hold, so the tap is also exposed as the default action.
        .accessibilityAction { latched.toggle(); apply() }
    }

    private func pressBegan() {
        cancelledByMove = false
        let work = DispatchWorkItem {
            momentary = true
            apply()
            MuffinHaptics.tap()
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdThreshold, execute: work)
    }

    private func pressEnded() {
        cancelPendingHold()
        if momentary {
            momentary = false           // back to whatever the latch says
            apply()
        } else if !cancelledByMove {
            latched.toggle()
            apply()
        }
    }

    private func cancelPendingHold() {
        holdWork?.cancel()
        holdWork = nil
    }

    private func reset() {
        cancelPendingHold()
        latched = false
        momentary = false
        cemu_bridge_set_mic_blow(false)
    }

    private func apply() {
        cemu_bridge_set_mic_blow(active)
    }
}

/// Keeps the in-game top bar's button group on one row at any width. The bar used to be a
/// plain HStack: on a narrow iPhone the group had nowhere to go, so the buttons squeezed
/// and overlapped the title and the FPS readout.
///
/// When the group fits, it is laid out as the plain row it always was - no scroll view at
/// all. A scroll view here, even one that can't scroll, picks up iOS 26's scroll edge
/// effect, which draws a blur across whatever sits at its edges: here, every button in the
/// bar. Only when the row genuinely doesn't fit does it fall back to scrolling, with that
/// edge effect turned off.
struct TopBarOverflowScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                ViewThatFits(in: .horizontal) {
                    content()
                        .fixedSize(horizontal: true, vertical: false)
                    scrolling
                }
            } else {
                // No ViewThatFits before iOS 16. Those versions have no scroll edge effect
                // either, so the scrolling row has no blur to draw there.
                scrolling
            }
        }
        .layoutPriority(1)
    }

    private var scrolling: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content()
        }
        .topBarNoScrollEdgeEffect()
    }
}

private extension View {
    @ViewBuilder func topBarNoScrollEdgeEffect() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
