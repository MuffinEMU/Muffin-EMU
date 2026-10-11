import CoreGraphics
import Foundation

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

    /// The identity under which the scheme's ambient input (a button held for the player, a
    /// stick driven by the device's motion) is mixed. Real touches are hashes of object
    /// addresses, so this value can't collide with one.
    public static let ambientID: TouchID = Int.min

    /// False while the pad shouldn't be holding anything for the player: paused, off screen,
    /// app inactive. Turning it off drops the ambient input at once.
    public var ambientEnabled = true {
        didSet { if ambientEnabled != oldValue { syncAmbient() } }
    }

    /// How long a pressed look stays on screen at least, in seconds. A tap shorter than a
    /// frame, or one whose down and up are handled together after the main thread stalled,
    /// is still drawn pressed once. Drawing only: nothing sent to the game waits on this.
    public var minimumLitDuration: Double = 0.09
    /// Seconds on a monotonic clock. Replaceable so checks can drive time by hand.
    public var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    private var litSince: [PadButton: Double] = [:]
    private var litSeen: Set<PadButton> = []

    public init(scheme: TouchScheme, output: PadOutput, context: LayoutContext) {
        self.scheme = scheme
        self.mixer = PadMixer(output: output)
        self.context = context
        scheme.layout(context)
        syncAmbient()
    }

    public func setScheme(_ next: TouchScheme) {
        cancelAll()
        scheme = next
        next.layout(context)
        syncAmbient()
    }

    public func setContext(_ next: LayoutContext) {
        guard next != context else { return }
        // Controls are about to move out from under any finger that is down; dropping
        // those fingers is better than letting them slide onto whatever lands under them.
        if !owners.isEmpty { cancelAll() }
        context = next
        scheme.layout(next)
        syncAmbient()
    }

    public func claims(_ point: CGPoint) -> Bool {
        scheme.claims(point) || (context.touchscreenRect?.contains(point) ?? false)
    }

    public func began(_ touch: TouchID, at point: CGPoint, time: Double) {
        // UIKit can hand a new finger the identity of one whose end never arrived. Whatever
        // that stale finger held must go first, or it outlives the new touch (a touch no
        // control claims would never replace it).
        if owners[touch] != nil { cancelled(touch, time: time) }
        if let c = scheme.began(touch, at: point, time: time) {
            owners[touch] = .scheme
            mixer.update(touch, c)
        } else if let rect = context.touchscreenRect, rect.contains(point) {
            owners[touch] = .touchscreen
            mixer.update(touch, Contribution(touchscreen: normalise(point, in: rect)))
        }
        settled()
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
        settled()
    }

    public func ended(_ touch: TouchID, at point: CGPoint, time: Double) {
        guard let owner = owners.removeValue(forKey: touch) else { return }
        if owner == .scheme { scheme.ended(touch, at: point, time: time) }
        mixer.remove(touch)
        settled()
    }

    /// The system took a touch away (incoming call, edge gesture). Treated as an end at
    /// the last known point: the scheme must not learn from it, so no point is passed on.
    public func cancelled(_ touch: TouchID, time: Double) {
        guard let owner = owners.removeValue(forKey: touch) else { return }
        if owner == .scheme { scheme.ended(touch, at: CGPoint(x: CGFloat.nan, y: .nan), time: time) }
        mixer.remove(touch)
        settled()
    }

    /// The fingers the engine is holding something for.
    public var heldTouches: Set<TouchID> { Set(owners.keys) }

    /// Releases every finger not in `live`: a touch whose end or cancel the view never saw.
    /// Called with the system's own list of live touches whenever a new finger lands.
    public func reconcile(live: Set<TouchID>) {
        for touch in owners.keys where !live.contains(touch) { cancelled(touch, time: 0) }
    }

    public func cancelAll() {
        for (touch, owner) in owners where owner == .scheme {
            scheme.ended(touch, at: CGPoint(x: CGFloat.nan, y: .nan), time: 0)
        }
        owners.removeAll()
        mixer.reset()
        settled()
    }

    public var needsTicks: Bool { scheme.needsTicks }

    public func tick(time: Double) {
        for (touch, c) in scheme.tick(time: time) where owners[touch] == .scheme {
            mixer.update(touch, c)
        }
        settled()
    }

    /// A new wheel angle from the device's motion (see `TouchScheme.motion(angle:)`).
    public func motion(angle: Double) {
        for (touch, c) in scheme.motion(angle: angle) where owners[touch] == .scheme {
            mixer.update(touch, c)
        }
        settled()
    }

    /// Re-reads the scheme's ambient input. Called after every change that could alter it.
    public func syncAmbient() {
        let wanted = ambientEnabled ? scheme.ambient() : nil
        if let wanted {
            if mixer.contribution(for: Self.ambientID) != wanted { mixer.update(Self.ambientID, wanted) }
        } else if mixer.contribution(for: Self.ambientID) != nil {
            mixer.remove(Self.ambientID)
        }
        noteLit()
    }

    private func settled() { syncAmbient() }

    /// Remembers when each button first showed as pressed, for `minimumLitDuration`.
    private func noteLit() {
        let now = mixer.pressed
        if now != litSeen {
            let at = clock()
            for b in now.subtracting(litSeen) { litSince[b] = at }
            litSeen = now
        }
    }

    /// Buttons to draw as pressed: the ones held, plus any that were pressed too recently to
    /// have been shown yet.
    public func litButtons() -> Set<PadButton> {
        var lit = mixer.pressed
        guard !litSince.isEmpty else { return lit }
        let t = clock()
        for (b, since) in litSince {
            if t - since < minimumLitDuration { lit.insert(b) } else if !mixer.pressed.contains(b) { litSince[b] = nil }
        }
        return lit
    }

    /// The soonest moment after which a button now drawn pressed only because of
    /// `minimumLitDuration` should be drawn released, or nil when nothing is held on by it.
    public func nextLitExpiry() -> Double? {
        let t = clock()
        return litSince.filter { !mixer.pressed.contains($0.key) && t - $0.value < minimumLitDuration }
            .map { $0.value + minimumLitDuration }.min()
    }

    public func render() -> [RenderElement] {
        var out = scheme.render(pressed: litButtons(), sticks: mixer.sticks)
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
