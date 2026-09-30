import CoreGraphics

/// A button on the emulated Wii U GamePad.
///
/// Raw values are `CemuBridgeButton`'s, so an adapter can convert with
/// `CemuBridgeButton(rawValue: UInt32(button.rawValue))` and never needs a lookup table.
/// Those values are baked into the bridge header and are not allowed to move; neither are
/// these.
public enum PadButton: Int, CaseIterable, Hashable, Sendable, CustomStringConvertible {
    case a = 1, b, x, y
    case l, r, zl, zr
    case plus, minus
    case up, down, left, right
    case stickL, stickR
    case home

    public var description: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"
        case .l: return "L"
        case .r: return "R"
        case .zl: return "ZL"
        case .zr: return "ZR"
        case .plus: return "+"
        case .minus: return "\u{2212}"
        case .up: return "\u{25B2}"
        case .down: return "\u{25BC}"
        case .left: return "\u{25C0}"
        case .right: return "\u{25B6}"
        case .stickL: return "L3"
        case .stickR: return "R3"
        case .home: return "\u{2302}"
        }
    }
}

/// Which analog stick. Raw values are `CemuBridgeStick`'s.
public enum PadStick: Int, CaseIterable, Hashable, Sendable {
    case left = 0
    case right = 1
}

/// A stick deflection in the CONSOLE's convention: -1...1, +x right, +y UP.
///
/// Everything inside the package works in view coordinates (+y down) and converts exactly
/// once, in `StickMath`. Nothing downstream should ever have to remember to negate y.
public struct StickValue: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = StickValue(x: 0, y: 0)

    public var magnitude: Double { (x * x + y * y).squareRoot() }
}

/// Where the pad's output goes. In MuffinEMU this is a thin shim over
/// `cemu_bridge_set_button_state` / `cemu_bridge_set_stick_axis` / `cemu_bridge_set_pad_touch`
/// (see integration/). In tests and in the demo app it is a recorder.
///
/// Calls arrive already de-duplicated and already paired: `PadMixer` only reports
/// transitions, and every press it reports is released by the time the touch that caused
/// it has ended or been cancelled.
public protocol PadOutput: AnyObject {
    func setButton(_ button: PadButton, pressed: Bool)
    func setStick(_ stick: PadStick, _ value: StickValue)
    /// The GamePad's own touchscreen. `point` is normalised to the GamePad image
    /// (0...1 on both axes, origin top-left); nil means the finger lifted.
    func setTouchscreen(_ point: CGPoint?)
    /// Everything released and both sticks centred, in one call.
    func releaseAll()
}
