import CoreGraphics
import Foundation
import TouchLabCore

// Behaviour and layout checks. Exit status is the number of failures, so CI fails on any.

final class Recorder: PadOutput {
    var log: [String] = []
    var held: Set<PadButton> = []
    var sticks: [PadStick: StickValue] = [:]
    var screen: CGPoint?
    func setButton(_ button: PadButton, pressed: Bool) {
        log.append("\(button)\(pressed ? "+" : "-")")
        if pressed { held.insert(button) } else { held.remove(button) }
    }
    func setStick(_ stick: PadStick, _ value: StickValue) { sticks[stick] = value }
    func setTouchscreen(_ point: CGPoint?) { screen = point }
    func releaseAll() { log.append("releaseAll"); held = []; sticks = [:] }
}

var failures = 0
var passes = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    if ok { passes += 1 } else { failures += 1; print("FAIL: \(what())") }
}
func near(_ a: Double, _ b: Double, _ tol: Double = 0.02) -> Bool { abs(a - b) <= tol }

// MARK: Mixer

do {
    let r = Recorder(), m = PadMixer(output: r)
    m.update(1, .press(.a)); m.update(2, .press(.a))
    m.remove(1)
    check(r.held == [.a], "A must stay held while a second finger holds it")
    m.remove(2)
    check(r.held.isEmpty && r.log == ["A+", "A-"], "exactly one press and one release, got \(r.log)")

    m.update(3, Contribution(stick: .left, stickValue: StickValue(x: 0.5, y: 0)))
    m.update(4, Contribution(stick: .left, stickValue: StickValue(x: -1, y: 0)))
    check(r.sticks[.left] == StickValue(x: -1, y: 0), "newest finger owns the stick")
    m.remove(4)
    check(r.sticks[.left] == StickValue(x: 0.5, y: 0), "older finger takes the stick back")
    m.remove(3)
    check(r.sticks[.left] == .zero, "stick centres when its last finger lifts")

    m.update(5, .press(.b, .zr))
    m.reset()
    check(r.log.last == "releaseAll" && m.pressed.isEmpty, "reset releases everything")
}

// MARK: Stick and d-pad maths

do {
    let t = StickTuning(deadzone: 0.1, curve: 1, gate: .round)
    let up = StickMath.value(offset: CGPoint(x: 0, y: -100), travel: 100, tuning: t)
    check(near(up.y, 1) && near(up.x, 0), "finger up the screen = +y (console convention), got \(up)")
    let dz = StickMath.value(offset: CGPoint(x: 9, y: 0), travel: 100, tuning: t)
    check(dz == .zero, "inside deadzone = zero")
    let justOut = StickMath.value(offset: CGPoint(x: 15, y: 0), travel: 100, tuning: t)
    check(justOut.x > 0 && justOut.x < 0.1, "deadzone is rescaled, not a jump: \(justOut.x)")
    let oct = StickTuning(deadzone: 0, curve: 1, gate: .octagon)
    let flat = StickMath.value(offset: CGPoint(x: 200 * cos(CGFloat.pi / 8), y: -200 * sin(CGFloat.pi / 8)), travel: 100, tuning: oct)
    check(near(flat.magnitude, cos(Double.pi / 8), 0.01), "octagon flat caps at cos(22.5deg): \(flat.magnitude)")
    let diag = StickMath.value(offset: CGPoint(x: 200, y: -200), travel: 100, tuning: oct)
    check(near(diag.magnitude, 1, 0.01), "octagon vertex reaches full travel")

    func dirs(_ deg: Double) -> Set<PadButton> { DPadMath.directions(angle: CGFloat(deg * .pi / 180)) }
    check(dirs(0) == [.right] && dirs(90) == [.up] && dirs(180) == [.left] && dirs(-90) == [.down], "cardinals")
    check(dirs(20) == [.right], "20deg is still right (wide cardinals)")
    check(dirs(45) == [.right, .up] && dirs(-135) == [.left, .down] && dirs(135) == [.left, .up], "diagonals")
    check(dirs(-179) == [.left] && dirs(179) == [.left], "wraps at 180")
}

// MARK: Layouts on every device

for info in SchemeCatalog.all {
    for device in TargetDevice.all {
        for display in TargetDevice.Display.allCases {
            let scheme = SchemeCatalog.make(info.id) as! ControlScheme
            let ctx = device.context(display)
            scheme.layout(ctx)
            let where_ = "\(info.name) / \(device.name) / \(display.rawValue)"
            let problems = LayoutCheck.problems(scheme.controls, in: ctx.safeBounds)
            check(problems.isEmpty, "\(where_): \(problems.joined(separator: "; "))")

            // Every GamePad input must be reachable somehow.
            var reachable = Set<PadButton>()
            var stickCount = 0
            for c in scheme.controls {
                switch c.kind {
                case .button(let b): reachable.insert(b)
                case .dpad(let click, _, _, _):
                    reachable.formUnion([.up, .down, .left, .right]); if let click { reachable.insert(click) }
                case .stick(_, _, let click), .floatingStick(_, _, _, _, let click):
                    stickCount += 1; if let click { reachable.insert(click) }
                case .swipeStick: stickCount += 1
                case .pedal(let set): reachable.formUnion(set)
                case .steer: stickCount += 1
                case .recentre: break
                }
            }
            // Racing is for one game's controls: only the buttons Mario Kart 8 uses and the one
            // stick it steers with. Every other scheme must reach the whole GamePad.
            let required: Set<PadButton> = info.id == RacingPad.schemeInfo.id
                ? [.a, .b, .x, .l, .r, .plus, .home] : Set(PadButton.allCases)
            let missing = required.subtracting(reachable)
            check(missing.isEmpty, "\(where_): unreachable \(missing.map(\.description).sorted())")
            check(stickCount == (info.id == RacingPad.schemeInfo.id ? 1 : 2), "\(where_): \(stickCount) sticks")

            if let frame = scheme as? FramePad, frame.mode != .overlay {
                for c in scheme.controls where !c.isZone {
                    for v in ctx.videoRects where v.insetBy(dx: 1, dy: 1).intersects(c.shape.boundingBox) {
                        check(false, "\(where_): Frame control \(c.label) covers the video")
                    }
                }
            }
        }
    }
}

