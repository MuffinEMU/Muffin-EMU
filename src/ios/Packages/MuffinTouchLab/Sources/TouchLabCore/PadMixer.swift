import CoreGraphics

/// An opaque per-finger identity. UIKit's `UITouch` object is stable for the life of a
/// touch, so the UI layer uses `ObjectIdentifier(touch)`'s hash; tests just count.
public typealias TouchID = Int

/// What one finger is doing to the pad right now.
public struct Contribution: Equatable, Sendable {
    public var buttons: Set<PadButton>
    public var stick: PadStick?
    public var stickValue: StickValue
    /// Normalised GamePad-touchscreen position, when this finger is on the touchscreen.
    public var touchscreen: CGPoint?

    public init(buttons: Set<PadButton> = [],
                stick: PadStick? = nil,
                stickValue: StickValue = .zero,
                touchscreen: CGPoint? = nil) {
        self.buttons = buttons
        self.stick = stick
        self.stickValue = stickValue
        self.touchscreen = touchscreen
    }

    public static let none = Contribution()

    public static func press(_ buttons: PadButton...) -> Contribution {
        Contribution(buttons: Set(buttons))
    }
}

/// Folds every live finger's `Contribution` into one pad state and reports only the
/// transitions to a `PadOutput`.
///
/// This is where press/release pairing is enforced by construction rather than by care.
/// A button is held while ANY live finger holds it, so two fingers on A and one lifting
/// does not drop A. A finger ending removes everything it contributed, so a press cannot
/// outlive the touch that made it. Nothing in a scheme sends a release by hand, which is
/// the class of bug (a missed release = a direction held forever) the bridge header warns
/// about.
///
/// A stick belongs to the most recent finger that drove it. If that finger lifts while an
/// older one is still driving the same stick, the older one takes it back; if none is left
/// the stick goes to (0,0), which the bridge reads as "not overridden".
public final class PadMixer {
    public let output: PadOutput

    public private(set) var pressed: Set<PadButton> = []
    public private(set) var sticks: [PadStick: StickValue] = [:]
    public private(set) var touchscreen: CGPoint?

    private var contributions: [TouchID: Contribution] = [:]
    /// Order in which fingers last claimed each stick, newest last.
    private var stickOwners: [PadStick: [TouchID]] = [:]
    private var touchscreenOwner: TouchID?

    public init(output: PadOutput) {
        self.output = output
    }

    public var liveTouches: Int { contributions.count }

    public func contribution(for touch: TouchID) -> Contribution? {
        contributions[touch]
    }

    public func update(_ touch: TouchID, _ contribution: Contribution) {
        let previous = contributions[touch]
        contributions[touch] = contribution

        if let stick = contribution.stick, previous?.stick != stick {
            if let old = previous?.stick { stickOwners[old]?.removeAll { $0 == touch } }
            stickOwners[stick, default: []].removeAll { $0 == touch }
            stickOwners[stick, default: []].append(touch)
        } else if contribution.stick == nil, let old = previous?.stick {
            stickOwners[old]?.removeAll { $0 == touch }
        }

        if contribution.touchscreen != nil, touchscreenOwner == nil {
            touchscreenOwner = touch
        }
        flush()
    }

    public func remove(_ touch: TouchID) {
        guard let previous = contributions.removeValue(forKey: touch) else { return }
        if let stick = previous.stick { stickOwners[stick]?.removeAll { $0 == touch } }
        if touchscreenOwner == touch { touchscreenOwner = nil }
        flush()
    }

    /// Drops every finger at once. Used when the UI can no longer track touches to their
    /// natural end (view leaving the window, app resigning active, system gesture).
    public func reset() {
        contributions.removeAll()
        stickOwners.removeAll()
        touchscreenOwner = nil
        let hadAnything = !pressed.isEmpty || sticks.values.contains { $0 != .zero } || touchscreen != nil
        pressed = []
        sticks = [:]
        touchscreen = nil
        if hadAnything { output.releaseAll() }
        // releaseAll covers buttons and sticks; the touchscreen is its own call.
        output.setTouchscreen(nil)
    }

    private func flush() {
        var nextPressed = Set<PadButton>()
        for c in contributions.values { nextPressed.formUnion(c.buttons) }

        for b in PadButton.allCases {
            let was = pressed.contains(b), now = nextPressed.contains(b)
            if was != now { output.setButton(b, pressed: now) }
        }
        pressed = nextPressed

        for stick in PadStick.allCases {
            let owner = stickOwners[stick]?.last
            let value = owner.flatMap { contributions[$0]?.stickValue } ?? .zero
            if (sticks[stick] ?? .zero) != value {
                sticks[stick] = value
                output.setStick(stick, value)
            }
        }

        let screen = touchscreenOwner.flatMap { contributions[$0]?.touchscreen }
        if screen != touchscreen {
            touchscreen = screen
            output.setTouchscreen(screen)
        }
    }
}
