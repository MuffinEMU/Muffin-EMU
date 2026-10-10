import SwiftUI
import UIKit
import TouchLabCore

/// How far off a button a touch still counts. Chosen in Settings.
enum TouchTolerance: Int, CaseIterable, Identifiable {
    case normal = 0, generous = 1, veryGenerous = 2

    static let defaultValue = TouchTolerance.generous
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .generous: return "Generous"
        case .veryGenerous: return "Very generous"
        }
    }

    /// Reach beyond the drawn edge, as a multiple of the button's radius.
    var reachFactor: CGFloat {
        switch self {
        case .normal: return 1.15
        case .generous: return 1.4
        case .veryGenerous: return 1.7
        }
    }

    /// Points a touch is nudged toward where the thumb's contact lands.
    var biasPoints: CGFloat {
        switch self {
        case .normal: return 0
        case .generous: return 3
        case .veryGenerous: return 6
        }
    }
}

struct PadTouchTarget: Equatable {
    let id: String
    let centre: CGPoint
    let halfSize: CGSize
    let isCircle: Bool
}

/// Which controls are drawn pressed. A release stays lit for `minimumLook` so a quick tap is
/// still seen; the game gets the release at once.
final class PadPressModel: ObservableObject {
    @Published private(set) var lit: Set<String> = []
    private var pressedAt: [String: Date] = [:]
    private static let minimumLook: TimeInterval = 0.09

    func pressed(_ id: String) {
        pressedAt[id] = Date()
        lit.insert(id)
    }

    func released(_ id: String) {
        let remaining = Self.minimumLook - Date().timeIntervalSince(pressedAt[id] ?? .distantPast)
        guard remaining > 0 else { lit.remove(id); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak self] in
            guard let self, let at = self.pressedAt[id], Date().timeIntervalSince(at) >= Self.minimumLook else { return }
            self.lit.remove(id)
        }
    }
}

/// One UIKit view owns every finger on a cluster. Each touch is assigned to the nearest
/// button (see HitResolver), follows the finger onto the next button, and counts as an area
/// when the system reports one. Hit testing is explicit: nothing is padded or inset.
final class PadTouchUIView: UIView {
    var targets: [HitTarget] = []
    var reachFactor: CGFloat = 1.4
    var bias: CGPoint = .zero
    var enabled = true { didSet { if !enabled { releaseAll() } } }
    private static let maxContact: CGFloat = 20
    var onChange: (String, Bool) -> Void = { _, _ in }

    private var assigned: [ObjectIdentifier: String] = [:]
    private var counts: [String: Int] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Invariant: hitTest claims a touch only if the same resolver touchesBegan uses (same
    /// parameters, the touch's own contact when the event has it, else the maximum) yields a button.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard enabled, !isHidden else { return nil }
        let touch = event?.allTouches?.first { $0.phase == .began && $0.view === self && hypot($0.location(in: self).x - point.x, $0.location(in: self).y - point.y) < 0.5 }
        let contact = touch.map { Self.contact(of: $0) } ?? Self.maxContact
        return resolve(point, contact: contact, current: nil) != nil ? self : nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { releaseAll() }
    }

    /// The contact area is half the reported major radius, capped so a palm does not reach.
    private static func contact(of touch: UITouch) -> CGFloat {
        touch.majorRadius > 0 ? min(touch.majorRadius, 40) / 2 : 0
    }

    private func resolve(_ point: CGPoint, contact: CGFloat, current: String?) -> String? {
        HitResolver.resolve(point, targets: targets, reachFactor: reachFactor,
                            contactRadius: contact, bias: bias, current: current)
    }

    private func resolve(_ touch: UITouch, current: String?) -> String? {
        resolve(touch.location(in: self), contact: Self.contact(of: touch), current: current)
    }

    private func retain(_ id: String) {
        counts[id, default: 0] += 1
        if counts[id] == 1 { onChange(id, true) }
    }

    private func release(_ id: String) {
        guard let n = counts[id] else { return }
        if n <= 1 { counts[id] = nil; onChange(id, false) } else { counts[id] = n - 1 }
    }

    private func releaseAll() {
        let ids = Array(assigned.values)
        assigned.removeAll()
        for id in ids { release(id) }
        for id in Array(counts.keys) { counts[id] = nil; onChange(id, false) }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if let id = resolve(t, current: nil) {
                assigned[ObjectIdentifier(t)] = id
                retain(id)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            let key = ObjectIdentifier(t)
            let old = assigned[key]
            let new = resolve(t, current: old)
            guard new != old else { continue }
            if let new { assigned[key] = new; retain(new) } else { assigned[key] = nil }
            if let old { release(old) }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches {
            if let id = assigned.removeValue(forKey: ObjectIdentifier(t)) { release(id) }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}

struct PadTouchSurface: UIViewRepresentable {
    let targets: [PadTouchTarget]
    let enabled: Bool
    let tolerance: TouchTolerance
    /// The side the thumb comes from: the left cluster nudges right and down, the right one left and down.
    let leading: Bool
    let onChange: (String, Bool) -> Void

    func makeUIView(context: Context) -> PadTouchUIView { PadTouchUIView() }

    func updateUIView(_ view: PadTouchUIView, context: Context) {
        view.targets = targets.map { HitTarget(id: $0.id, centre: $0.centre, halfSize: $0.halfSize, isCircle: $0.isCircle) }
        view.reachFactor = tolerance.reachFactor
        view.bias = CGPoint(x: leading ? tolerance.biasPoints : -tolerance.biasPoints, y: tolerance.biasPoints)
        view.onChange = onChange
        view.enabled = enabled
    }

    static func dismantleUIView(_ view: PadTouchUIView, coordinator: ()) {
        view.enabled = false
    }
}