// MARK: Any window size
// iPad Split View, Slide Over, Stage Manager and iOS 26+ free-form windows can hand the pad
// almost any size. Sweep a grid of them: every layout must still fit without overlaps.

for info in SchemeCatalog.all {
    var bad: [String] = []
    var w: CGFloat = 480
    while w <= 1400 {
        var h: CGFloat = 300
        while h <= 1100 {
            let ctx = LayoutContext(size: CGSize(width: w, height: h),
                                    safeInsets: Insets(top: 20, left: 0, bottom: 20, right: 0))
            let scheme = SchemeCatalog.make(info.id) as! ControlScheme
            scheme.layout(ctx)
            let p = LayoutCheck.problems(scheme.controls, in: ctx.safeBounds)
            if !p.isEmpty { bad.append("\(Int(w))x\(Int(h)): \(p.first!)") }
            h += 80
        }
        w += 70
    }
    check(bad.isEmpty, "\(info.name): \(bad.count) window sizes fail, e.g. \(bad.prefix(3).joined(separator: " | "))")
}

// MARK: Racing layouts with each option, on every device

for options in [RacingPad.Options(), RacingPad.Options(autoAccelerate: true), RacingPad.Options(tilt: true),
                RacingPad.Options(autoAccelerate: true, tilt: true)] {
    for device in TargetDevice.all {
        for display in TargetDevice.Display.allCases {
            let scheme = RacingPad(options: options)
            let ctx = device.context(display)
            scheme.layout(ctx)
            let where_ = "Racing \(options) / \(device.name) / \(display.rawValue)"
            check(LayoutCheck.problems(scheme.controls, in: ctx.safeBounds).isEmpty,
                  "\(where_): \(LayoutCheck.problems(scheme.controls, in: ctx.safeBounds).joined(separator: "; "))")
            // Thumb-sized: the pedal the thumb rests on is never smaller than a 44 point target.
            if let a = scheme.controls.first(where: { if case .pedal(let s) = $0.kind { return s == [.a] }; return false }) {
                let b = a.shape.boundingBox
                check(b.width >= 44 && b.height >= 44, "\(where_): accelerate zone \(Int(b.width))x\(Int(b.height)) is smaller than a thumb")
            } else { check(false, "\(where_): no accelerate zone") }
            check(scheme.controls.contains { if case .steer = $0.kind { return true }; return false }, "\(where_): no steering area")
        }
    }
}

// MARK: A button size
// The slider runs 1.0...1.8 in 0.01 steps on every style. A must only ever grow with it, with
// no jump between adjacent steps, and stay on screen and clear of its neighbours at the top.

func aWidth(_ scheme: ControlScheme) -> CGFloat {
    let a = scheme.controls.first {
        if case .pedal(let set) = $0.kind { return set == [.a] }
        return $0.button == .a
    }
    return a?.shape.boundingBox.width ?? 0
}

for device in ["iPad Pro 11 (A12Z)", "iPhone 16"].compactMap({ name in TargetDevice.all.first { $0.name == name } }) {
    for display in TargetDevice.Display.allCases {
        let ctx = device.context(display)
        for info in SchemeCatalog.all {
            let where_ = "A size / \(info.name) / \(device.name) / \(display.rawValue)"
            func laidOut(_ a: CGFloat) -> ControlScheme {
                let s = SchemeCatalog.make(info.id, aScale: a) as! ControlScheme
                s.layout(ctx)
                return s
            }
            var prev = aWidth(laidOut(1))
            check(prev > 0, "\(where_): no A control")
            for step in 1...80 {
                let w = aWidth(laidOut(1 + CGFloat(step) / 100))
                check(w >= prev - 0.001, "\(where_): A shrank \(prev) -> \(w) at \(1 + Double(step) / 100)")
                check(w <= prev * 1.02 + 0.001, "\(where_): A jumped \(prev) -> \(w) at \(1 + Double(step) / 100)")
                prev = w
            }
            let top = laidOut(1.8)
            let problems = LayoutCheck.problems(top.controls, in: ctx.safeBounds)
            check(problems.isEmpty, "\(where_) at 1.8: \(problems.joined(separator: "; "))")
            check(aWidth(top) >= aWidth(laidOut(1)) * 1.2, "\(where_): A grew only \(aWidth(top) / aWidth(laidOut(1)))x")
        }
    }
}

// MARK: Stick spacing
// The hand-size setting moves the sticks apart or together. Every value the app's slider
// can send must still give a layout with no overlaps, on every target device, and must
// actually move the sticks where there is room to.

for device in TargetDevice.all {
    for id in ["zone", "adaptive", "frame"] {
        let base = device.context(.stacked)
        let home = SchemeCatalog.make(id) as! ControlScheme
        home.layout(base)
        let homeGap = abs(home.controls.first { $0.label == "R" && $0.role == .stickBase }!.shape.center.x
                          - home.controls.first { $0.label == "L" && $0.role == .stickBase }!.shape.center.x)
        var gaps: [CGFloat] = []
        for spacing: CGFloat in [-3, -1.5, 1.5] {
            var ctx = base
            ctx.stickSpacing = spacing
            let scheme = SchemeCatalog.make(id) as! ControlScheme
            scheme.layout(ctx)
            let p = LayoutCheck.problems(scheme.controls, in: ctx.safeBounds)
            check(p.isEmpty, "\(device.name) \(id) spacing \(spacing): \(p.first ?? "")")
            let gap = abs(scheme.controls.first { $0.label == "R" && $0.role == .stickBase }!.shape.center.x
                          - scheme.controls.first { $0.label == "L" && $0.role == .stickBase }!.shape.center.x)
            check(spacing < 0 ? gap <= homeGap + 0.5 : gap >= homeGap - 0.5,
                  "\(device.name) \(id) spacing \(spacing): moved the wrong way (\(homeGap) -> \(gap))")
            gaps.append(gap)
        }
        // More inward never ends up further apart than less inward.
        check(gaps[0] <= gaps[1] + 0.5, "\(device.name) \(id): spacing -3 gives a wider gap (\(gaps[0])) than -1.5 (\(gaps[1]))")
    }
}

