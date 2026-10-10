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
        // Arc places every button by the player's own reach, so it has no separate A size.
        for info in SchemeCatalog.all where info.id != ArcPad.schemeInfo.id {
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
    // Up to the old 1.5-button maximum the shoulders go exactly where they always did, over the
    // GamePad screen or not; past it they stop before covering it.
    if let zl = stacked.2, let gp = stacked.3 {
        let u = zl.width / 1.9
        check(!zl.intersects(gp) || stacked.0 <= 1.5 * u + 1,
              "upright iPad \(id) stacked: shoulders cover the GamePad screen past the old maximum")
        check(stacked.0 > 1.5 * 72 - 1, "upright iPad \(id) stacked: only moved \(stacked.0)")
    }
}

// MARK: Shoulder drops within the old range are exactly what they always were
// Up to 1.5 buttons (the slider's old maximum) the GamePad touchscreen and video play no part:
// the same request gives the same shoulders whether or not those rectangles are known. Only
// past 1.5 do the shoulders stop in front of a rectangle they started clear of.

for (name, size, insets) in [
    ("iPad landscape", CGSize(width: 1366, height: 1024), Insets(top: 24, bottom: 20)),
    ("iPad portrait", CGSize(width: 1024, height: 1366), Insets(top: 24, bottom: 20)),
    ("iPhone landscape", CGSize(width: 852, height: 393), Insets(left: 59, bottom: 21, right: 59)),
] {
    for id in ["zone", "adaptive"] {
        let plain = LayoutContext(size: size, safeInsets: insets)
        let homeScheme = SchemeCatalog.make(id) as! ControlScheme
        homeScheme.layout(plain)
        guard let homeZL = shoulderRects(homeScheme)[.zl] else { continue }
        let u = homeZL.width / 1.9
        func layout(_ ctx: LayoutContext, _ request: CGFloat) -> [PadButton: CGRect] {
            var c = ctx
            c.shoulderOffset = request
            let sc = SchemeCatalog.make(id) as! ControlScheme
            sc.layout(c)
            return shoulderRects(sc)
        }
        // A picture whose top edge the shoulders reach at about half a button down.
        let near = CGRect(x: 0, y: homeZL.minY + 1.5 * u, width: size.width, height: size.height)
        // One they only reach well past 1.5 buttons.
        let far = CGRect(x: 0, y: homeZL.minY + 3.2 * u, width: size.width, height: size.height)
        for request: CGFloat in [0.25, 0.5, 1, 1.25, 1.5] {
            let bare = layout(plain, request)
            for rect in [near, far] {
                var withRect = plain
                withRect.touchscreenRect = rect
                withRect.videoRects = [rect]
                let got = layout(withRect, request)
                for (b, r) in bare {
                    check(got[b] == r, "\(name) \(id) drop \(request): \(b) moved by the GamePad rectangle")
                }
            }
        }
        // Past the old maximum: blocked at once by the near picture, further than 1.5 by the far one.
        var nearCtx = plain
        nearCtx.touchscreenRect = near
        let atCap = layout(nearCtx, 1.5)[.zl]!.minY
        check(abs(layout(nearCtx, 20)[.zl]!.minY - atCap) < 0.01, "\(name) \(id): shoulders went past the old maximum into the picture")
        var farCtx = plain
        farCtx.touchscreenRect = far
        let beyond = layout(farCtx, 20)[.zl]!
        check(!beyond.intersects(far), "\(name) \(id): shoulders cover the picture past the old maximum")
        check(beyond.minY >= layout(plain, 1.5)[.zl]!.minY - 0.01, "\(name) \(id): shoulders went back up")
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
            check(near(atEdge.magnitude, (Double(lim) - tuning.deadzone) / (1 - tuning.deadzone), 1e-6), "edge value is the gate limit, rescaled past the deadzone (as on the pad) at \(deg)deg (\(g)): \(atEdge.magnitude)")
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


// MARK: Shared settings: every scheme gives the same stick output as MuffinEMU's own pad

/// A literal copy of the stick maths in MuffinEMU's own pad (JoystickControl.report and the
/// clamp above it in ControllerPad.swift). `dx`/`dy` are the finger's offset from the ring's
/// centre in points, +y down; the result is the console value, +y up.
func gen1Stick(dx: CGFloat, dy: CGFloat, travel: CGFloat, deadzone: Double, curve: Double, octagon: Bool) -> (x: Double, y: Double) {
    func radiusFraction(_ angle: CGFloat) -> CGFloat {
        if !octagon { return 1 }
        let wedge = CGFloat.pi / 4
        var offset = angle.truncatingRemainder(dividingBy: wedge)
        if offset < 0 { offset += wedge }
        return cos(wedge / 2) / cos(offset - wedge / 2)
    }
    let dead = CGFloat(min(max(deadzone, 0), 0.30))
    let curve = CGFloat(min(max(curve, 1), 2.5))
    let distance = (dx * dx + dy * dy).squareRoot()
    let reach = travel * radiusFraction(atan2(dy, dx))
    let deflection = travel > 0 ? min(distance, reach) / travel : 0
    guard deflection > dead, distance > 0 else { return (0, 0) }
    var magnitude = (deflection - dead) / (1 - dead)
    if curve != 1 { magnitude = CGFloat(pow(Double(magnitude), Double(curve))) }
    return (Double(dx / distance * magnitude), Double(-dy / distance * magnitude))
}

func settingsContext(_ settings: PadSettings, _ display: TargetDevice.Display = .stacked) -> LayoutContext {
    var c = ipad.context(display)
    c.scale = settings.scale; c.stick = settings.stick; c.calibration = settings.calibration
    c.tolerance = settings.tolerance; c.stickSpacing = settings.stickSpacing; c.shoulderOffset = settings.shoulderOffset
    return c
}

do {
    // 1. The shared function itself, against the pad's, over a grid of settings and positions.
    let travel: CGFloat = 80
    var worst = 0.0
    for dead in [0.0, 0.06, 0.15, 0.30] {
        for curve in [1.0, 1.6, 2.5] {
            for gate in StickTuning.Gate.allCases {
                let tuning = StickTuning(deadzone: dead, curve: curve, gate: gate)
                for deg in stride(from: 0.0, to: 360.0, by: 7.5) {
                    for r in [0.0, 0.03, 0.06, 0.1, 0.3, 0.5, 0.8, 0.93, 1.0, 1.1, 1.3] {
                        let a = CGFloat(deg * .pi / 180)
                        let dx = cos(a) * CGFloat(r) * travel, dy = sin(a) * CGFloat(r) * travel
                        let mine = StickMath.value(offset: CGPoint(x: dx, y: dy), travel: travel, tuning: tuning)
                        let ref = gen1Stick(dx: dx, dy: dy, travel: travel, deadzone: dead, curve: curve, octagon: gate == .octagon)
                        worst = max(worst, abs(mine.x - ref.x), abs(mine.y - ref.y))
                    }
                }
            }
        }
    }
    check(worst < 1e-12, "StickMath.value equals the pad's formula over the whole grid (worst difference \(worst))")
    let wild = StickTuning(deadzone: 5, curve: 0.2, gate: .round)
    check(StickMath.value(offset: CGPoint(x: 80, y: 0), travel: 80, tuning: wild)
          == StickMath.value(offset: CGPoint(x: 80, y: 0), travel: 80, tuning: StickTuning(deadzone: 0.30, curve: 1, gate: .round)),
          "out-of-range deadzone and curve are clamped to the pad's ranges")
}

/// The first stick control of the given side that a scheme lays out, and where a finger starts.
func stickControl(_ s: ControlScheme, _ side: PadStick) -> (PadControl, travel: CGFloat, floating: Bool)? {
    for c in s.controls {
        switch c.kind {
        case let .stick(st, travel, _) where st == side: return (c, travel, false)
        case let .floatingStick(st, travel, _, _, _) where st == side: return (c, travel, true)
        default: break
        }
    }
    return nil
}

do {
    let tunings = [StickTuning(), StickTuning(deadzone: 0, curve: 1, gate: .round),
                   StickTuning(deadzone: 0.2, curve: 2.2, gate: .octagon),
                   StickTuning(deadzone: 0.3, curve: 1.4, gate: .round)]
    var compared = 0
    var schemesWithSticks: [String] = []
    for info in SchemeCatalog.all {
        for tuning in tunings {
            var settings = PadSettings(); settings.stick = tuning
            let r = Recorder()
            let e = PadEngine(scheme: SchemeCatalog.make(info.id), output: r, context: settingsContext(settings))
            let s = e.scheme as! ControlScheme
            for side in [PadStick.left, .right] {
                guard let (c, travel, floating) = stickControl(s, side) else { continue }
                if !schemesWithSticks.contains(info.id) { schemesWithSticks.append(info.id) }
                let origin = floating ? CGPoint(x: c.shape.boundingBox.midX, y: c.shape.boundingBox.midY) : c.shape.center
                for deg in stride(from: 0.0, to: 360.0, by: 15.0) {
                    for rr in [0.02, 0.07, 0.25, 0.6, 0.95, 1.0, 1.1] {
                        let a = CGFloat(deg * .pi / 180)
                        let dx = cos(a) * CGFloat(rr) * travel, dy = sin(a) * CGFloat(rr) * travel
                        e.began(1, at: origin, time: 0)
                        e.moved(1, to: origin + CGPoint(x: dx, y: dy), time: 0.1)
                        let got = r.sticks[side] ?? .zero
                        let ref = gen1Stick(dx: dx, dy: dy, travel: travel, deadzone: tuning.deadzone,
                                            curve: tuning.curve, octagon: tuning.gate == .octagon)
                        compared += 1
                        check(abs(got.x - ref.x) < 1e-9 && abs(got.y - ref.y) < 1e-9,
                              "\(info.id) \(side) stick at \(deg)deg r\(rr), \(tuning): got \(got), the pad gives \(ref)")
                        e.ended(1, at: origin, time: 0.2)
                    }
                }
            }
        }
    }
    check(compared > 500, "stick parity compared \(compared) positions across \(schemesWithSticks)")
    check(["zone", "float", "adaptive", "frame"].allSatisfy { schemesWithSticks.contains($0) }, "every stick scheme was exercised: \(schemesWithSticks)")
}

do {
    // 2. Defaults: the unset PadSettings lays out exactly what the bare context did.
    let bare = ipad.context(.stacked)
    let viaSettings = LayoutContext(size: bare.size, safeInsets: bare.safeInsets, videoRects: bare.videoRects,
                                    touchscreenRect: bare.touchscreenRect, settings: PadSettings())
    check(viaSettings == bare, "default PadSettings is the default layout context")
    for info in SchemeCatalog.all {
        let a = SchemeCatalog.make(info.id) as! ControlScheme, b = SchemeCatalog.make(info.id) as! ControlScheme
        a.layout(bare); b.layout(viaSettings)
        check(a.controls.map(\.shape) == b.controls.map(\.shape) && a.controls.map(\.reach) == b.controls.map(\.reach),
              "\(info.id): default settings change no control or catchment")
    }
    check(StickCalibration().isIdentity && StickCalibration(encoded: "").isIdentity, "no calibration stored = identity")
    let zero = StickMath.value(offset: CGPoint(x: 40, y: -25), travel: 80, tuning: StickTuning())
    check(zero == StickMath.value(offset: CGPoint(x: 40, y: -25), travel: 80, tuning: StickTuning(),
                                  calibration: .identity, fixedBase: false), "identity calibration changes nothing")
}

do {
    // 3. Calibration maps the player's reach and rest onto the same output, in every scheme.
    let cal = StickCalibration(fullThrow: 0.7, centre: CGPoint(x: 0.1, y: -0.05), jitter: 0.12)
    for info in SchemeCatalog.all {
        var settings = PadSettings(); settings.calibration = StickCalibrations(left: cal, right: cal)
        let r = Recorder()
        let e = PadEngine(scheme: SchemeCatalog.make(info.id), output: r, context: settingsContext(settings))
        let s = e.scheme as! ControlScheme
        for side in [PadStick.left, .right] {
            guard let (c, travel, floating) = stickControl(s, side) else { continue }
            let origin = floating ? CGPoint(x: c.shape.boundingBox.midX, y: c.shape.boundingBox.midY) : c.shape.center
            let rest = floating ? CGPoint.zero : CGPoint(x: cal.centre.x * travel, y: cal.centre.y * travel)
            e.began(1, at: origin + rest, time: 0)
            check((r.sticks[side] ?? .zero) == .zero, "\(info.id) \(side): the calibrated rest spot is the centre")
            let wobble = travel * CGFloat(cal.jitter) * 0.9
            e.moved(1, to: origin + rest + CGPoint(x: wobble, y: 0), time: 0.05)
            check((r.sticks[side] ?? .zero) == .zero, "\(info.id) \(side): wobble inside the calibrated rest is ignored")
            e.moved(1, to: origin + rest + CGPoint(x: travel * 0.7, y: 0), time: 0.1)
            check(near(r.sticks[side]?.x ?? 0, 1, 1e-9), "\(info.id) \(side): the calibrated throw is full output, got \(String(describing: r.sticks[side]))")
            e.moved(1, to: origin + rest + CGPoint(x: -travel * 0.7, y: 0), time: 0.15)
            check(near(r.sticks[side]?.x ?? 0, -1, 1e-9), "\(info.id) \(side): and full the other way")
            e.moved(1, to: origin + rest + CGPoint(x: 0, y: -travel * 0.35), time: 0.2)
            let half = r.sticks[side]?.y ?? 0
            let want = (0.5 - 0.12 / 0.7) / (1 - 0.12 / 0.7)
            check(near(half, want, 1e-9), "\(info.id) \(side): half the calibrated throw is half output past the deadzone: \(half) vs \(want)")
            e.ended(1, at: origin, time: 0.3)
        }
    }
    // Racing steers the same way: their throw is full lock, their wobble is not steering.
    var settings = PadSettings(); settings.calibration = StickCalibrations(left: cal)
    let r = Recorder()
    let e = PadEngine(scheme: SchemeCatalog.make("racing"), output: r, context: settingsContext(settings))
    let (spec, zone) = steerSpec(e.scheme as! ControlScheme)
    let start = CGPoint(x: zone.midX, y: zone.midY)
    e.began(1, at: start, time: 0)
    e.moved(1, to: start + CGPoint(x: spec.lockX * 0.11 * 0.7, y: 0), time: 0.1)
    check((r.sticks[.left]?.x ?? 0) == 0, "racing: wobble inside the calibrated rest does not steer")
    e.moved(1, to: start + CGPoint(x: spec.lockX * 0.7, y: 0), time: 0.2)
    check(near(r.sticks[.left]?.x ?? 0, 1, 1e-9), "racing: the calibrated throw is full lock")
    e.ended(1, at: start, time: 0.3)
    // Racing deadzone and curve are the same numbers as the sticks'.
    var t = PadSettings(); t.stick = StickTuning(deadzone: 0.2, curve: 2, gate: .octagon)
    let r2 = Recorder()
    let e2 = PadEngine(scheme: SchemeCatalog.make("racing"), output: r2, context: settingsContext(t))
    let (spec2, zone2) = steerSpec(e2.scheme as! ControlScheme)
    let start2 = CGPoint(x: zone2.midX, y: zone2.midY)
    e2.began(1, at: start2, time: 0)
    e2.moved(1, to: start2 + CGPoint(x: spec2.lockX * 0.6, y: 0), time: 0.1)
    check(near(r2.sticks[.left]?.x ?? 0, pow((0.6 - 0.2) / 0.8, 2), 1e-9), "racing: deadzone and curve mean what they do on the sticks")
}

do {
    // 4. Touch tolerance: never less than the scheme's own reach, and more at a higher level.
    func reaches(_ id: String, _ tol: PadTolerance?) -> [CGFloat] {
        var settings = PadSettings(); settings.tolerance = tol
        let s = SchemeCatalog.make(id) as! ControlScheme
        s.layout(settingsContext(settings))
        return s.controls.map(\.reach)
    }
    for info in SchemeCatalog.all {
        let base = reaches(info.id, nil), normal = reaches(info.id, .normal)
        let generous = reaches(info.id, .generous), very = reaches(info.id, .veryGenerous)
        check(zip(base, normal).allSatisfy { $0 <= $1 } && zip(normal, generous).allSatisfy { $0 <= $1 }
              && zip(generous, very).allSatisfy { $0 <= $1 }, "\(info.id): tolerance only ever widens a catchment")
        check(zip(base, very).contains { $0 < $1 }, "\(info.id): the most generous level widens something")
    }
    // A touch just outside a button is taken at the most generous level, and not before.
    var settings = PadSettings(); settings.tolerance = .veryGenerous
    let s = SchemeCatalog.make("float") as! ControlScheme
    let plain = SchemeCatalog.make("float") as! ControlScheme
    s.layout(settingsContext(settings)); plain.layout(settingsContext(PadSettings()))
    let a = plain.controls.first { $0.button == .x }!
    let r = a.shape.boundingBox.width / 2
    let p = a.shape.center + CGPoint(x: r + 0.6 * r, y: 0)
    check(s.claims(p) || !plain.claims(p), "float: a touch 0.6 radii outside a button is claimed when tolerance is raised")
}

do {
    // 5. The calibration flow.
    let travel: CGFloat = 80
    func run(radius: Double, sectors: Int = 8, rest: CGPoint = CGPoint(x: 4, y: -3), wobble: CGFloat = 1) -> StickCalibration? {
        var session = StickCalibrationSession(travel: travel)
        var t = 0.0
        session.begin(at: rest, time: t)
        while session.phase == .rest {
            t += 0.05
            let k = CGFloat(Int(t * 20) % 2 == 0 ? 1 : -1)
            session.move(to: rest + CGPoint(x: wobble * k, y: -wobble * k), time: t)
        }
        for i in 0..<sectors {
            let a = CGFloat(i) * .pi / 4
            let lim = Double(StickMath.gateFraction(.octagon, angle: a))
            let r = CGFloat(radius * lim) * travel
            t += 0.05
            session.move(to: rest + CGPoint(x: cos(a) * r, y: -sin(a) * r), time: t)
        }
        return session.lift()
    }
    let part = run(radius: 0.8)
    check(part != nil && near(part!.fullThrow, 0.8, 0.01), "calibration: a 0.8 sweep reads 0.8, got \(String(describing: part))")
    check(part != nil && near(Double(part!.centre.x), 4.0 / 80, 0.002) && near(Double(part!.centre.y), -3.0 / 80, 0.002),
          "calibration: the rest spot is recorded, got \(String(describing: part?.centre))")
    check(part != nil && part!.jitter > 0.01 && part!.jitter < 0.05, "calibration: the rest wobble is recorded, got \(String(describing: part?.jitter))")
    let whole = run(radius: 1.0, rest: .zero, wobble: 0)
    check(whole?.fullThrow == 1 && whole?.centre == .zero, "calibration: a player who uses the whole ring keeps the default throw and centre")
    check(run(radius: 0.8, sectors: 4) == nil, "calibration: lifting before reaching most of the ring saves nothing")
    var early = StickCalibrationSession(travel: travel)
    early.begin(at: .zero, time: 0)
    check(early.lift() == nil && early.phase == .waiting, "calibration: lifting during the rest saves nothing and starts over")
    var wander = StickCalibrationSession(travel: travel)
    wander.begin(at: .zero, time: 0)
    wander.move(to: CGPoint(x: 60, y: 0), time: 0.5)
    wander.move(to: CGPoint(x: 60, y: 0), time: 1.0)
    check(wander.phase == .rest, "calibration: a thumb that wanders off has not rested")
    if let p = part {
        let back = StickCalibration(encoded: p.encoded)
        check(near(back.fullThrow, p.fullThrow, 1e-4) && near(Double(back.centre.x), Double(p.centre.x), 1e-4) && near(back.jitter, p.jitter, 1e-4),
              "calibration: stored string round-trips")
    }
    check(StickCalibration(encoded: "nonsense").isIdentity && StickCalibration(encoded: "9,9,9,9").fullThrow == 1.15,
          "calibration: a bad stored string is the identity and out-of-range values are clamped")
}

do {
    // 6. Haptics, opacity, scale and shoulders reach the shared settings unchanged.
    var s = PadSettings(); s.scale = 1.3; s.shoulderOffset = 0.8; s.stickSpacing = -1
    let c = LayoutContext(size: CGSize(width: 800, height: 400), settings: s)
    check(c.scale == 1.3 && c.shoulderOffset == 0.8 && c.stickSpacing == -1, "PadSettings reaches the layout context")
}

// MARK: Arc

func arcDevices() -> [TargetDevice] {
    let names = ["iPhone SE", "iPhone 16 Pro Max", "iPad mini", "iPad Pro 13"]
    return TargetDevice.all.filter { names.contains($0.name) } + TargetDevice.portraitVariants
}

// Circle fit: recovers a known pivot and radius from noisy thumb-sweep samples.
do {
    var seed: UInt64 = 0x9E3779B97F4A7C15
    func rnd() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 11) / Double(1 << 53)
    }
    func gauss() -> Double { (-2 * log(max(rnd(), 1e-12))).squareRoot() * cos(2 * .pi * rnd()) }
    for (cx, cy, r, a0, a1) in [(1180.0, 600.0, 260.0, 1.9, 3.0), (-40.0, 700.0, 190.0, -0.1, 1.2), (400.0, 900.0, 320.0, 1.1, 1.8)] {
        var pts: [CGPoint] = []
        for _ in 0..<80 {
            let a = a0 + (a1 - a0) * rnd()
            let rr = r + 3 * gauss()
            pts.append(CGPoint(x: cx + rr * cos(a), y: cy - rr * sin(a) + 0))
        }
        // (y is flipped on screen; the circle is the same circle.)
        if let fit = ArcMath.fitCircle(pts) {
            let ce = hypot(Double(fit.center.x) - cx, Double(fit.center.y) - cy)
            check(ce < 0.12 * r, "arc: fit pivot off by \(ce) for r=\(r)")
            check(abs(Double(fit.radius) - r) < 0.08 * r, "arc: fit radius \(fit.radius) vs \(r)")
            check(Double(fit.rms) < 6, "arc: residual \(fit.rms) should be near the 3pt noise")
        } else {
            check(false, "arc: no fit for r=\(r)")
        }
    }
    // Noise-free samples are recovered exactly.
    let exact = (0..<20).map { i -> CGPoint in let a = 1.2 + Double(i) * 0.05; return CGPoint(x: 700 + 300 * cos(a), y: 500 - 300 * sin(a)) }
    if let f = ArcMath.fitCircle(exact) {
        check(hypot(Double(f.center.x) - 700, Double(f.center.y) - 500) < 0.01 && abs(Double(f.radius) - 300) < 0.01, "arc: exact fit, got \(f)")
    } else { check(false, "arc: exact samples must fit") }
    let line = (0..<30).map { CGPoint(x: Double($0) * 5, y: 100 + Double($0) * 2) }
    check(ArcMath.fitCircle(line) == nil, "arc: a straight sweep is not a circle")
    check(ArcMath.fitCircle([CGPoint(x: 1, y: 1)]) == nil, "arc: too few points")
}

