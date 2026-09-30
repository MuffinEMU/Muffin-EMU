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
}

public extension TouchScheme {
    var needsTicks: Bool { false }
    func tick(time: Double) -> [TouchID: Contribution] { [:] }
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
        case touchscreen   // outline of the passthrough area (debug)
    }

    public var shape: PadShape
    public var role: Role
    public var label: String
    public var lit: Bool
    /// Drawn at reduced opacity: an idle floating stick's resting spot, zone hints.
    public var ghost: Bool

    public init(shape: PadShape, role: Role, label: String = "", lit: Bool = false, ghost: Bool = false) {
        self.shape = shape
        self.role = role
        self.label = label
        self.lit = lit
        self.ghost = ghost
    }
}