// MARK: Shoulder offset
// The iPad-only slider drops L, R, ZL and ZR together. Every value the slider can send must
// give a layout with no overlaps, keep the four shoulders level and in the same shape as
// each other, never move them up, and never leave them above their home position.

func shoulderRects(_ scheme: ControlScheme) -> [PadButton: CGRect] {
    var out: [PadButton: CGRect] = [:]
    for c in scheme.controls where c.role == .shoulder {
        if let b = c.button { out[b] = c.shape.boundingBox }
    }
    return out
}

for device in TargetDevice.all {
    for id in ["zone", "adaptive"] {
        let base = device.context(.stacked)
        let home = SchemeCatalog.make(id) as! ControlScheme
        home.layout(base)
        let homeRects = shoulderRects(home)
        check(homeRects.count == 4, "\(device.name) \(id): \(homeRects.count) shoulders at home")
        var drops: [CGFloat] = []
        for offset: CGFloat in [-2, 0.5, 1, 1.5, 3] {
            var ctx = base
            ctx.shoulderOffset = offset
            let scheme = SchemeCatalog.make(id) as! ControlScheme
            scheme.layout(ctx)
            let p = LayoutCheck.problems(scheme.controls, in: ctx.safeBounds)
            check(p.isEmpty, "\(device.name) \(id) shoulder offset \(offset): \(p.first ?? "")")
            let rects = shoulderRects(scheme)
            guard rects.count == 4, homeRects.count == 4 else { continue }
            let drop = rects[.zl]!.minY - homeRects[.zl]!.minY
            drops.append(drop)
            for (b, r) in rects {
                check(abs((r.minY - homeRects[b]!.minY) - drop) < 0.5,
                      "\(device.name) \(id) shoulder offset \(offset): \(b) not level with ZL")
                check(abs(r.minX - homeRects[b]!.minX) < 0.5 && abs(r.width - homeRects[b]!.width) < 0.5,
                      "\(device.name) \(id) shoulder offset \(offset): \(b) moved sideways or resized")
            }
            check(drop >= -0.5, "\(device.name) \(id) shoulder offset \(offset): moved up (\(drop))")
            if offset <= 0 { check(abs(drop) < 0.5, "\(device.name) \(id) shoulder offset \(offset): moved (\(drop))") }
        }
        // The mini's pad is already squeezed to fit (its sticks leave under a point of room
        // below the shoulders), so there it correctly stays put.
        if device.name.contains("iPad") && !device.name.contains("mini") {
            check((drops.last ?? 0) > 4, "\(device.name) \(id): the shoulders have no room to move down (\(drops))")
        }
        // More requested never ends up lower than less requested.
        if drops.count == 5 {
            check(drops[1] <= drops[2] + 0.5 && drops[2] <= drops[3] + 0.5 && drops[3] <= drops[4] + 0.5,
                  "\(device.name) \(id): shoulder drop not monotonic \(drops)")
        }
    }
}

// MARK: Shoulder offset, upright iPad
// The same iPad held upright (1024 x 1366) has far more room below the shoulders than held
// sideways, and the slider's upright range follows it: the largest drop is bigger than in
// landscape, everything stays on screen, and with the pictures stacked the shoulders stop in
// front of the GamePad touchscreen instead of covering it.

for id in ["zone", "adaptive"] {
    let insets = Insets(top: 24, bottom: 20)
    func drop(_ size: CGSize, request: CGFloat, display: TargetDevice.Display?) -> (CGFloat, [String], CGRect?, CGRect?) {
        let dev = TargetDevice(name: "iPad 1366", size: size, insets: insets)
        var ctx = display.map { dev.context($0) } ?? LayoutContext(size: size, safeInsets: insets)
        let home = SchemeCatalog.make(id) as! ControlScheme
        home.layout(ctx)
        ctx.shoulderOffset = request
        let scheme = SchemeCatalog.make(id) as! ControlScheme
        scheme.layout(ctx)
        let d = shoulderRects(scheme)[.zl]!.minY - shoulderRects(home)[.zl]!.minY
        let zl = shoulderRects(scheme)[.zl]
        return (d, LayoutCheck.problems(scheme.controls, in: ctx.safeBounds), zl, ctx.touchscreenRect)
    }
    let landscape = drop(CGSize(width: 1366, height: 1024), request: 20, display: nil)
    let upright = drop(CGSize(width: 1024, height: 1366), request: 20, display: nil)
    check(upright.1.isEmpty, "upright iPad \(id): \(upright.1.first ?? "")")
    check(upright.0 > landscape.0 + 50, "upright iPad \(id): max drop \(upright.0) not larger than landscape \(landscape.0)")
    // Stacked: the lowered shoulders stay clear of the GamePad touchscreen.
    let stacked = drop(CGSize(width: 1024, height: 1366), request: 20, display: .stacked)
    check(stacked.1.isEmpty, "upright iPad \(id) stacked: \(stacked.1.first ?? "")")
    if let zl = stacked.2, let gp = stacked.3 {
        check(!zl.intersects(gp), "upright iPad \(id) stacked: shoulders cover the GamePad screen")
        check(stacked.0 > 1.5 * 72, "upright iPad \(id) stacked: only moved \(stacked.0)")
    }
}