// Layout on every device and orientation, with and without calibration.
for device in arcDevices() {
    for display in TargetDevice.Display.allCases {
        let ctx = device.context(display)
        let arc = ArcPad()
        arc.layout(ctx)
        let where_ = "Arc / \(device.name) / \(display.rawValue)"
        check(!arc.usingFallback, "\(where_): fell back to the plain arrangement")
        let problems = LayoutCheck.problems(arc.controls, in: ctx.safeBounds)
        check(problems.isEmpty, "\(where_): \(problems.joined(separator: "; "))")
        if arc.avoidance != .none {
            let keep = arc.avoidance == .video ? ctx.videoRects + [ctx.touchscreenRect!] : [ctx.touchscreenRect!]
            for c in arc.controls where !c.isZone {
                for k in keep where k.insetBy(dx: 1, dy: 1).intersects(c.shape.boundingBox) {
                    check(false, "\(where_): \(c.label) covers the video/GamePad rect")
                }
            }
        }
        if display == .stacked && device.name != "iPad Pro 13 portrait" {
            check(arc.avoidance != .none, "\(where_): stacked screens leave margins, Arc must stay off the video (got \(arc.avoidance))")
        }
    }
}

// Angular assignment: radial over/undershoot keeps the button; sliding along the arc moves it.
for device in arcDevices() {
    let ctx = device.context(.stacked)
    for (rad, name) in [(-0.8, "short"), (0.0, "on"), (0.9, "far")] {
        let out = Recorder()
        let arc = ArcPad()
        let eng = PadEngine(scheme: arc, output: out, context: ctx)
        for set in arc.hands {
            let buttons: [PadButton] = set.side == .right ? [.x, .a, .b, .y] : [.up, .right, .down, .left]
            for b in buttons {
                guard let c = arc.controls.first(where: { $0.button == b }) else { check(false, "arc: no \(b)"); continue }
                let (r, phi) = set.polar(c.shape.center)
                let p = set.point(r: r + CGFloat(rad) * arc.layoutUnit, phi: phi)
                eng.began(1, at: p, time: 0)
                check(out.held == [b], "arc \(device.name): \(name) press of \(b) gave \(out.held.map(\.description).sorted())")
                eng.ended(1, at: p, time: 0.1)
                check(out.held.isEmpty, "arc: release after \(b)")
            }
        }
    }
    // Slide A -> B along the arc, with a wobbling radius.
    let out = Recorder()
    let arc = ArcPad()
    let eng = PadEngine(scheme: arc, output: out, context: ctx)
    let hand = arc.hands.first { $0.side == .right }!
    let a = arc.controls.first { $0.button == .a }!.shape.center
    let b = arc.controls.first { $0.button == .b }!.shape.center
    let (r, pa) = hand.polar(a), (_, pb) = hand.polar(b)
    eng.began(1, at: a, time: 0)
    check(out.held == [.a], "arc: touch A")
    for i in 1...10 {
        let t = CGFloat(i) / 10
        let wobble = (i % 2 == 0 ? 0.5 : -0.5) * arc.layoutUnit
        eng.moved(1, to: hand.point(r: r + wobble, phi: pa + (pb - pa) * t), time: Double(i) * 0.01)
    }
    check(out.held == [.b], "arc: slid A to B, holding \(out.held)")
    eng.moved(1, to: CGPoint(x: ctx.size.width / 2, y: ctx.safeBounds.minY + 4), time: 1)
    check(out.held.isEmpty, "arc: far off the arc lets go")
    eng.ended(1, at: .zero, time: 2)
    check(out.held.isEmpty, "arc: nothing stuck")
}

