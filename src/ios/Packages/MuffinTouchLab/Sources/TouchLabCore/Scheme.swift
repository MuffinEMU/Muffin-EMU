import CoreGraphics

public struct SchemeInfo: Equatable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
}

/// One touch-control scheme. Everything is in view points, +y down.
///
/// A scheme only decides what each finger means. It never talks to the output: it
/// returns a `Contribution` per finger and `PadEngine` hands that to `PadMixer`, which
/// owns pairing and de-duplication. So a scheme bug can produce a wrong press, but not a
/// press that outlives its finger.
public protocol TouchScheme: AnyObject {
    var info: SchemeInfo { get }

    func layout(_ context: LayoutContext)

    /// Would a finger landing here be taken by a control? The UI layer uses this in
    /// hitTest so touches nothing wants fall through to whatever is under the pad.
    func claims(_ point: CGPoint) -> Bool

    /// nil = not ours.
    func began(_ touch: TouchID, at point: CGPoint, time: Double) -> Contribution?
    func moved(_ touch: TouchID, to point: CGPoint, time: Double) -> Contribution
    func ended(_ touch: TouchID, at point: CGPoint, time: Double)

    /// Schemes whose output changes while a finger is held still (swipe-camera decay)
    /// ask for ticks; the UI drives them from a display link only while this is true.
    var needsTicks: Bool { get }
    func tick(time: Double) -> [TouchID: Contribution]

    func render(pressed: Set<PadButton>, sticks: [PadStick: StickValue]) -> [RenderElement]

    /// Input that belongs to no finger: a button held for the player (auto-accelerate) or a
    /// stick driven by the device's motion. `PadEngine` re-reads it after every touch event
    /// and feeds it to the mixer under one fixed identity, so it is released with everything
    /// else and never outlives the pad.
    func ambient() -> Contribution?

    /// True while the scheme steers from the device's motion. The UI layer then runs the
    /// motion sensor and calls `motion(angle:)`.
    var wantsMotion: Bool { get }

    /// A new wheel angle from the device's motion, in radians, positive clockwise as the
    /// player sees the screen. Returns the contributions of fingers whose output changed
    /// because of it.
    func motion(angle: Double) -> [TouchID: Contribution]
}

public extension TouchScheme {
    var needsTicks: Bool { false }
    func tick(time: Double) -> [TouchID: Contribution] { [:] }
    func ambient() -> Contribution? { nil }
    var wantsMotion: Bool { false }
    func motion(angle: Double) -> [TouchID: Contribution] { [:] }
}

/// What to draw. Kept platform-free so the same list feeds UIKit on device and the SVG
/// renderer used for the previews and layout checks.
public struct RenderElement: Equatable, Sendable {
    public enum Role: Equatable, Sendable {
        case face          // A/B/X/Y
        case dpad          // one arm of the cross
        case shoulder      // L/R/ZL/ZR
        case system        // +/-/HOME
        case dot           // L3/R3 click dots
        case stickBase
        case stickKnob
        case zone          // a floating control's catchment, drawn faintly
        case area          // a catchment that is always drawn, faintly (Racing's steering area)
        case pedal         // a large held zone; drawn lighter than a button so it leaves the game visible
        case touchscreen   // outline of the passthrough area (debug)
        case guide         // a line along `path`: Arc's arc band, sweep trace, fitted-arc preview, snap ticks
        case handle        // a drag handle shown while a layout can be moved
    }

    /// `.standard` is the flat look every scheme shares. `.refined` is Arc's: a hairline
    /// outline, a soft shadow, a lit rim and a pressed state that sinks (see `RefinedLook`).
    public enum Style: Equatable, Sendable { case standard, refined }

    /// Accent for guides and handles.
    public enum Tone: Equatable, Sendable { case neutral, accent, good, warn }

    public var shape: PadShape
    public var role: Role
    public var label: String
    public var lit: Bool
    /// Drawn at reduced opacity: an idle floating stick's resting spot, zone hints.
    public var ghost: Bool
    public var style: Style
    public var tone: Tone
    /// Multiplies the drawn opacity (1 = as is). Lets a scheme rest its controls dim.
    public var fade: CGFloat
    /// `.guide` only: the polyline, in view points.
    public var path: [CGPoint]
    /// `.guide` only: stroke width in points.
    public var width: CGFloat
    /// `.guide` only: dash length in points, 0 = solid.
    public var dash: CGFloat

    public init(shape: PadShape, role: Role, label: String = "", lit: Bool = false, ghost: Bool = false,
                style: Style = .standard, tone: Tone = .neutral, fade: CGFloat = 1,
                path: [CGPoint] = [], width: CGFloat = 0, dash: CGFloat = 0) {
        self.shape = shape
        self.role = role
        self.label = label
        self.lit = lit
        self.ghost = ghost
        self.style = style
        self.tone = tone
        self.fade = fade
        self.path = path
        self.width = width
        self.dash = dash
    }
}