// MARK: Behaviour, through the engine, on the A12Z iPad

let ipad = TargetDevice.all.first { $0.name.contains("A12Z") }!

func engine(_ id: String, _ display: TargetDevice.Display = .stacked) -> (PadEngine, Recorder, ControlScheme) {
    let r = Recorder()
    let e = PadEngine(scheme: SchemeCatalog.make(id), output: r, context: ipad.context(display))
    return (e, r, e.scheme as! ControlScheme)
}
func centre(_ s: ControlScheme, _ b: PadButton) -> CGPoint {
    s.controls.first { $0.button == b }!.shape.center
}
func tap(_ e: PadEngine, _ p: CGPoint, id: TouchID = 1, t: Double = 0) {
    e.began(id, at: p, time: t); e.ended(id, at: p, time: t + 0.1)
}

// MARK: Stick overtravel
do {
    let travel: CGFloat = 100
    let extra = StickMath.overtravel(travel)
    check(extra > 0 && extra <= 0.2 * travel, "overtravel is a small fraction of travel: \(extra)")
    let round = StickTuning(deadzone: 0.06, curve: 1, gate: .round)
    let oct = StickTuning(deadzone: 0.06, curve: 1, gate: .octagon)
    for tuning in [round, oct] {
        let g = tuning.gate
        for deg in stride(from: 0.0, to: 360.0, by: 15.0) {
            let a = CGFloat(deg * .pi / 180)
            let dir = CGPoint(x: cos(a), y: sin(a))
            let lim = StickMath.gateFraction(g, angle: a)
            let atEdge = StickMath.value(offset: dir * travel, travel: travel, tuning: tuning)
            let past = StickMath.value(offset: dir * (travel + 3 * extra), travel: travel, tuning: tuning)
            check(near(atEdge.magnitude, Double(lim), 1e-6), "edge value is the gate limit at \(deg)deg (\(g)): \(atEdge.magnitude)")
            check(near(past.magnitude, atEdge.magnitude, 1e-9) && abs(past.x) <= 1 && abs(past.y) <= 1,
                  "beyond the edge adds no output at \(deg)deg (\(g))")
            let knob = StickMath.knobOffset(offset: dir * (travel + 3 * extra), travel: travel, gate: g)
            check(near(Double(knob.length), Double(travel * lim + extra), 1e-3), "knob stops at gate + overtravel at \(deg)deg (\(g))")
            let inside = StickMath.knobOffset(offset: dir * (travel * 0.5), travel: travel, gate: g)
            check(near(Double(inside.length), Double(travel * 0.5), 1e-3), "knob follows the finger inside the ring")
        }
    }
    check(near(StickMath.value(offset: CGPoint(x: travel, y: 0), travel: travel, tuning: round).x, 1, 1e-9), "exact boundary = exactly 1")
    check(StickMath.value(offset: CGPoint(x: 3, y: -3), travel: travel, tuning: round) == .zero, "recentred finger is inside the deadzone")
}

do {
    let (e, r, s) = engine("zone", .stacked)
    let left = s.controls.first { if case .stick(.left, _, _) = $0.kind { return true }; return false }!
    let right = s.controls.first { if case .stick(.right, _, _) = $0.kind { return true }; return false }!
    guard case let .stick(_, travel, _) = left.kind else { fatalError() }
    let extra = StickMath.overtravel(travel)
    let lc = left.shape.center, rc = right.shape.center
    e.began(1, at: lc, time: 0)
    e.began(2, at: rc, time: 0)
    e.moved(1, to: lc + CGPoint(x: travel, y: 0), time: 0.1)
    check(near(r.sticks[.left]?.x ?? 0, 1, 1e-9), "overtravel: left at boundary is exactly 1, got \(String(describing: r.sticks[.left]))")
    e.moved(1, to: lc + CGPoint(x: travel + extra * 0.8, y: 0), time: 0.2)
    check(near(r.sticks[.left]?.x ?? 0, 1, 1e-9), "overtravel: left past the boundary stays 1")
    e.moved(2, to: rc + CGPoint(x: 0, y: -(travel + 5 * extra)), time: 0.2)
    check(near(r.sticks[.right]?.y ?? 0, 1, 1e-9) && near(r.sticks[.right]?.x ?? 1, 0, 1e-9), "overtravel: right far up is (0,1)")
    check(near(r.sticks[.left]?.x ?? 0, 1, 1e-9), "overtravel: left unaffected by the right finger")
    let knobs = e.render().filter { $0.role == .stickKnob }
    let lk = knobs.first { $0.shape.center.distance(to: lc) < 3 * travel && abs($0.shape.center.y - lc.y) < 1 }
    check(lk != nil && near(Double(lk!.shape.center.x - lc.x), Double(travel + extra * 0.8), 1e-3), "overtravel: left knob follows past the ring")
    let rk = knobs.first { $0.shape.center.distance(to: rc) < 3 * travel && abs($0.shape.center.x - rc.x) < 1 }
    check(rk != nil && near(Double(rc.y - rk!.shape.center.y), Double(travel + extra), 1e-3), "overtravel: right knob stops at travel + overtravel")
    e.moved(1, to: lc + CGPoint(x: 8, y: -8), time: 0.3)
    check(near(r.sticks[.right]?.y ?? 0, 1, 1e-9), "overtravel: right still held while left moves")
    e.moved(1, to: lc, time: 0.4)
    check(r.sticks[.left] == .zero, "overtravel: left recentres to zero")
    e.ended(2, at: rc, time: 0.5)
    check(r.sticks[.right] == .zero, "overtravel: right recentres on release")
    e.ended(1, at: lc, time: 0.6)
}