// Calibration end to end: two thumbs sweep known arcs, the scheme fits and re-lays out.
do {
    let device = TargetDevice.all.first { $0.name == "iPad mini" }!
    let ctx = device.context(.stacked)
    let out = Recorder()
    let arc = ArcPad()
    var saved: [String: ArcProfile] = [:]
    arc.onProfiles = { saved = $0 }
    let eng = PadEngine(scheme: arc, output: out, context: ctx)
    let u = ctx.unit
    // Right thumb pivots below-right of the screen; left mirrored. Sweeps of ~55 degrees.
    let rp = CGPoint(x: ctx.size.width - 10, y: ctx.size.height + 40), lp = CGPoint(x: 10, y: ctx.size.height + 40)
    let rad: CGFloat = 6.2 * u
    var seed: UInt64 = 42
    func jitter() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(seed >> 11) / Double(1 << 53) - 0.5) * 6
    }
    arc.startCalibration()
    check(arc.isCalibrating && eng.claims(CGPoint(x: 5, y: 5)), "arc: calibration claims the whole screen")
    var t = 0.0
    eng.began(1, at: CGPoint(x: rp.x - rad * sin(0.35), y: rp.y - rad * cos(0.35)), time: t)
    eng.began(2, at: CGPoint(x: lp.x + rad * sin(0.35), y: lp.y - rad * cos(0.35)), time: t)
    for i in 0...120 {
        t = Double(i) * 0.04
        let phi = 0.35 + 0.9 * CGFloat(i) / 120
        eng.moved(1, to: CGPoint(x: rp.x - rad * sin(phi) + jitter(), y: rp.y - rad * cos(phi) + jitter()), time: t)
        eng.moved(2, to: CGPoint(x: lp.x + rad * sin(phi) + jitter(), y: lp.y - rad * cos(phi) + jitter()), time: t)
        eng.tick(time: t)
    }
    check(out.held.isEmpty && out.log.isEmpty, "arc: a calibration sweep presses nothing")
    eng.tick(time: 5.2)
    check(!arc.isCalibrating, "arc: calibration ends after five seconds")
    eng.ended(1, at: .zero, time: 5.3); eng.ended(2, at: .zero, time: 5.3)
    let prof = saved["landscape"]
    check(prof?.left != nil && prof?.right != nil, "arc: both hands calibrated, got \(String(describing: prof))")
    if let r = prof?.right {
        let short = Double(min(ctx.size.width, ctx.size.height))
        check(abs(r.radius * short - Double(rad)) < 0.08 * Double(rad), "arc: fitted radius \(r.radius * short) vs \(rad)")
        check(abs(r.pivotX * Double(ctx.size.width) - Double(rp.x)) < 0.1 * Double(rad), "arc: fitted pivot x")
        check(abs(r.pivotY * Double(ctx.size.height) - Double(rp.y)) < 0.1 * Double(rad), "arc: fitted pivot y")
    }
    check(arc.hands.allSatisfy { $0.calibrated }, "arc: layout uses the calibration")
    check(LayoutCheck.problems(arc.controls, in: ctx.safeBounds).isEmpty, "arc: calibrated layout has no overlaps")
    check(arc.avoidance != .none, "arc: calibrated layout still avoids the video")
    let json = ArcPad.encode(saved)
    check(ArcPad.decode(json) == saved, "arc: calibration round-trips through JSON")
    check(ArcPad.decode("garbage").isEmpty && ArcPad.decode("{\"landscape\":{\"right\":{\"pivotX\":1e999}}}").isEmpty, "arc: bad saved data loads as nothing")
    // A fresh scheme with the saved JSON lays out the same way; portrait has its own (empty) profile.
    let again = ArcPad(profiles: ArcPad.decode(json))
    again.layout(ctx)
    check(again.hands == arc.hands, "arc: saved calibration reproduces the layout")
    again.layout(TargetDevice.portraitVariants.first { $0.name == "iPad mini portrait" }!.context(.stacked))
    check(again.hands.allSatisfy { !$0.calibrated }, "arc: calibration is per orientation")
    // Skipping leaves everything as it was; reset returns the default arc.
    arc.startCalibration(); arc.skipCalibration()
    check(arc.hands.allSatisfy { $0.calibrated }, "arc: skipping keeps the calibration")
    arc.resetCalibration()
    check(arc.hands.allSatisfy { !$0.calibrated }, "arc: reset returns the default arc")
    // A garbage sweep (a tap) is rejected and the default stays.
    arc.startCalibration()
    let e2 = PadEngine(scheme: arc, output: out, context: ctx)
    e2.began(9, at: CGPoint(x: 700, y: 600), time: 0)
    e2.moved(9, to: CGPoint(x: 701, y: 600), time: 0.1)
    e2.tick(time: 5.5)
    check(arc.hands.allSatisfy { !$0.calibrated }, "arc: a tap is not a sweep")
}

print("\(passes) passed, \(failures) failed")
exit(Int32(min(failures, 125)))
