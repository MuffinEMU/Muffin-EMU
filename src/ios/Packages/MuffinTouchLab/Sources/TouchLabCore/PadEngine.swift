import CoreGraphics

/// Glue between raw touches, the active scheme and the mixer. The UI layer talks only to
/// this.
///
/// It also owns GamePad-touchscreen passthrough, for every scheme alike: a finger that no
/// control claims but that lands on `LayoutContext.touchscreenRect` becomes a touchscreen
/// touch for as long as it stays down, wherever it drags.
public final class PadEngine {
    public private(set) var scheme: TouchScheme
    public let mixer: PadMixer
    public private(set) var context: LayoutContext

    private enum Owner { case scheme, touchscreen }
    private var owners: [TouchID: Owner] = [:]

    public init(scheme: TouchScheme, output: PadOutput, context: LayoutContext) {
        self.scheme = scheme
        self.mixer = PadMixer(output: output)
        self.context = context
        scheme.layout(context)
    }

    public func setScheme(_ next: TouchScheme) {
        cancelAll()
        scheme = next
        next.layout(context)
    }

    public func setContext(_ next: LayoutContext) {
        guard next != context else { return }
        // Controls are about to move out from under any finger that is down; dropping
        // those fingers is better than letting them slide onto whatever lands under them.
        if mixer.liveTouches > 0 { cancelAll() }
        context = next
        scheme.layout(next)
    }

    public func claims(_ point: CGPoint) -> Bool {
        scheme.claims(point) || (context.touchscreenRect?.contains(point) ?? false)
    }

    public func began(_ touch: TouchID, at point: CGPoint, time: Double) {
        if let c = scheme.began(touch, at: point, time: time) {
            owners[touch] = .scheme
            mixer.update(touch, c)
        } else if let rect = context.touchscreenRect, rect.contains(point) {
            owners[touch] = .touchscreen
            mixer.update(touch, Contribution(touchscreen: normalise(point, in: rect)))
        }
    }

    public func moved(_ touch: TouchID, to point: CGPoint, time: Double) {
        switch owners[touch] {
        case .scheme?:
            mixer.update(touch, scheme.moved(touch, to: point, time: time))
        case .touchscreen?:
            if let rect = context.touchscreenRect {
                mixer.update(touch, Contribution(touchscreen: normalise(point, in: rect)))
            }
        case nil:
            break
        }
    }

    public func ended(_ touch: TouchID, at point: CGPoint, time: Double) {
        guard let owner = owners.removeValue(forKey: touch) else { return }
        if owner == .scheme { scheme.ended(touch, at: point, time: time) }
        mixer.remove(touch)
    }

    /// The system took a touch away (incoming call, edge gesture). Treated as an end at
    /// the last known point: the scheme must not learn from it, so no point is passed on.
    public func cancelled(_ touch: TouchID, time: Double) {
        guard let owner = owners.removeValue(forKey: touch) else { return }
        if owner == .scheme { scheme.ended(touch, at: CGPoint(x: CGFloat.nan, y: .nan), time: time) }
        mixer.remove(touch)
    }

    public func cancelAll() {
        for (touch, owner) in owners where owner == .scheme {
            scheme.ended(touch, at: CGPoint(x: CGFloat.nan, y: .nan), time: 0)
        }
        owners.removeAll()
        mixer.reset()
    }

    public var needsTicks: Bool { scheme.needsTicks }

    public func tick(time: Double) {
        for (touch, c) in scheme.tick(time: time) where owners[touch] == .scheme {
            mixer.update(touch, c)
        }
    }

    public func render() -> [RenderElement] {
        var out = scheme.render(pressed: mixer.pressed, sticks: mixer.sticks)
        if let rect = context.touchscreenRect {
            out.insert(RenderElement(shape: .roundedRect(rect, cornerRadius: 6), role: .touchscreen,
                                     lit: mixer.touchscreen != nil, ghost: true), at: 0)
        }
        return out
    }

    private func normalise(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        let q = p.clamped(to: rect)
        return CGPoint(x: (q.x - rect.minX) / max(rect.width, 1), y: (q.y - rect.minY) / max(rect.height, 1))
    }
}