for id in ["zone", "adaptive", "frame", "float"] {
    let (e, r, s) = engine(id)
    for b in [PadButton.a, .b, .x, .y, .l, .r, .zl, .zr, .plus, .minus, .home] {
        r.log = []
        e.began(1, at: centre(s, b), time: 0)
        check(r.held == [b], "\(id): tap \(b) holds exactly \(b), got \(r.held)")
        e.ended(1, at: centre(s, b), time: 0.1)
        check(r.held.isEmpty, "\(id): \(b) released")
        _ = (s as? AdaptivePad)?.resetLearning()
    }

    // Slide A -> B without lifting.
    let a = centre(s, .a), b = centre(s, .b)
    e.began(1, at: a, time: 0)
    e.moved(1, to: b, time: 0.1)
    check(r.held == [.b], "\(id): slide A to B, got \(r.held)")
    e.cancelled(1, time: 0.2)
    check(r.held.isEmpty, "\(id): cancel releases")

    // Chord in the gap between A and B.
    let unit = s.controls.first { $0.button == .a }!.shape.boundingBox.width
    let dir = (b - a) * (1 / b.distance(to: a))
    let gapMid = a + dir * (b.distance(to: a) / 2)
    e.began(2, at: gapMid, time: 1)
    check(r.held == [.a, .b], "\(id): thumb between A and B presses both, got \(r.held) (unit \(unit))")
    e.ended(2, at: gapMid, time: 1.1)
}

do {
    let (e, r, s) = engine("zone")
    let dpad = s.controls.first { if case .dpad = $0.kind { return true }; return false }!
    let c = dpad.shape.center
    let u = s.controls.first { $0.button == .a }!.shape.boundingBox.width
    e.began(1, at: c + CGPoint(x: 1.2 * u, y: -1.2 * u), time: 0)
    check(r.held == [.up, .right], "zone: d-pad up-right diagonal, got \(r.held)")
    e.moved(1, to: c + CGPoint(x: 0, y: 1.1 * u), time: 0.05)
    check(r.held == [.down], "zone: d-pad rolls to down, got \(r.held)")
    e.ended(1, at: c, time: 0.1)
    e.began(1, at: c, time: 1)
    check(r.held == [.stickL], "zone: d-pad centre dot is L3, got \(r.held)")
    e.ended(1, at: c, time: 1.1)

    let stick = s.controls.first { if case .stick(.left, _, _) = $0.kind { return true }; return false }!
    e.began(3, at: stick.shape.center, time: 2)
    e.moved(3, to: stick.shape.center + CGPoint(x: 400, y: 0), time: 2.1)
    check(near(r.sticks[.left]?.x ?? 0, 1), "zone: left stick full right, got \(String(describing: r.sticks[.left]))")
    e.ended(3, at: .zero, time: 2.2)
    check(r.sticks[.left] == .zero, "zone: stick recentres")

    // Touchscreen passthrough.
    let pad = ipad.context(.stacked).touchscreenRect!
    let p = CGPoint(x: pad.minX + pad.width * 0.25, y: pad.minY + pad.height * 0.75)
    if !s.claims(p) {
        e.began(9, at: p, time: 3)
        check(near(Double(r.screen?.x ?? -1), 0.25) && near(Double(r.screen?.y ?? -1), 0.75),
              "zone: GamePad touch normalised, got \(String(describing: r.screen))")
        e.ended(9, at: p, time: 3.1)
        check(r.screen == nil, "zone: touchscreen lifts")
    }
}

do {
    let (e, r, s) = engine("float", .single)
    // Float over a single screen: pick a spot in the left zone that is off the GamePad.
    let zone = s.controls.first { if case .floatingStick(.left, _, _, _, _) = $0.kind { return true }; return false }!
    let ts = ipad.context(.single).touchscreenRect!
    let box = zone.shape.boundingBox
    let p = CGPoint(x: box.minX + 40, y: min(box.maxY - 40, ts.minY - 1 > box.minY ? ts.minY - 20 : box.maxY - 40))
    let landing = ts.contains(p) ? CGPoint(x: box.minX + 20, y: box.maxY - 5) : p
    e.began(1, at: landing, time: 0)
    check(r.sticks[.left] == nil || r.sticks[.left] == .zero, "float: stick is centred under the thumb on landing")
    let drawn = e.render()
    check(!drawn.contains { $0.role == .stickBase }, "float: no stick ring is drawn")
    check(drawn.contains { $0.role == .dot && $0.shape.center == landing }, "float: anchor dot where the thumb landed")
    check(drawn.filter { $0.role == .stickKnob }.count == 1, "float: only the active knob is drawn")
    e.moved(1, to: landing + CGPoint(x: 300, y: 0), time: 0.1)
    check((r.sticks[.left]?.x ?? 0) > 0.9, "float: drag right = full right, got \(String(describing: r.sticks[.left]))")
    let knob = e.render().first { $0.role == .stickKnob }!.shape.center
    let travel = PadParts.stickTravel * s.controls.first { $0.button == .a }!.shape.boundingBox.width / 0.92
    check(knob.distance(to: landing) <= travel + StickMath.overtravel(travel) + 0.5, "float: knob stops at full push plus overtravel, \(knob.distance(to: landing)) from anchor")
    check(e.render().contains { $0.role == .dot && $0.shape.center == landing }, "float: anchor stays put when dragging past the edge")
    e.moved(1, to: landing + CGPoint(x: -300, y: 0), time: 0.2)
    check((r.sticks[.left]?.x ?? 0) < -0.9, "float: full left from the same anchor, got \(String(describing: r.sticks[.left]))")
    e.ended(1, at: landing, time: 0.3)
    e.began(1, at: landing, time: 0.4)
    check(!r.held.contains(.stickL), "float: re-grabbing after a drag is not a click")
    e.ended(1, at: landing, time: 0.45)
    e.began(1, at: landing + CGPoint(x: 8, y: 4), time: 0.6)
    check(r.held.contains(.stickL), "float: tap then tap-and-hold = L3, got \(r.held)")
    e.ended(1, at: landing, time: 0.9)
    check(r.held.isEmpty, "float: L3 released")
    check(!e.render().contains { $0.role == .stickBase || $0.role == .stickKnob || $0.role == .dot },
          "float: nothing drawn for idle sticks")
}

