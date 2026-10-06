import SwiftUI
import UIKit

// Auto-hide for the in-game top bar (Back, the button row, the frame rate).
//
// WHY THE BAR FLOATS AND NEVER RESIZES ANYTHING
//
// The bar already floats over the video, so hiding it changes no layout: it fades and
// slides up, and the video, the pad and DisplayRouter's sizing stay exactly where they
// were. The bar's measured height is kept while it is hidden for the same reason. The pads
// reserve that band so no control lands under Back and pause, and a pad that re-flowed
// every time the bar hid would move the buttons under a player's thumbs. Only things that
// are purely informational (the core's FPS and notification cards) move up into the freed
// space.
//
// WHERE THE HANDLE SITS
//
// Centred on the top edge of the safe area, inside the band the bar vacates. Every pad
// keeps its controls below that band, and all of them hang off the left and right edges,
// so the top centre is the one place on screen with nothing interactive in it.

enum TopBarAutoHide {
    /// Stored as a small integer so "never chosen" is a real third state. Nothing stored
    /// follows the device; a choice that matches the device's own default is stored as
    /// "follow" again, so changing device class later still behaves sensibly.
    static let overrideKey = "muffin.topBar.autoHideOverride"
    static let followDevice = 0
    static let forceOn = 1
    static let forceOff = 2

    /// How long the bar stays after the last touch on it.
    static let hideDelayNanoseconds: UInt64 = 4_000_000_000

    /// On everywhere. It was iPhone-only at first, but on an iPad the bar sitting over the picture
    /// for a whole session read as a bug, not a choice. Kept as a property so a device class can
    /// differ again without touching the stored-override logic.
    static var deviceDefault: Bool { true }

    static func isOn(override: Int) -> Bool {
        switch override {
        case forceOn: return true
        case forceOff: return false
        default: return deviceDefault
        }
    }

    static func override(forChoice on: Bool) -> Int {
        on == deviceDefault ? followDevice : (on ? forceOn : forceOff)
    }
}

/// The fade and slide. Applied to the bar itself and always BEFORE the modifier that
/// measures it, so the measurement is of the bar's layout frame and not of where the
/// effect has drawn it.
struct TopBarHidingEffect: ViewModifier {
    let hidden: Bool
    /// The bar's measured bottom edge, which is more than enough to carry it off screen.
    let slideDistance: CGFloat
    let slides: Bool

    func body(content: Content) -> some View {
        content
            .offset(y: hidden && slides ? -(slideDistance + 8) : 0)
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}

/// The pill that brings the bar back: a tap, or a swipe down. A 220 by 72 point target
/// around a small, faint pill, so it is easy to hit without looking and easy to ignore.
/// The frame itself is what grows (never negative padding: hit testing clips to the frame).
struct TopBarRevealHandle: View {
    let onReveal: () -> Void

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.45))
            // A hairline of shadow so it still reads over a white title screen.
            .shadow(color: Color.black.opacity(0.4), radius: 1, x: 0, y: 0.5)
            .frame(width: 40, height: 5)
            .padding(.top, 6)
            .frame(width: 220, height: 72, alignment: .top)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onEnded { value in
                    // A tap, or a swipe that ends lower than it began. A swipe up is not a request.
                    if value.translation.height > -12 { onReveal() }
                }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Show top bar")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onReveal() }
    }
}

/// The look of MuffinSecondaryButtonStyle with a 44 by 44 point touch target. The visible
/// button keeps its size and sits in the middle of the target; only the part that
/// responds to a finger grows. `highlighted` is the on state some bar buttons carry (Blow).
struct MuffinBarButtonStyle: ButtonStyle {
    var highlighted = false

    func makeBody(configuration: Configuration) -> some View {
        MuffinSecondaryButtonStyle().makeBody(configuration: configuration)
            .overlay(tint)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    private var tint: some View {
        let shape = RoundedRectangle(cornerRadius: MuffinTheme.Radius.chip, style: .continuous)
        return shape
            .fill(MuffinTheme.pixelBlue.opacity(highlighted ? 0.28 : 0))
            .overlay(shape.strokeBorder(MuffinTheme.pixelBlue.opacity(highlighted ? 0.9 : 0), lineWidth: 1.5))
            .allowsHitTesting(false)
    }
}

extension View {
    func topBarAutoHideEffect(hidden: Bool, slideDistance: CGFloat, slides: Bool) -> some View {
        modifier(TopBarHidingEffect(hidden: hidden, slideDistance: slideDistance, slides: slides))
    }
}
