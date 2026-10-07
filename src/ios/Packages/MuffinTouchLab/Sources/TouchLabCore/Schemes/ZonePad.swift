import CoreGraphics

/// Scheme 1 - Zone Pad.
///
/// The conservative replacement: the real GamePad's arrangement (sticks above the
/// d-pad and face buttons, shoulders along the top edge), with the input rebuilt so a
/// thumb that is roughly right counts:
///
/// - Every control has catchment past its drawn edge and the nearest one wins, so there
///   are no dead gaps between buttons and nothing depends on SwiftUI hit testing.
/// - The d-pad is one eight-way control read from the thumb's angle, with wider
///   sectors for the four cardinals - diagonals are deliberate, not accidental.
/// - Rolling a thumb across A/B/X/Y (or L/ZL) moves the press without lifting, and a thumb
///   resting in the gap between two face buttons presses both.
/// - Pressing the d-pad's centre dot is L3, the face diamond's is R3, as on the shipping pad.
public final class ZonePad: ControlScheme {
    public static let schemeInfo = SchemeInfo(
        id: "zone",
        name: "Zone",
        summary: "The GamePad's own layout with forgiving, gap-free touch zones, slide between buttons and two-button presses.")

    /// A is about 1.4 times its usual size, with a wider catchment; the other face buttons
    /// shrink a little to make room and the diamond moves in to stay on screen.
    public let largeA: Bool

    public init(largeA: Bool = false) {
        self.largeA = largeA
        super.init(info: Self.schemeInfo)
    }

    override public func makeControls(_ context: LayoutContext) -> [PadControl] {
        GamePadArrangement.build(context, largeA: largeA)
    }
}