do {
    let (e, r, s0) = engine("adaptive")
    let s = s0 as! AdaptivePad
    let u = s.controls.first { $0.button == .a }!.shape.boundingBox.width
    let home = centre(s, .a)
    for i in 0..<40 {
        let target = centre(s, .a)
        tap(e, CGPoint(x: home.x - 0.35 * u, y: target.y), t: Double(i))
        _ = r
    }
    let moved = centre(s, .a).x - home.x
    check(moved < -0.15 * u && moved > -0.4 * u, "adaptive: face diamond drifts toward presses left of A, moved \(moved / u)u")
    check(LayoutCheck.problems(s.controls, in: ipad.context(.stacked).safeBounds).isEmpty, "adaptive: drift keeps layout valid")
    let before = s.learned
    e.began(1, at: centre(s, .a), time: 100)
    e.moved(1, to: centre(s, .b), time: 100.1)
    e.ended(1, at: centre(s, .b), time: 100.2)
    check(s.learned == before, "adaptive: a slide teaches nothing")
    s.resetLearning()
    check(centre(s, .a) == home, "adaptive: reset returns home")
    let sample: [Int: CGPoint] = [2: CGPoint(x: -0.25, y: 0.125), 5: CGPoint(x: 0.5, y: 0)]
    check(AdaptivePad.decode(AdaptivePad.encode(sample)) == sample, "adaptive: learned positions round-trip through JSON")
    check(AdaptivePad.decode("garbage").isEmpty, "adaptive: bad saved data loads as nothing learned")
}

do {
    let (_, _, s0) = engine("frame")
    let f = s0 as! FramePad
    check(f.mode == .columns, "frame: stacked screens on the A12Z iPad use side columns, got \(f.mode)")
    let (_, _, s1) = engine("frame", .single)
    check((s1 as! FramePad).mode == .overlay, "frame: single 16:9 on a 4:3 iPad has no usable margin -> overlay")
    let portrait = TargetDevice.all.first { $0.name.contains("portrait") }!
    let fp = FramePad(); fp.layout(portrait.context(.single))
    check(fp.mode == .band, "frame: portrait single screen uses the bottom band, got \(fp.mode)")
}


// MARK: Racing behaviour

func racingEngine(_ options: RacingPad.Options = RacingPad.Options()) -> (PadEngine, Recorder, RacingPad) {
    let r = Recorder()
    let pad = RacingPad(options: options)
    let e = PadEngine(scheme: pad, output: r, context: ipad.context(.stacked))
    return (e, r, pad)
}
func pedalCentre(_ s: ControlScheme, _ set: Set<PadButton>) -> CGPoint {
    s.controls.first { if case .pedal(let x) = $0.kind { return x == set }; return false }!.shape.center
}
func steerSpec(_ s: ControlScheme) -> (SteerSpec, CGRect) {
    for c in s.controls { if case .steer(let spec) = c.kind { return (spec, c.shape.boundingBox) } }
    fatalError("no steering area")
}

do {
    let (e, r, s) = racingEngine()
    let (spec, zone) = steerSpec(s)
    let start = CGPoint(x: zone.midX, y: zone.midY)
    e.began(1, at: start, time: 0)
    check(r.sticks[.left] == nil || r.sticks[.left] == .zero, "racing: landing on the steering area does not steer")
    e.moved(1, to: start + CGPoint(x: spec.lockX, y: 0), time: 0.1)
    check(near(r.sticks[.left]?.x ?? 0, 1, 0.01), "racing: full lock right, got \(String(describing: r.sticks[.left]))")
    e.moved(1, to: start + CGPoint(x: -spec.lockX, y: 0), time: 0.2)
    check(near(r.sticks[.left]?.x ?? 0, -1, 0.01), "racing: full lock left")
    e.moved(1, to: start + CGPoint(x: spec.lockX * 0.5, y: 0), time: 0.3)
    check((r.sticks[.left]?.x ?? 0) > 0.3 && (r.sticks[.left]?.x ?? 0) < 0.6, "racing: half travel is about half steering")
    e.moved(1, to: start + CGPoint(x: spec.lockX * 0.5, y: -spec.lockY * 0.3), time: 0.35)
    check((r.sticks[.left]?.y ?? 1) == 0, "racing: small upward wander is inside the item dead zone")
    e.moved(1, to: start + CGPoint(x: spec.lockX * 0.5, y: -spec.lockY), time: 0.4)
    check((r.sticks[.left]?.y ?? 0) > 0.9, "racing: push up = throw forward (+y)")
    e.moved(1, to: start + CGPoint(x: 0, y: spec.lockY), time: 0.5)
    check((r.sticks[.left]?.y ?? 0) < -0.9, "racing: pull down = throw back (-y)")
    e.moved(1, to: start + CGPoint(x: spec.lockX * 4, y: 0), time: 0.6)
    check(near(r.sticks[.left]?.x ?? 0, 1, 0.01), "racing: stays at full lock far past it")
    e.moved(1, to: start + CGPoint(x: spec.lockX * 4 - spec.lockX * 1.3, y: 0), time: 0.7)
    check((r.sticks[.left]?.x ?? 0) < 0.99, "racing: the anchor followed the thumb, so backing off leaves full lock quickly")
    e.ended(1, at: start, time: 0.8)
    check(r.sticks[.left] == .zero, "racing: stick centres when the thumb lifts")
}

do {
    let (e, r, s) = racingEngine()
    let a = pedalCentre(s, [.a]), ar = pedalCentre(s, [.a, .r]), rr = pedalCentre(s, [.r]), b = pedalCentre(s, [.b])
    e.began(1, at: a, time: 0)
    check(r.held == [.a], "racing: thumb on the accelerate zone holds A, got \(r.held)")
    e.moved(1, to: ar, time: 0.1)
    check(r.held == [.a, .r], "racing: sliding up onto A+R holds both, got \(r.held)")
    e.moved(1, to: rr, time: 0.2)
    check(r.held == [.r], "racing: sliding on to the drift zone hands over to R, got \(r.held)")
    e.moved(1, to: ar, time: 0.3)
    e.moved(1, to: a, time: 0.4)
    check(r.held == [.a], "racing: and back down to A, got \(r.held)")
    e.moved(1, to: b, time: 0.5)
    check(r.held == [.b], "racing: brake is next to accelerate, got \(r.held)")
    e.ended(1, at: b, time: 0.6)
    check(r.held.isEmpty, "racing: lift releases")
    r.log = []
    e.began(2, at: a, time: 1)
    e.moved(2, to: ar, time: 1.1)
    e.ended(2, at: ar, time: 1.2)
    check(r.log == ["A+", "R+", "A-", "R-"] || r.log == ["A+", "R+", "R-", "A-"], "racing: A to A+R presses A once and keeps it: \(r.log)")
}

do {
    let (e, r, s) = racingEngine()
    let (spec, zone) = steerSpec(s)
    let a = pedalCentre(s, [.a])
    let start = CGPoint(x: zone.midX, y: zone.midY)
    e.began(1, at: start, time: 0)
    e.began(2, at: a, time: 0.01)
    check(r.held == [.a], "racing: A held while steering")
    for i in 1...20 {
        e.moved(1, to: start + CGPoint(x: spec.lockX * CGFloat(sin(Double(i) / 3)), y: 0), time: 0.02 * Double(i))
        check(r.held == [.a], "racing: steering move \(i) must not drop A, got \(r.held)")
    }
    e.ended(1, at: start, time: 1)
    check(r.held == [.a] && r.sticks[.left] == .zero, "racing: lifting the steering thumb keeps A and centres the stick")
    e.ended(2, at: a, time: 1.1)
    r.log = []
    e.began(1, at: start, time: 2)
    for i in 0..<5 { tap(e, a, id: 5, t: 2.1 + Double(i) * 0.3) }
    e.ended(1, at: start, time: 4)
    check(r.log.filter { $0 == "A+" }.count == 5 && r.log.filter { $0 == "A-" }.count == 5, "racing: five taps on A while steering, got \(r.log)")
}

do {
    let (e, r, s) = racingEngine(RacingPad.Options(autoAccelerate: true))
    check(r.held == [.a], "racing: auto-accelerate holds A with no finger down, got \(r.held)")
    let b = pedalCentre(s, [.b])
    e.began(1, at: b, time: 0)
    check(r.held == [.b], "racing: the brake zone overrides auto-accelerate, got \(r.held)")
    e.ended(1, at: b, time: 0.1)
    check(r.held == [.a], "racing: A comes back when the brake lifts, got \(r.held)")
    e.ambientEnabled = false
    check(r.held.isEmpty, "racing: nothing is held for the player while the pad is off")
    e.ambientEnabled = true
    check(r.held == [.a], "racing: and back on")
}

do {
    let (e, r, s) = racingEngine(RacingPad.Options(tilt: true))
    let (_, zone) = steerSpec(s)
    check(s.wantsMotion, "racing: tilt option asks for motion")
    e.motion(angle: 1.0)
    check(r.sticks[.left] == nil || r.sticks[.left] == .zero, "racing: first motion sample is straight ahead")
    e.motion(angle: 1.0 + RacingPad.tiltFullLock)
    check(near(r.sticks[.left]?.x ?? 0, 1, 0.01), "racing: turned the full angle = full lock, got \(String(describing: r.sticks[.left]))")
    e.motion(angle: 1.0 - RacingPad.tiltFullLock / 2)
    check((r.sticks[.left]?.x ?? 0) < -0.3, "racing: turned the other way steers left")
    let steer = CGPoint(x: zone.midX, y: zone.midY)
    e.began(1, at: steer, time: 0)
    e.moved(1, to: steer + CGPoint(x: -400, y: -400), time: 0.1)
    check((r.sticks[.left]?.x ?? 0) < 0 && (r.sticks[.left]?.y ?? 0) > 0.5, "racing: tilt gives X, the thumb still throws items, got \(String(describing: r.sticks[.left]))")
    e.ended(1, at: steer, time: 0.2)
    check((r.sticks[.left]?.x ?? 0) < 0, "racing: tilt keeps steering after the thumb lifts")
    let c = s.controls.first { if case .recentre = $0.kind { return true }; return false }!
    e.began(2, at: c.shape.center, time: 1)
    e.ended(2, at: c.shape.center, time: 1.1)
    check(r.sticks[.left] == nil || r.sticks[.left] == .zero, "racing: the recentre button re-centres, got \(String(describing: r.sticks[.left]))")
}

// MARK: Pressed look outlasts a quick tap

do {
    let r = Recorder()
    let e = PadEngine(scheme: ZonePad(), output: r, context: ipad.context(.stacked))
    var now = 100.0
    e.clock = { now }
    let s = e.scheme as! ControlScheme
    let a = centre(s, .a)
    e.began(1, at: a, time: 0)
    e.ended(1, at: a, time: 0.001)
    check(r.held.isEmpty, "afterglow: the game still sees the release")
    check(e.litButtons().contains(.a), "afterglow: a tap that ended before a draw is still drawn pressed")
    check(e.render().contains { $0.label == "A" && $0.lit }, "afterglow: render shows A lit")
    now += e.minimumLitDuration + 0.01
    check(!e.litButtons().contains(.a), "afterglow: and then it lets go")
    check(e.nextLitExpiry() == nil, "afterglow: nothing left waiting")
}

do {
    let fit = PadScreenGeometry.aspectFit(16.0 / 9.0, in: CGRect(x: 0, y: 0, width: 1000, height: 1000))
    check(abs(fit.width - 1000) < 0.01 && abs(fit.height - 562.5) < 0.01 && abs(fit.minY - 218.75) < 0.01,
          "aspectFit letterboxes 16:9 in a square, got \(fit)")
    let tall = PadScreenGeometry.aspectFit(16.0 / 9.0, in: CGRect(x: 10, y: 0, width: 1600, height: 450))
    check(abs(tall.height - 450) < 0.01 && abs(tall.width - 800) < 0.01 && abs(tall.midX - 810) < 0.01,
          "aspectFit pillarboxes in a wide rect, got \(tall)")
}

// MARK: Shoulder travel uses the whole room, both ways round

for (name, size, insets) in [
    ("iPad landscape", CGSize(width: 1366, height: 1024), Insets(top: 24, bottom: 20)),
    ("iPad portrait", CGSize(width: 1024, height: 1366), Insets(top: 24, bottom: 20)),
    ("iPhone landscape", CGSize(width: 932, height: 430), Insets(left: 59, bottom: 21, right: 59)),
    ("iPhone portrait", CGSize(width: 430, height: 932), Insets(top: 59, bottom: 34)),
] {
    for id in ["zone", "adaptive"] {
        let ctx = LayoutContext(size: size, safeInsets: insets)
        let limit = GamePadArrangement.maxShoulderDrop(ctx)
        var home = ctx
        home.shoulderOffset = 0
        let homeScheme = SchemeCatalog.make(id) as! ControlScheme
        homeScheme.layout(home)
        var far = ctx
        far.shoulderOffset = limit
        let farScheme = SchemeCatalog.make(id) as! ControlScheme
        farScheme.layout(far)
        var over = ctx
        over.shoulderOffset = limit + 0.5
        let overScheme = SchemeCatalog.make(id) as! ControlScheme
        overScheme.layout(over)
        let moved = { (s: ControlScheme) in shoulderRects(s)[.zl]!.minY - shoulderRects(homeScheme)[.zl]!.minY }
        let u = shoulderRects(farScheme)[.zl]!.width / 1.9
        check(LayoutCheck.problems(farScheme.controls, in: ctx.safeBounds).isEmpty, "\(name) \(id): max shoulder drop leaves a problem")
        check(abs(moved(farScheme) - limit * u) < u * 0.1 + 1, "\(name) \(id): the slider maximum \(limit) is not reached (\(moved(farScheme) / u))")
        check(moved(overScheme) <= moved(farScheme) + 1, "\(name) \(id): the shoulders move past the slider maximum")
    }
}

// MARK: Nearest-button assignment

do {
    let r: CGFloat = 30
    let a = HitTarget(id: "A", centre: CGPoint(x: 100, y: 0), halfSize: CGSize(width: r, height: r), isCircle: true)
    let b = HitTarget(id: "B", centre: CGPoint(x: 171, y: 0), halfSize: CGSize(width: r, height: r), isCircle: true)
    let both = [a, b]
    func hit(_ x: CGFloat, _ y: CGFloat = 0, reach: CGFloat = 1.4, contact: CGFloat = 0,
             bias: CGPoint = .zero, current: String? = nil) -> String? {
        HitResolver.resolve(CGPoint(x: x, y: y), targets: both, reachFactor: reach,
                            contactRadius: contact, bias: bias, current: current)
    }
    check(hit(100) == "A" && hit(171) == "B", "nearest: a touch on a button's centre gets that button")
    check(hit(133) == "A", "nearest: a touch in the gap, nearer A, goes to A")
    check(hit(138) == "B", "nearest: a touch in the gap, nearer B, goes to B")
    check(hit(60) == "A", "nearest: just outside the drawn edge (within 1.4x) still counts")
    check(hit(100, 45) == nil, "nearest: a touch outside the reach goes nowhere")
    check(hit(60, 0, reach: 1.0) == nil, "nearest: with no tolerance an edge miss goes nowhere")
    check(hit(100, 45, contact: 8) == "A", "nearest: a wide contact area extends the reach")
    check(hit(60, 0, bias: CGPoint(x: 6, y: 0)) == "A" && hit(133, 0, bias: CGPoint(x: 6, y: 0)) == "B",
          "nearest: the bias shifts where the touch is read")
    check(hit(135, current: "A") == "A" && hit(135, current: "B") == "B", "nearest: a finger on the seam keeps the button it holds")
    check(hit(160, current: "A") == "B", "nearest: sliding well onto B hands over from A")
    check(hit(100 + 29, 29, reach: 1.15) == "A", "nearest: a round button's frame corner presses it at Normal")
    check(hit(150, current: "A") == "B" && hit(150, current: "B") == "B", "nearest: a point inside B while holding A switches to B")
    let pill = HitTarget(id: "ZL", centre: CGPoint(x: 0, y: 0), halfSize: CGSize(width: 60, height: 20), isCircle: false)
    check(HitResolver.resolve(CGPoint(x: 50, y: 24), targets: [pill], reachFactor: 1.4) == "ZL", "nearest: a shoulder's reach follows its shorter side")
    check(HitResolver.resolve(CGPoint(x: 50, y: 40), targets: [pill], reachFactor: 1.4) == nil, "nearest: and stops there")
}

print("\(passes) passed, \(failures) failed")
exit(Int32(min(failures, 125)))
