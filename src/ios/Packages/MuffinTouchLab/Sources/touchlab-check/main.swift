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
        // Arc places every button by the player's own reach and Showcase is the GamePad at life size, so neither has a separate A size.
        for info in SchemeCatalog.all where info.id != ArcPad.schemeInfo.id && info.id != ShowcasePad.schemeInfo.id {
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

// BEGIN nearest-hit checks
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

// END nearest-hit checks

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
    check(run(radius: 1.1, rest: .zero, wobble: 0)?.fullThrow == 1, "calibration: a sweep past the ring is still a throw of 1, so the stick can reach full output")
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
            let buttons: [PadButton] = set.side == .right ? [.a, .b, .x, .y] : [.up, .down, .left, .right]
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

// Reading order along each arc, from the top end down.
for device in arcDevices() {
    let arc = ArcPad()
    arc.layout(device.context(.stacked))
    for set in arc.hands {
        let order: [PadButton] = set.side == .right ? [.a, .b, .x, .y] : [.up, .down, .left, .right]
        let ys = order.compactMap { b in arc.controls.first { $0.button == b }?.shape.center.y }
        check(ys.count == 4 && zip(ys, ys.dropFirst()).allSatisfy { $0 < $1 }, "arc \(device.name): \(set.side) order along the arc is \(order.map(\.description)), got y \(ys)")
    }
}

// Calibration end to end: guided, left thumb then right, review, Done. Then it locks.
func sweep(_ eng: PadEngine, id: Int, pivot: CGPoint, side: ArcSide, radius: CGFloat, from: CGFloat, to: CGFloat, t0: Double) {
    var seed: UInt64 = UInt64(id) &* 977
    func jitter() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(seed >> 11) / Double(1 << 53) - 0.5) * 6
    }
    func at(_ phi: CGFloat) -> CGPoint {
        CGPoint(x: pivot.x + side.inboardSign * radius * sin(phi) + jitter(), y: pivot.y - radius * cos(phi) + jitter())
    }
    eng.began(id, at: at(from), time: t0)
    for i in 1...100 { eng.moved(id, to: at(from + (to - from) * CGFloat(i) / 100), time: t0 + Double(i) * 0.02) }
    eng.ended(id, at: at(to), time: t0 + 2.1)
}

do {
    let device = TargetDevice.all.first { $0.name == "iPad mini" }!
    let ctx = device.context(.stacked)
    let out = Recorder()
    let arc = ArcPad()
    var saved: [String: ArcProfile] = [:]
    arc.onProfiles = { saved = $0 }
    let eng = PadEngine(scheme: arc, output: out, context: ctx)
    let u = ctx.unit
    let rp = CGPoint(x: ctx.size.width - 10, y: ctx.size.height + 40), lp = CGPoint(x: 10, y: ctx.size.height + 40)
    let rad: CGFloat = 6.2 * u
    check(!arc.isLocked && !arc.hasCalibration, "arc: unlocked until the first calibration completes")
    check(arc.startCalibration() && arc.calibrationPhase == .left && eng.claims(CGPoint(x: 5, y: 5)), "arc: calibration starts with the left thumb and claims the screen")
    check(arc.calibrationPrompt.contains("left thumb"), "arc: prompt names the thumb")
    // A tap is not a sweep: stay on the left thumb with a note.
    eng.began(5, at: CGPoint(x: 200, y: 500), time: 0); eng.ended(5, at: CGPoint(x: 200, y: 500), time: 0.1)
    check(arc.calibrationPhase == .left && arc.calibrationNote != nil, "arc: a tap is not a sweep")
    sweep(eng, id: 1, pivot: lp, side: .left, radius: rad, from: 0.35, to: 1.25, t0: 1)
    check(arc.calibrationPhase == .right, "arc: left sweep accepted, now the right thumb")
    sweep(eng, id: 2, pivot: rp, side: .right, radius: rad, from: 0.35, to: 1.25, t0: 4)
    check(arc.calibrationPhase == .review, "arc: both swept, review")
    check(out.held.isEmpty && out.log.isEmpty, "arc: a calibration sweep presses nothing")
    check(!arc.render(pressed: [], sticks: [:]).isEmpty, "arc: review renders")
    // Redo throws the sweeps away; do it once, then redo for real.
    arc.redoCalibration()
    check(arc.calibrationPhase == .left, "arc: redo starts over")
    sweep(eng, id: 3, pivot: lp, side: .left, radius: rad, from: 0.35, to: 1.25, t0: 8)
    sweep(eng, id: 4, pivot: rp, side: .right, radius: rad, from: 0.35, to: 1.25, t0: 11)
    arc.acceptCalibration()
    check(!arc.isCalibrating && arc.isLocked && arc.hasCalibration, "arc: Done saves and locks")
    let prof = saved["landscape"]
    check(prof?.left != nil && prof?.right != nil && prof?.locked == true, "arc: both hands saved, got \(String(describing: prof))")
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
    let again = ArcPad(profiles: ArcPad.decode(json))
    again.layout(ctx)
    check(again.hands == arc.hands && again.isLocked, "arc: saved calibration reproduces the layout and the lock")
    again.layout(TargetDevice.portraitVariants.first { $0.name == "iPad mini portrait" }!.context(.stacked))
    check(again.hands.allSatisfy { !$0.calibrated } && !again.isLocked, "arc: calibration and lock are per orientation")

    // LOCKED: nothing can start, nothing can be dragged, play still works.
    let before = arc.controls.map(\.shape)
    check(!arc.startCalibration() && !arc.isCalibrating, "arc: locked refuses calibration")
    check(!arc.setFineTuning(true) && !arc.isFineTuning, "arc: locked refuses fine-tuning")
    let a = arc.controls.first { $0.button == .a }!.shape.center
    let hand = arc.hands.first { $0.side == .right }!
    let (ra, pa) = hand.polar(a)
    eng.began(20, at: a, time: 20)
    check(out.held == [.a], "arc: locked, a press still plays")
    eng.moved(20, to: hand.point(r: ra + 40, phi: pa + 0.3), time: 20.1)
    eng.ended(20, at: a, time: 20.2)
    check(arc.controls.map(\.shape) == before && saved["landscape"]?.rightTweaks == nil, "arc: locked, a drag moves nothing")

    // UNLOCKED: fine-tune by dragging along the arc and in/out, per hand, persisted. Done on
    // a window with no video so the geometry, not the margins, decides where things go.
    arc.setLocked(false)
    check(!arc.isLocked && saved["landscape"]?.locked == false, "arc: unlock persists")
    check(arc.setFineTuning(true) && arc.isFineTuning, "arc: unlocked allows fine-tuning")
    arc.setFineTuning(false)
    arc.resetToDefault()
    let open = LayoutContext(size: CGSize(width: 1376, height: 1032), safeInsets: Insets(top: 24, bottom: 20))
    let tarc = ArcPad()
    var tsaved: [String: ArcProfile] = [:]
    tarc.onProfiles = { tsaved = $0 }
    let teng = PadEngine(scheme: tarc, output: out, context: open)
    check(tarc.setFineTuning(true), "arc: fine-tune on")
    out.log.removeAll()
    let ta = tarc.controls.first { $0.button == .a }!.shape.center
    let thand = tarc.hands.first { $0.side == .right }!
    let leftBefore = tarc.controls.first { $0.button == .left }!.shape.center
    let (tra, tpa) = thand.polar(ta)
    teng.began(21, at: ta, time: 30)
    check(out.log.isEmpty && out.held.isEmpty, "arc: fine-tune presses nothing")
    for i in 1...10 { teng.moved(21, to: thand.point(r: tra + 3 * CGFloat(i), phi: tpa + 0.02 * CGFloat(i)), time: 30 + Double(i) * 0.02) }
    teng.ended(21, at: ta, time: 31)
    let ta2 = tarc.controls.first { $0.button == .a }!.shape.center
    let (tra2, tpa2) = tarc.hands.first { $0.side == .right }!.polar(ta2)
    check(abs((tpa2 - tpa) - 0.2) < 0.05, "arc: dragged 0.2 rad along the arc, moved \(tpa2 - tpa)")
    check(abs((tra2 - tra) - 30) < 3, "arc: dragged 30pt out, moved \(tra2 - tra)")
    check(tarc.controls.first { $0.button == .left }!.shape.center == leftBefore, "arc: the other hand is untouched")
    check(tsaved["landscape"]?.rightTweaks?["arc"] != nil && tsaved["landscape"]?.leftTweaks == nil, "arc: fine-tune saved for that hand only")
    let tuned = ArcPad(profiles: ArcPad.decode(ArcPad.encode(tsaved)))
    tuned.layout(open)
    check(tuned.controls.map(\.shape) == tarc.controls.map(\.shape), "arc: fine-tuning persists exactly")
    check(LayoutCheck.problems(tarc.controls, in: open.safeBounds).isEmpty, "arc: fine-tuned layout has no overlaps")
    // Drag the left stick on its own.
    let ls = tarc.controls.first { if case .stick(.left, _, _) = $0.kind { return true } else { return false } }!.shape.center
    teng.began(22, at: ls, time: 40)
    teng.moved(22, to: CGPoint(x: ls.x + 25, y: ls.y), time: 40.1)
    teng.ended(22, at: ls, time: 40.2)
    check(tsaved["landscape"]?.leftTweaks?["stick"] != nil, "arc: any control can be dragged, saved under its hand")
    tarc.setLocked(true)
    check(!tarc.isFineTuning, "arc: locking ends fine-tuning")
    let frozen = tarc.controls.map(\.shape)
    teng.began(23, at: tarc.controls.first { $0.button == .a }!.shape.center, time: 50)
    teng.moved(23, to: CGPoint(x: 900, y: 500), time: 50.1)
    teng.ended(23, at: .zero, time: 50.2)
    check(tarc.controls.map(\.shape) == frozen, "arc: locked again, drags move nothing")
    tarc.setLocked(false)
    tarc.resetToDefault()
    check(!tarc.hasCalibration && tsaved["landscape"] == nil, "arc: reset clears tweaks")
    arc.resetToDefault()
    arc.startCalibration()
    check(arc.startCalibration() && arc.isCalibrating, "arc: recalibrate available when unlocked")
    arc.cancelCalibration()
}

// Overlap: nothing covers the video when there is margin, the stacked layouts all fit, and
// a screen the video fills falls back to the placement that covers least, logged once.
do {
    var lines: [String] = []
    ArcPad.logSink = { lines.append($0) }
    ArcPad.logged.removeAll()
    for d in (TargetDevice.all + TargetDevice.portraitVariants) {
        let ctx = d.context(.stacked)
        let arc = ArcPad(); arc.layout(ctx)
        check(arc.avoidance != .none && !arc.usingFallback, "arc: \(d.name) stacked has margin and must avoid the video, got \(arc.avoidance)")
    }
    check(lines.isEmpty, "arc: no fallback log when everything fits, got \(lines)")
    let se = TargetDevice.all.first { $0.name == "iPhone SE" }!.context(.single)
    let full = ArcPad(); full.layout(se)
    check(full.avoidance == .none && !full.usingFallback, "arc: a video that fills the screen falls back to least overlap")
    check(LayoutCheck.problems(full.controls, in: se.safeBounds).isEmpty, "arc: and still nothing overlaps each other")
    let again = ArcPad(); again.layout(se); again.layout(se)
    check(lines.count == 1, "arc: the fallback is logged once, got \(lines.count)")
    // Least overlap: no worse than the plain Zone-style arrangement over the same video.
    let zone = GamePadArrangement.build(se)
    func covered(_ cs: [PadControl]) -> CGFloat {
        cs.reduce(0) { acc, c in
            let i = c.shape.boundingBox.intersection(se.videoRects[0])
            return acc + (i.isNull ? 0 : i.width * i.height)
        }
    }
    check(covered(full.controls) <= covered(zone), "arc: covers no more of the video than the plain layout")
}


// MARK: Showcase
// The showcase pad's geometry, transplant and colours ported as pure Swift, and the TouchLab
// scheme built on them.

do {
    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
    func centre(_ r: ShowcaseResolved, _ id: String) -> CGPoint { r.controls[id]!.centre }
    func nearPt(_ p: CGPoint, _ x: CGFloat, _ y: CGFloat) -> Bool { abs(p.x - x) < 0.02 && abs(p.y - y) < 0.02 }

    // Expected values are PreviewPadStore.resolve's own, taken by compiling the showcase
    // pad's GamePadGeometry.swift and MuffinPadCustomisation.swift unchanged on the same inputs.
    func resolve(_ preset: ShowcaseLayoutPreset, _ mode: ShowcaseLayout.DisplayMode, size: CGSize, safe: CGRect,
                 ppi: CGFloat, phone: Bool) -> ShowcaseResolved {
        ShowcaseResolver.resolve(preset: preset, displayMode: mode, container: size, safeArea: safe,
                                 pointsPerInch: ppi, isPhone: phone)
    }
    let pro11 = resolve(.native, .fit, size: CGSize(width: 1194, height: 834), safe: rect(0, 24, 1194, 790), ppi: 132, phone: false)
    check(abs(pro11.unit - 55.22) < 0.01, "showcase: iPad Pro 11 life-size D is 10.625 mm at 132 ppi, got \(pro11.unit)")
    check(nearPt(centre(pro11, "A"), 1105.62, 573.81) && nearPt(centre(pro11, "stickL"), 88.37, 429.15)
          && nearPt(centre(pro11, "dpad"), 141.39, 573.81) && nearPt(centre(pro11, "HOME"), 597.00, 765.96),
          "showcase: iPad Pro 11 fit/native positions differ from PreviewPadStore")
    check(abs(pro11.video.height - 671.62) < 0.01, "showcase: iPad Pro 11 fit picture is full-bleed 16:9")

    let se = resolve(.native, .native, size: CGSize(width: 667, height: 375), safe: rect(0, 0, 667, 375), ppi: 163, phone: true)
    check(abs(se.unit - 54.95) < 0.01 && nearPt(centre(se, "plus"), 448.58, 198.38) && nearPt(centre(se, "minus"), 218.42, 198.38),
          "showcase: iPhone SE native: +/- at the elbow, unit 54.95, got \(se.unit)")
    check(abs(se.video.minX - 256.34) < 0.01 && abs(se.video.width - 154.32) < 0.01, "showcase: iPhone SE native picture rect \(se.video)")

    let seT = resolve(.iPadPro2020, .fit, size: CGSize(width: 667, height: 375), safe: rect(0, 0, 667, 375), ppi: 163, phone: true)
    check(abs(seT.unit - 41.40) < 0.01 && nearPt(centre(seT, "A"), 600.74, 194.91) && nearPt(centre(seT, "stickR"), 600.74, 86.45)
          && nearPt(centre(seT, "plus"), 516.28, 295.10), "showcase: iPad Pro preset transplanted to iPhone SE differs from PadPresetFitter, unit \(seT.unit)")
    let miniT = resolve(.iPadPro2020, .native, size: CGSize(width: 1133, height: 744), safe: rect(0, 24, 1133, 700), ppi: 163, phone: false)
    check(abs(miniT.unit - 48.66) < 0.01 && nearPt(centre(miniT, "A"), 1055.11, 251.43) && nearPt(centre(miniT, "HOME"), 558.71, 547.26),
          "showcase: iPad Pro preset on iPad mini native differs from PadPresetFitter, unit \(miniT.unit)")
    let up = resolve(.compact, .fit, size: CGSize(width: 440, height: 956), safe: rect(0, 62, 440, 860), ppi: 460.0 / 3, phone: true)
    check(abs(up.unit - 44.90) < 0.01 && nearPt(centre(up, "A"), 368.14, 311.05) && abs(up.video.minY - 62) < 0.01 && abs(up.video.height - 247.5) < 0.01,
          "showcase: phone upright is forced to Native (picture on top), got \(up.unit) \(up.video)")

    // Colour files: the showcase's JSON, byte for byte readable both ways.
    let json = "{\"version\":1,\"name\":\"Mine\",\"outline\":{\"hex\":\"#101010\"},\"fills\":{\"default\":{\"hex\":\"#336699\",\"alpha\":0.5}},\"glyphs\":{\"default\":{\"hex\":\"#FFFFFF\"}},\"pressedAlphaBoost\":0.12}"
    if let file = try? ShowcaseColourFile.decode(Data(json.utf8)) {
        check(file.fill("A").hex == "#336699" && abs(file.alpha("A", pressed: true) - 0.62) < 1e-9, "showcase: .muffinclr fill/alpha lookup")
        check((try? ShowcaseColourFile.decode(file.encoded())) == file, "showcase: .muffinclr round-trips")
    } else { check(false, "showcase: a .muffinclr written by the showcase pad failed to decode") }
    for p in ShowcaseColourPreset.allCases {
        check((try? ShowcaseColourFile.decode(p.file.encoded())) == p.file, "showcase: \(p.rawValue) round-trips as .muffinclr")
    }
    check(ShowcaseColourPresets.wiiUWhite.fill("A").hex == "#F1F1F1" && ShowcaseColourPresets.wiiUWhite.fill("dpad").hex == "#BDBDC1"
          && ShowcaseColourPresets.superFamicom.fill("Y").hex == "#D14B45", "showcase: preset colours")
    check(abs(ShowcaseDeviceMetrics.measurement(identifier: "iPad8,9", nativePixels: CGSize(width: 1668, height: 2388), scale: 2, isPad: true, calibrated: nil).pointsPerInch - 132) < 0.01
          && abs(ShowcaseDeviceMetrics.measurement(identifier: "iPad16,1", nativePixels: .zero, scale: 2, isPad: true, calibrated: nil).pointsPerInch - 163) < 0.01,
          "showcase: points per inch from model")

    // Every review device, both orientations, both display modes, both host layouts, every preset.
    var overlays = 0, clears = 0
    var smallest: (CGFloat, String) = (1, "")
    for device in TargetDevice.showcaseReview {
        for mode in ShowcaseLayout.DisplayMode.allCases {
            for display in TargetDevice.Display.allCases {
                for preset in ShowcaseLayoutPreset.allCases {
                    let pad = ShowcasePad()
                    pad.pointsPerInch = device.showcasePointsPerInch
                    pad.layoutPreset = preset
                    pad.displayMode = mode
                    let ctx = device.context(display)
                    pad.layout(ctx)
                    let where_ = "Showcase / \(device.name) / \(mode.rawValue) / \(display.rawValue) / \(preset.rawValue)"
                    let problems = LayoutCheck.problems(pad.controls, in: ctx.safeBounds)
                    check(problems.isEmpty, "\(where_): \(problems.joined(separator: "; "))")
                    var reach = Set<PadButton>(), sticks = 0
                    for c in pad.controls {
                        switch c.kind {
                        case .button(let b): reach.insert(b)
                        case .dpad: reach.formUnion([.up, .down, .left, .right, .stickL])
                        case .stick: sticks += 1
                        default: break
                        }
                    }
                    check(reach == Set(PadButton.allCases) && sticks == 2, "\(where_): missing \(Set(PadButton.allCases).subtracting(reach))")
                    let avoid: [CGRect]
                    switch pad.arrangement {
                    case .native:
                        let r = pad.pictureRect
                        check(r != nil && abs(r!.width / r!.height - 16.0 / 9) < 0.01 && ctx.safeBounds.insetBy(dx: -1, dy: -1).contains(r!),
                              "\(where_): native picture rect \(String(describing: r))")
                        avoid = r.map { [$0] } ?? []
                    case .clear:
                        clears += 1
                        avoid = ctx.videoRects
                        check(pad.unitPoints >= pad.minimumUnit - 0.01, "\(where_): clear layout under the minimum size")
                    case .overlay:
                        overlays += 1
                        avoid = []
                        check(mode == .fit, "\(where_): only Fit may float over the picture")
                    }
                    for c in pad.controls where !avoid.isEmpty {
                        check(!avoid.contains { $0.insetBy(dx: 1, dy: 1).intersects(c.shape.boundingBox) },
                              "\(where_): \(c.label) covers the picture")
                    }
                    if pad.lifeSizeFraction < smallest.0 { smallest = (pad.lifeSizeFraction, where_) }
                }
            }
        }
    }
    print("showcase: \(clears) clear, \(overlays) overlay; smallest \(Int(smallest.0 * 100))% of life size (\(smallest.1))")
    check(clears >= 36, "showcase: Fit clears the picture in \(clears) of 48 cases, expected at least 36")
    // Fit never shrinks a button under the touch size, however it packs the pad.
    for device in TargetDevice.showcaseReview {
        for display in TargetDevice.Display.allCases {
            for preset in ShowcaseLayoutPreset.allCases {
                let pad = ShowcasePad(); pad.pointsPerInch = device.showcasePointsPerInch; pad.layoutPreset = preset
                pad.layout(device.context(display))
                guard pad.arrangement == .clear else { continue }
                let where_ = "Showcase \(device.name) \(display.rawValue) \(preset.rawValue)"
                for c in pad.controls {
                    switch c.kind {
                    case .button(let b) where c.role == .face || b == .home || c.role == .system:
                        let d = c.shape.boundingBox.width
                        let floor = c.role == .face ? pad.minimumUnit : pad.minimumUnit * (b == .home ? 1.04 : 0.68)
                        check(d >= floor - 0.5, "\(where_): \(b) is \(d) pt, under \(floor)")
                    case .dpad:
                        check(c.shape.boundingBox.width >= 2.28 * pad.minimumUnit - 0.5, "\(where_): d-pad under the touch size")
                    case .stick(let st, _, _):
                        // Each stick keeps its own shoulders within reach.
                        for sh in [PadButton.l, .zl, .r, .zr] where (sh == .l || sh == .zl) == (st == .left) {
                            let sc = pad.controls.first { $0.button == sh }!.shape.center
                            check(sc.distance(to: c.shape.center) <= 4.5 * pad.unitPoints, "\(where_): \(sh) strays from its stick")
                        }
                    default: break
                    }
                }
            }
        }
    }
    // Cases the old fitter gave up on now clear the picture, with + left of - above HOME.
    for (name, display, preset) in [("iPhone SE", TargetDevice.Display.stacked, ShowcaseLayoutPreset.compact),
                                    ("iPad Pro 13", .single, .native), ("iPad mini portrait", .stacked, .native),
                                    ("iPad Pro 11 (A12Z) portrait", .stacked, .iPadPro2020)] {
        let d = TargetDevice.showcaseReview.first { $0.name == name }!
        let pad = ShowcasePad(); pad.pointsPerInch = d.showcasePointsPerInch; pad.layoutPreset = preset
        pad.layout(d.context(display))
        check(pad.arrangement == .clear, "showcase: \(name) \(display.rawValue) \(preset.rawValue) should clear the picture, got \(pad.arrangement)")
        func at(_ b: PadButton) -> CGPoint { pad.controls.first { $0.button == b }!.shape.center }
        check(at(.plus).x < at(.minus).x && abs(at(.plus).y - at(.minus).y) < 1, "showcase: \(name) + is left of - on one row")
        check(at(.home).y > at(.plus).y || abs(at(.home).x - at(.plus).x) > 20, "showcase: \(name) HOME sits with the + / - pair")
    }
    // Shared settings: scale sizes the pad, opacity fades it and firms the look as it fades.
    do {
        let d = TargetDevice.all.first { $0.name.contains("A12Z") }!
        func unit(_ scale: CGFloat) -> CGFloat {
            var ctx = d.context(.stacked); ctx.scale = scale
            let pad = ShowcasePad(); pad.pointsPerInch = 132; pad.layout(ctx); return pad.unitPoints
        }
        check(unit(0.8) < unit(1) - 1 && unit(1) <= unit(1.2) + 0.01, "showcase: the shared scale resizes the pad (\(unit(0.8)), \(unit(1)), \(unit(1.2)))")
        let pad = ShowcasePad(); pad.pointsPerInch = 132; pad.layout(d.context(.stacked))
        let def = pad.scene(pressed: [], sticks: [:])
        check(abs(def.opacity - 0.94) < 1e-9 && pad.scene(pressed: [], sticks: [:], opacity: 1).opacity <= 1
              && abs(pad.scene(pressed: [], sticks: [:], opacity: 0.3).opacity - 0.94 * 0.3 / 0.85) < 1e-9,
              "showcase: scene opacity follows the shared opacity (\(def.opacity))")
        let faint = pad.scene(pressed: [], sticks: [:], opacity: 0.3)
        func maxShadow(_ s: ShowcaseScene) -> Double { s.primitives.compactMap(\.shadow?.opacity).max() ?? 0 }
        check(maxShadow(faint) > maxShadow(def) + 0.05, "showcase: a faint pad gets a firmer shadow")
        check(faint.primitives.count == def.primitives.count, "showcase: a faint pad keeps every control")
    }
    // Colours: every preset is a valid .muffinclr, readable, and distinct.
    do {
        var names = Set<String>()
        for p in ShowcaseColourPreset.allCases {
            let f = p.file
            check(names.insert(f.name).inserted, "showcase: colour preset name \(f.name) is unique")
            check((try? ShowcaseColourFile.decode(f.encoded())) == f && f.version == 1, "showcase: \(p.rawValue) is a version 1 .muffinclr")
            // (Drawing nudges any glyph that is too faint for its fill; the presets added since the
            // first three are expected to be readable as written.)
            for id in ["A", "B", "X", "Y", "dpad", "plus", "L", "R", "stickL", "HOME"] where ![.wiiUWhite, .wiiUBlack, .superFamicom].contains(p) {
                let c = ShowcaseRGBA.contrast(f.glyph(id), f.fill(id).withAlpha(1))
                check(c >= 1.8, "showcase: \(p.rawValue) \(id) glyph contrast \(c)")
            }
        }
        check(ShowcaseColourPreset.allCases.count >= 10, "showcase: colour presets")
    }
    // Press animation: eases down in ~60 ms and back in ~150 ms, snaps with Reduce Motion, settles.
    do {
        var a = ShowcasePressAnimator()
        a.step(pressed: [], time: 0, reduceMotion: false)
        check(!a.isAnimating && a.eased.isEmpty, "showcase: press animator starts idle")
        a.step(pressed: [.a], time: 1, reduceMotion: false)       // first frame after a gap settles
        check(a.eased[.a] == 1 && !a.isAnimating, "showcase: first frame is settled")
        a.step(pressed: [], time: 1.016, reduceMotion: false)
        let mid = a.eased[.a] ?? 0
        check(mid > 0.5 && mid < 1 && a.isAnimating, "showcase: release eases (\(mid))")
        a.step(pressed: [], time: 1.1, reduceMotion: false)
        a.step(pressed: [], time: 1.2, reduceMotion: false)
        check(a.eased[.a] == nil && !a.isAnimating, "showcase: release settles")
        a.step(pressed: [.a], time: 1.216, reduceMotion: false)
        let down = a.eased[.a] ?? 0
        check(down > 0 && down < 1 && a.isAnimating, "showcase: press eases in (\(down))")
        a.step(pressed: [.a], time: 1.3, reduceMotion: false)
        check(a.eased[.a] == 1 && !a.isAnimating, "showcase: press settles")
        var r = ShowcasePressAnimator()
        r.step(pressed: [], time: 0, reduceMotion: true)
        r.step(pressed: [.b], time: 0.016, reduceMotion: true)
        check(r.eased[.b] == 1 && !r.isAnimating, "showcase: Reduce Motion snaps")
        // The scene at an eased amount sits between up and held.
        let d = TargetDevice.all.first { $0.name.contains("A12Z") }!
        let pad = ShowcasePad(); pad.pointsPerInch = 132; pad.layout(d.context(.stacked))
        let up = pad.scene(pressed: [], sticks: [:]), held = pad.scene(pressed: [.a], sticks: [:])
        _ = pad.scene(pressed: [], sticks: [:], time: 10)
        let mid2 = pad.scene(pressed: [.a], sticks: [:], time: 10.03)
        check(pad.isAnimatingPress && mid2 != up && mid2 != held, "showcase: a half-pressed button looks half-pressed")
        _ = pad.scene(pressed: [.a], sticks: [:], time: 10.5)
        check(pad.scene(pressed: [.a], sticks: [:], time: 10.6) == held && !pad.isAnimatingPress, "showcase: settled animation equals the held look")
        _ = pad.scene(pressed: [], sticks: [:], time: 11)
        _ = pad.scene(pressed: [], sticks: [:], time: 11.5)
        check(pad.scene(pressed: [], sticks: [:], time: 11.6) == up, "showcase: settled animation equals the up look")
        // Glass.
        pad.glass = true
        let g = pad.scene(pressed: [], sticks: [:])
        check(g != up && g.primitives.count > up.primitives.count, "showcase: glass changes the look")
        check(g.primitives.allSatisfy { p in if case .vertical = p.fill { return true }; if case .solid = p.fill { return true }; return p.fill == nil },
              "showcase: glass scene is plain data")
    }
    // The GamePad stays a real touchscreen wherever Fit found a margin.
    do {
        let d = TargetDevice.all.first { $0.name.contains("A12Z") }!
        let pad = ShowcasePad(); pad.pointsPerInch = 132; pad.layout(d.context(.stacked))
        check(pad.arrangement == .clear && abs(pad.lifeSizeFraction - 1) < 0.01, "showcase: iPad Pro 11 stacked is clear at life size, got \(pad.arrangement) \(pad.lifeSizeFraction)")
        let face = pad.controls.first { $0.button == .a }!.shape.boundingBox.width
        check(abs(face - 10.625 * 132 / 25.4) < 0.05, "showcase: a face button is 10.625 mm across, got \(face) pt")
    }
    // Window sizes of every shape: Fit and Native both stay valid.
    for mode in ShowcaseLayout.DisplayMode.allCases {
        var bad: [String] = []
        var w: CGFloat = 480
        while w <= 1400 {
            var h: CGFloat = 300
            while h <= 1100 {
                let ctx = LayoutContext(size: CGSize(width: w, height: h), safeInsets: Insets(top: 20, left: 0, bottom: 20, right: 0))
                let pad = ShowcasePad(); pad.displayMode = mode; pad.layout(ctx)
                let p = LayoutCheck.problems(pad.controls, in: ctx.safeBounds)
                if !p.isEmpty { bad.append("\(Int(w))x\(Int(h)): \(p.first!)") }
                h += 80
            }
            w += 70
        }
        check(bad.isEmpty, "Showcase \(mode.rawValue): \(bad.count) window sizes fail, e.g. \(bad.prefix(3).joined(separator: " | "))")
    }

    // Behaviour, through the engine, on the A12Z iPad (Fit, clear) and an iPhone (Native).
    for (name, display, mode) in [("iPad Pro 11 (A12Z)", TargetDevice.Display.stacked, ShowcaseLayout.DisplayMode.fit),
                                  ("iPhone 16 Pro Max", .stacked, .native)] {
        let d = TargetDevice.all.first { $0.name == name }!
        let r = Recorder()
        let pad = ShowcasePad(); pad.pointsPerInch = d.showcasePointsPerInch; pad.displayMode = mode
        let e = PadEngine(scheme: pad, output: r, context: d.context(display))
        func at(_ b: PadButton) -> CGPoint { pad.controls.first { $0.button == b }!.shape.center }
        for b in [PadButton.a, .b, .x, .y, .l, .r, .zl, .zr, .plus, .minus, .home, .stickR] {
            e.began(1, at: at(b), time: 0)
            check(r.held == [b], "showcase \(name): tap \(b) holds exactly \(b), got \(r.held)")
            e.ended(1, at: at(b), time: 0.1)
            check(r.held.isEmpty, "showcase \(name): \(b) released")
        }
        let a = at(.a), b = at(.b)
        e.began(1, at: a, time: 1); e.moved(1, to: b, time: 1.1)
        check(r.held == [.b], "showcase \(name): slide A to B, got \(r.held)")
        e.cancelled(1, time: 1.2)
        check(r.held.isEmpty, "showcase \(name): cancel releases")
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        e.began(2, at: mid, time: 2)
        check(r.held == [.a, .b], "showcase \(name): chord in the gap between A and B, got \(r.held)")
        e.ended(2, at: mid, time: 2.1)
        e.began(1, at: at(.zl), time: 3); e.moved(1, to: at(.l), time: 3.1)
        check(r.held == [.l], "showcase \(name): slide ZL to L, got \(r.held)")
        e.ended(1, at: at(.l), time: 3.2)
        // A finger resting in the gap between the faces and the d-pad is claimed by something (gap-free).
        let dpad = pad.controls.first { if case .dpad = $0.kind { return true }; return false }!
        let c = dpad.shape.center, u = pad.unitPoints
        e.began(1, at: c + CGPoint(x: 0.9 * u, y: -0.9 * u), time: 4)
        check(r.held == [.up, .right], "showcase \(name): d-pad up-right diagonal, got \(r.held)")
        e.moved(1, to: c + CGPoint(x: 0, y: 0.9 * u), time: 4.05)
        check(r.held == [.down], "showcase \(name): d-pad rolls to down, got \(r.held)")
        e.ended(1, at: c, time: 4.1)
        e.began(1, at: c, time: 5)
        check(r.held == [.stickL], "showcase \(name): d-pad centre is L3, got \(r.held)")
        e.ended(1, at: c, time: 5.1)
        let stick = pad.controls.first { if case .stick(.left, _, _) = $0.kind { return true }; return false }!
        e.began(3, at: stick.shape.center, time: 6)
        e.moved(3, to: stick.shape.center + CGPoint(x: 400, y: 0), time: 6.1)
        check(near(r.sticks[.left]?.x ?? 0, 1), "showcase \(name): left stick full right, got \(String(describing: r.sticks[.left]))")
        check(pad.scene(pressed: [], sticks: [:]).primitives.count > 40, "showcase \(name): scene has the full pad")
        e.ended(3, at: .zero, time: 6.2)
        check(r.sticks[.left] == .zero, "showcase \(name): stick recentres")
        // Shared stick settings reach it: a bigger deadzone swallows a small push.
        var ctx = d.context(display); ctx.stick = StickTuning(deadzone: 0.3, curve: 1, gate: .round)
        e.setContext(ctx)
        let s2 = pad.controls.first { if case .stick(.left, _, _) = $0.kind { return true }; return false }!
        e.began(4, at: s2.shape.center, time: 7)
        guard case let .stick(_, travel2, _) = s2.kind else { fatalError() }
        e.moved(4, to: s2.shape.center + CGPoint(x: 0.25 * travel2, y: 0), time: 7.1)
        check(r.sticks[.left] == .zero, "showcase \(name): stick reads context.stick (deadzone)")
        e.ended(4, at: .zero, time: 7.2)
    }

    // Settings: preset, colour and display mode each change the pad, and colour reaches the scene.
    do {
        let d = TargetDevice.all.first { $0.name.contains("A12Z") }!
        let pad = ShowcasePad(); pad.pointsPerInch = 132; pad.layout(d.context(.stacked))
        let before = pad.controls.first { $0.button == .a }!.shape.center
        pad.layoutPreset = .compact
        check(pad.controls.first { $0.button == .a }!.shape.center != before && pad.lifeSizeFraction < 0.8, "showcase: Compact preset re-lays out at 70%")
        pad.layoutPreset = .native
        pad.displayMode = .native
        check(pad.arrangement == .native && pad.pictureRect != nil, "showcase: display mode switches to Native")
        let white = pad.scene(pressed: [], sticks: [:])
        pad.colourPreset = .wiiUBlack
        check(pad.scene(pressed: [], sticks: [:]) != white, "showcase: colour preset changes the scene")
        let held = pad.scene(pressed: [.a], sticks: [:])
        check(held != pad.scene(pressed: [], sticks: [:]), "showcase: a held button looks different")
    }
}

// MARK: Engine: stuck inputs, press latency, multi-touch, catchment, stick feel

/// Every scheme on every device and display, as a ready engine.
func forEachEngine(_ body: (SchemeInfo, TargetDevice, TargetDevice.Display, PadEngine, Recorder, ControlScheme) -> Void) {
    for info in SchemeCatalog.all {
        for device in TargetDevice.all {
            for display in TargetDevice.Display.allCases {
                let r = Recorder()
                let e = PadEngine(scheme: SchemeCatalog.make(info.id), output: r, context: device.context(display))
                body(info, device, display, e, r, e.scheme as! ControlScheme)
            }
        }
    }
}
func isPress(_ c: PadControl) -> Bool {
    switch c.kind { case .button, .pedal: return true; default: return false }
}
func where_(_ info: SchemeInfo, _ d: TargetDevice, _ x: TargetDevice.Display) -> String { "\(info.id) / \(d.name) / \(x)" }
/// Every press has exactly one release.
func balanced(_ log: [String]) -> Bool {
    var open: [String: Int] = [:]
    for entry in log {
        if entry == "releaseAll" { open = [:]; continue }
        let name = String(entry.dropLast())
        if entry.hasSuffix("+") { open[name, default: 0] += 1 } else if entry.hasSuffix("-") { open[name, default: 0] -= 1 }
        if open[name]! < 0 || open[name]! > 1 { return false }
    }
    return open.values.allSatisfy { $0 == 0 }
}

// A press is decided on touch-down: held the moment `began` returns, with no tick, no time passing.
var pressedOnDown = 0
forEachEngine { info, device, display, e, r, s in
    for c in s.controls where c.button != nil && c.priority == 1 && c.role != .dot {
        e.began(1, at: c.shape.center, time: 0)
        check(r.held.contains(c.button!), "press on touch-down: \(c.button!) on \(where_(info, device, display))")
        pressedOnDown += 1
        e.ended(1, at: c.shape.center, time: 0.001)
        check(r.held.isEmpty, "release on touch-up: \(c.button!) on \(where_(info, device, display))")
    }
    check(balanced(r.log), "every press released exactly once on \(where_(info, device, display)): \(r.log.prefix(8))")
}
check(pressedOnDown > 1000, "press-on-touch-down was exercised widely (\(pressedOnDown))")

// Gap-free catchment: between neighbours of one slide group or cluster, every point on the line
// joining their centres presses something.
var gapPairs = 0
forEachEngine { info, device, display, e, r, s in
    let u = e.context.unit
    let items = s.controls.filter(isPress)
    s.clusterOffsets = [:]
    for (i, a) in items.enumerated() {
        for b in items[(i + 1)...] where (a.group != 0 && a.group == b.group) || (a.cluster >= 0 && a.cluster == b.cluster) {
            let ca = a.shape.center, cb = b.shape.center
            guard max(a.shape.edgeDistance(to: cb), b.shape.edgeDistance(to: ca)) < u else { continue }
            gapPairs += 1
            for k in 0...20 {
                let t = CGFloat(k) / 20
                let p = CGPoint(x: ca.x + (cb.x - ca.x) * t, y: ca.y + (cb.y - ca.y) * t)
                s.clusterOffsets = [:]      // Adaptive drifts a cluster toward a press; probe the layout as drawn
                e.began(1, at: p, time: 0)
                check(!r.held.isEmpty || e.mixer.contribution(for: 1)?.stick != nil, "no dead gap between \(a.label) and \(b.label) at \(p) on \(where_(info, device, display))")
                e.ended(1, at: p, time: 0.01)
            }
        }
    }
}
check(gapPairs > 300, "gap check covered neighbouring buttons (\(gapPairs) pairs)")

// Bounded: a button's catchment ends within a modest distance of its drawn edge, so it never
// reaches far into the GamePad touchscreen or the open screen.
forEachEngine { info, device, display, e, r, s in
    let u = e.context.unit
    for c in s.controls where isPress(c) && c.role != .pedal {
        check(c.reach <= 0.85 * u, "\(c.label) catchment reaches \(c.reach / u)u past its edge on \(where_(info, device, display))")
    }
}

// Slide: a finger rolling between buttons of a slide group moves the press, in every scheme.
var slides = 0
forEachEngine { info, device, display, e, r, s in
    var groups: [Int: [PadControl]] = [:]
    for c in s.controls where c.button != nil && c.group != 0 { groups[c.group, default: []].append(c) }
    for (_, members) in groups where members.count > 1 {
        for from in members {
            for to in members where to.button != from.button {
                e.began(1, at: from.shape.center, time: 0)
                e.moved(1, to: to.shape.center, time: 0.05)
                check(r.held == [to.button!], "slide \(from.label)->\(to.label) leaves only \(to.label) held, got \(r.held) on \(where_(info, device, display))")
                slides += 1
                e.ended(1, at: to.shape.center, time: 0.1)
            }
        }
    }
    check(r.held.isEmpty && balanced(r.log), "slides leave nothing held and every press released once on \(where_(info, device, display))")
}
check(slides > 300, "slides were exercised (\(slides))")

// Chords: a thumb on the seam between two chording buttons presses both.
var chordsTried = 0
forEachEngine { info, device, display, e, r, s in
    let ch = s.controls.filter { $0.chords && $0.button != nil }
    for (i, a) in ch.enumerated() {
        for b in ch[(i + 1)...] where a.group == b.group {
            let gap = max(a.shape.edgeDistance(to: b.shape.center), b.shape.edgeDistance(to: a.shape.center))
            guard gap < 0.9 * e.context.unit, gap > 0 else { continue }
            let mid = CGPoint(x: (a.shape.center.x + b.shape.center.x) / 2, y: (a.shape.center.y + b.shape.center.y) / 2)
            if s.controls.contains(where: { $0.priority > 1 && $0.shape.edgeDistance(to: mid) <= $0.reach }) { continue }
            s.clusterOffsets = [:]
            e.began(1, at: mid, time: 0)
            check(r.held == [a.button!, b.button!], "seam between \(a.label) and \(b.label) presses both, got \(r.held) on \(where_(info, device, display))")
            chordsTried += 1
            e.ended(1, at: mid, time: 0.1)
        }
    }
}
check(chordsTried > 100, "chords were exercised (\(chordsTried))")

// Multi-touch: three fingers, two on one button, ended together or cancelled together.
forEachEngine { info, device, display, e, r, s in
    let btns = s.controls.filter { $0.button != nil && $0.priority == 1 && $0.role != .dot }
    guard btns.count >= 3 else { return }
    let w = where_(info, device, display)
    // three fingers on three different, well-separated buttons
    var chosen: [PadControl] = []
    for c in btns where chosen.allSatisfy({ $0.shape.edgeDistance(to: c.shape.center) > 1.5 * e.context.unit }) { chosen.append(c) }
    if chosen.count >= 3 {
        for (i, c) in chosen.prefix(3).enumerated() { e.began(10 + i, at: c.shape.center, time: 0) }
        check(r.held == Set(chosen.prefix(3).map { $0.button! }), "three fingers hold three buttons on \(w), got \(r.held)")
        e.ended(11, at: chosen[1].shape.center, time: 0.1)
        check(r.held == Set([chosen[0].button!, chosen[2].button!]), "lifting the middle finger leaves the others on \(w)")
        e.cancelled(10, time: 0.1); e.cancelled(12, time: 0.1)
        check(r.held.isEmpty, "cancelling two fingers in one event releases both on \(w)")
        e.cancelled(10, time: 0.2); e.ended(12, at: .zero, time: 0.2)
        check(balanced(r.log) && r.held.isEmpty, "a repeated end or cancel releases nothing twice on \(w): \(r.log)")
    }
    // two fingers on the same button: held until both lift
    let b = btns[0]
    e.began(20, at: b.shape.center, time: 1)
    e.began(21, at: b.shape.center, time: 1)
    e.ended(20, at: b.shape.center, time: 1.1)
    check(r.held == [b.button!], "button stays held while a second finger is on it on \(w)")
    e.ended(21, at: b.shape.center, time: 1.2)
    check(r.held.isEmpty && balanced(r.log), "button released only when both fingers lift on \(w)")
}

// Everything that can end a press early or late: release once and only once.
forEachEngine { info, device, display, e, r, s in
    guard let a = s.controls.first(where: { $0.button == .a }) ?? s.controls.first(where: { $0.button != nil && $0.priority == 1 }) else { return }
    let w = where_(info, device, display)
    // scheme switch mid-press
    e.began(1, at: a.shape.center, time: 0)
    e.setScheme(SchemeCatalog.make(info.id == "zone" ? "float" : "zone"))
    check(r.held.isEmpty && balanced(r.log), "switching scheme mid-press releases it on \(w)")
    e.ended(1, at: a.shape.center, time: 0.1)       // the old finger lifting later is harmless
    check(r.held.isEmpty && balanced(r.log), "...and the late touch-up is harmless on \(w)")
    e.setScheme(SchemeCatalog.make(info.id))
    // rotation / resize mid-press
    let before = e.context
    e.began(2, at: e.scheme is ControlScheme ? (e.scheme as! ControlScheme).controls.first(where: { $0.button != nil && $0.priority == 1 })!.shape.center : .zero, time: 1)
    var rotated = before; rotated.size = CGSize(width: before.size.height, height: before.size.width)
    e.setContext(rotated)
    check(r.held.isEmpty && balanced(r.log), "rotating mid-press releases it on \(w)")
    e.moved(2, to: CGPoint(x: 100, y: 100), time: 1.1); e.ended(2, at: CGPoint(x: 100, y: 100), time: 1.2)
    check(r.held.isEmpty && balanced(r.log), "...and the old finger moving and lifting does nothing on \(w)")
    // backgrounding / view leaving the window / scene disconnect all end in cancelAll
    e.setContext(before)
    let again = (e.scheme as! ControlScheme).controls.first(where: { $0.button != nil && $0.priority == 1 })!.shape.center
    e.began(3, at: again, time: 2)
    e.began(4, at: again, time: 2)
    e.cancelAll()
    check(r.held.isEmpty && balanced(r.log) && e.heldTouches.isEmpty, "cancelAll releases every finger on \(w)")
    e.ended(3, at: again, time: 2.1); e.cancelled(4, time: 2.1)
    check(r.held.isEmpty && balanced(r.log), "...and the fingers' late ends are harmless on \(w)")
}

// A new finger that reuses a leaked finger's identity must not inherit or leave behind its press.
do {
    let (e, r, s) = engine("zone")
    e.began(1, at: centre(s, .a), time: 0)
    check(r.held == [.a], "setup")
    var dead: CGPoint?
    outer: for x in stride(from: CGFloat(5), to: e.context.size.width, by: 11) {
        for y in stride(from: CGFloat(5), to: e.context.size.height, by: 11) where !e.claims(CGPoint(x: x, y: y)) {
            dead = CGPoint(x: x, y: y); break outer
        }
    }
    check(dead != nil, "found a point nothing claims")
    e.began(1, at: dead!, time: 1)
    check(r.held.isEmpty, "a reused finger identity landing on nothing drops the old press, held \(r.held)")
    check(e.heldTouches.isEmpty, "...and is not held")
    // a finger the system no longer lists
    e.began(2, at: centre(s, .b), time: 2)
    e.began(3, at: centre(s, .a), time: 2)
    e.reconcile(live: [3])
    check(r.held == [.a], "reconcile drops a finger the system no longer lists, held \(r.held)")
    e.reconcile(live: [])
    check(r.held.isEmpty && balanced(r.log), "reconcile with nothing live releases all")
}

// A stick keeps its finger across zones; a button finger leaving the pad lets go and re-presses on return.
do {
    let (e, r, s) = engine("zone")
    let stick = stickControl(s, .left)!
    let start = stick.0.shape.center + CGPoint(x: stick.travel * 0.6, y: 0)
    e.began(1, at: start, time: 0)
    e.moved(1, to: centre(s, .a), time: 0.1)
    check(!r.held.contains(.a), "a finger on the stick sliding over A does not press A")
    check(e.mixer.contribution(for: 1)?.stick == .left, "the stick keeps its finger")
    e.ended(1, at: centre(s, .a), time: 0.2)
    check(r.sticks[.left] == .zero || r.sticks[.left] == nil, "stick centres when its finger lifts")

    e.began(2, at: centre(s, .a), time: 1)
    e.moved(2, to: CGPoint(x: -400, y: -400), time: 1.1)
    check(r.held.isEmpty, "a button finger sliding off the pad edge lets go")
    e.moved(2, to: centre(s, .a), time: 1.2)
    check(r.held == [.a], "...and presses again when it slides back")
    e.ended(2, at: centre(s, .a), time: 1.3)
    check(r.held.isEmpty && balanced(r.log), "...and releases once")
}

// Stick feel (opt-in): defaults are exactly the old behaviour; follow and relative are off.
check(!StickTuning().followsThumb && !StickTuning().relativeCentre, "stick follow and relative centre default to off")
check(StickTuning() == StickTuning(deadzone: 0.06, curve: 1, gate: .octagon), "default tuning is unchanged")
for id in ["zone", "float", "frame", "showcase"] {
    func run(_ tuning: StickTuning, _ offsets: [CGFloat]) -> (values: [StickValue], base: [CGPoint]) {
        var ctx = ipad.context(.stacked); ctx.stick = tuning
        let r = Recorder()
        let e = PadEngine(scheme: SchemeCatalog.make(id), output: r, context: ctx)
        let s = e.scheme as! ControlScheme
        guard let (c, travel, floating) = stickControl(s, .left) else { return ([], []) }
        let start = floating ? c.shape.center : c.shape.center + CGPoint(x: travel * 0.5, y: 0)
        e.began(1, at: start, time: 0)
        var values = [e.mixer.sticks[.left] ?? .zero]
        for (i, o) in offsets.enumerated() {
            e.moved(1, to: start + CGPoint(x: o * travel, y: 0), time: Double(i + 1) * 0.01)
            values.append(e.mixer.sticks[.left] ?? .zero)
        }
        let base = s.render(pressed: [], sticks: e.mixer.sticks).filter { $0.role == .stickBase || $0.role == .dot }
            .map { $0.shape.center }
        return (values, base)
    }
    let plain = run(StickTuning(), [1, 2, 3, 2])
    guard plain.values.count == 5 else { continue }
    // default: behaves as the plain maths says
    check(plain.values[3].magnitude > 0.99 && plain.values[4].magnitude > 0.99, "\(id): by default a thumb pushed past the ring and back a little stays at full")
    var follow = StickTuning(); follow.followsThumb = true
    let f = run(follow, [1, 2, 3, 2])
    check(f.values[3].magnitude > 0.99, "\(id): follow, pushed past the ring: full output")
    check(f.values[4].magnitude < 0.4, "\(id): follow, thumb back one travel: the base came along so the stick eases off, got \(f.values[4].magnitude)")
    check(f.base != plain.base, "\(id): follow moves the drawn base")
}
do {
    var rel = StickTuning(); rel.relativeCentre = true
    var ctx = ipad.context(.stacked); ctx.stick = rel
    let r = Recorder()
    let e = PadEngine(scheme: SchemeCatalog.make("zone"), output: r, context: ctx)
    let s = e.scheme as! ControlScheme
    let (c, travel, _) = stickControl(s, .left)!
    let land = c.shape.center + CGPoint(x: travel * 0.7, y: travel * 0.3)
    e.began(1, at: land, time: 0)
    check((r.sticks[.left] ?? .zero) == .zero, "relative stick: landing off-centre is not a push")
    e.moved(1, to: land + CGPoint(x: travel, y: 0), time: 0.1)
    check(near(r.sticks[.left]?.x ?? 0, 1, 0.01), "relative stick: full output one travel from where it landed")
    let drawn = s.render(pressed: [], sticks: e.mixer.sticks).first { $0.role == .stickBase }
    check(drawn?.shape.center == land, "relative stick: the ring is drawn where the thumb landed")
    e.ended(1, at: land, time: 0.2)
    check(s.render(pressed: [], sticks: [:]).first { $0.role == .stickBase }?.shape.center == c.shape.center, "relative stick: the ring returns to its place on release")
    // the same landing without the option is a push
    let (e2, r2, s2) = engine("zone")
    let c2 = stickControl(s2, .left)!
    e2.began(1, at: c2.0.shape.center + CGPoint(x: c2.travel * 0.7, y: c2.travel * 0.3), time: 0)
    check((r2.sticks[.left] ?? .zero) != .zero, "default stick: landing off-centre is a push, as before")
}


// MARK: Classic look (PadStyle) and Racing item/edge options

do {
    let ids = ["zone", "float", "adaptive", "frame", "racing"]
    for id in ids {
        check(PadStyle.appliesTo(id), "style: \(id) uses the shared look")
        for device in TargetDevice.all {
            for display in TargetDevice.Display.allCases {
                let ctx = device.context(display)
                let engine = PadEngine(scheme: SchemeCatalog.make(id), output: Recorder(), context: ctx)
                let els = engine.render()
                let base = PadStyle.scene(elements: els, size: ctx.size)
                check(!base.primitives.isEmpty, "style: \(id) / \(device.name): empty scene")
                // Every primitive stays finite and on a sane canvas.
                var finite = true
                for p in base.primitives {
                    switch p.shape {
                    case .circle(let c, let r): finite = finite && c.x.isFinite && c.y.isFinite && r >= 0
                    case .rect(let r, let cr): finite = finite && r.width >= 0 && r.height >= 0 && cr >= 0
                    case .path(let cmds): finite = finite && !cmds.isEmpty
                    }
                }
                check(finite, "style: \(id) / \(device.name) / \(display.rawValue): bad primitive")
                if device.name == "iPhone 16", display == .single {
                    for preset in ShowcaseColourPreset.allCases {
                        check(PadStyle.scene(elements: els, size: ctx.size, look: PadStyle.look(preset)) != base,
                              "style: \(id) preset \(preset.rawValue) changes the look")
                    }
                }
            }
        }
    }
    check(!PadStyle.appliesTo("arc") && !PadStyle.appliesTo("showcase"), "style: Arc and Showcase keep their own looks")
    check(PadStyle.cornerRadius(width: 200, height: 40) == 40 * 0.26 && PadStyle.cornerRadius(width: 900, height: 900) == 18,
          "style: one corner rule")
    // Pressed looks different from idle for every role.
    let c = CGPoint(x: 50, y: 50)
    for (role, shape) in [(RenderElement.Role.face, PadShape.circle(center: c, radius: 30)),
                          (.shoulder, .roundedRect(CGRect(x: 0, y: 0, width: 80, height: 40), cornerRadius: 10)),
                          (.system, .circle(center: c, radius: 20)), (.dpad, .roundedRect(CGRect(x: 0, y: 0, width: 40, height: 40), cornerRadius: 10)),
                          (.pedal, .roundedRect(CGRect(x: 0, y: 0, width: 80, height: 90), cornerRadius: 10)),
                          (.dot, .circle(center: c, radius: 12)), (.stickKnob, .circle(center: c, radius: 30))] {
        for preset in PadStyle.choices {
            let off = PadStyle.scene(elements: [RenderElement(shape: shape, role: role, label: "A")], size: CGSize(width: 100, height: 100), look: PadStyle.look(preset))
            let on = PadStyle.scene(elements: [RenderElement(shape: shape, role: role, label: "A", lit: true)], size: CGSize(width: 100, height: 100), look: PadStyle.look(preset))
            check(off != on, "style: \(role) held reads differently (\(PadStyle.name(preset)))")
        }
    }
    check(PadSettings().colourPreset == nil, "style: default look is Classic")
    check(PadStyle.look(nil).lit != nil && PadStyle.look(.wiiUWhite).lit == nil, "style: Classic keeps its yellow, presets use the Showcase press")
}

for placement in RacingPad.ItemPlacement.allCases {
    for large in [false, true] {
        for tilt in [false, true] {
            let options = RacingPad.Options(tilt: tilt, itemPlacement: placement, largeItem: large)
            for device in TargetDevice.all {
                for display in TargetDevice.Display.allCases {
                    let scheme = RacingPad(options: options)
                    let ctx = device.context(display)
                    scheme.layout(ctx)
                    let where_ = "Racing \(placement)/large=\(large)/tilt=\(tilt) / \(device.name) / \(display.rawValue)"
                    check(LayoutCheck.problems(scheme.controls, in: ctx.safeBounds).isEmpty,
                          "\(where_): \(LayoutCheck.problems(scheme.controls, in: ctx.safeBounds).joined(separator: "; "))")
                    let item = scheme.controls.first { $0.button == .l }
                    check(item != nil, "\(where_): no item button")
                    if let item, device.size.width > device.size.height, placement != .centre {
                        // Off the centre, the item is either above the steering area or above the pedals, never over a pedal.
                        let box = item.shape.boundingBox
                        let overPedal = scheme.controls.contains { c in
                            if case .pedal = c.kind { return c.shape.boundingBox.intersects(box) }
                            return false
                        }
                        check(!overPedal, "\(where_): item over a pedal")
                    }
                }
            }
        }
    }
}

// Racing's controls leave the screen edge clear but still catch a touch right at it.
do {
    let ctx = ipad.context(.single)
    let pad = RacingPad()
    pad.layout(ctx)
    let a = pad.controls.first { if case .pedal(let s) = $0.kind { return s == [.a] }; return false }!
    let box = a.shape.boundingBox
    check(box.maxX < ctx.safeBounds.maxX && box.maxY < ctx.safeBounds.maxY, "racing: accelerate stops short of the screen edge")
    check(pad.claims(CGPoint(x: ctx.safeBounds.maxX - 0.5, y: box.midY)), "racing: but the edge itself still presses it")
    let (_, steer) = steerSpec(pad)
    check(steer.minX > ctx.safeBounds.minX && pad.claims(CGPoint(x: ctx.safeBounds.minX + 0.5, y: steer.midY)),
          "racing: steering area clears the edge and still takes a touch at it")
}

// Glyphs are drawn shapes: + is a horizontal and a vertical stroke, - one horizontal, home a filled house.
do {
    func strokes(_ label: String) -> [(CGRect)] {
        let c = CGPoint(x: 50, y: 50)
        let sc = PadStyle.scene(elements: [RenderElement(shape: .circle(center: c, radius: 20), role: .system, label: label)],
                                size: CGSize(width: 100, height: 100))
        return sc.primitives.compactMap { p in
            guard case .path(let cmds) = p.shape, p.stroke != nil, p.fill == nil else { return nil }
            let pts = cmds.compactMap { cmd -> CGPoint? in
                switch cmd { case .move(let a), .line(let a): return a; default: return nil }
            }
            guard let f = pts.first else { return nil }
            return pts.reduce(CGRect(origin: f, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        }
    }
    let plus = strokes("+"), minus = strokes("\u{2212}")
    check(plus.count == 2, "glyph: + draws two strokes, got \(plus.count)")
    check(plus.contains { $0.height == 0 && $0.width > 5 } && plus.contains { $0.width == 0 && $0.height > 5 }, "glyph: + has one horizontal and one vertical stroke")
    check(minus.count == 1 && minus[0].height == 0 && minus[0].width > 5, "glyph: minus is one horizontal stroke")
    let home = PadStyle.scene(elements: [RenderElement(shape: .circle(center: CGPoint(x: 50, y: 50), radius: 20), role: .system, label: "\u{2302}")],
                              size: CGSize(width: 100, height: 100))
    check(home.primitives.contains { if case .path(let c) = $0.shape { return c.count == 12 && $0.fill != nil }; return false }, "glyph: home is a filled house")
    for (label, n) in [("\u{25B2}", 0), ("\u{25BC}", 1), ("\u{25C0}", 2), ("\u{25B6}", 3)] {
        let sc = PadStyle.scene(elements: [RenderElement(shape: .roundedRect(CGRect(x: 30, y: 30, width: 40, height: 40), cornerRadius: 8), role: .dpad, label: label)],
                                size: CGSize(width: 100, height: 100))
        let tri = sc.primitives.last
        guard let tri, case .path(let cmds) = tri.shape, case .move(let apex) = cmds[0] else { check(false, "glyph: arrow \(n) missing"); continue }
        let dx = apex.x - 50, dy = apex.y - 50
        let ok = [dy < -1 && abs(dx) < 0.01, dy > 1 && abs(dx) < 0.01, dx < -1 && abs(dy) < 0.01, dx > 1 && abs(dy) < 0.01][n]
        check(ok, "glyph: arrow \(label) points the right way")
    }
    // Every scheme, every device: each + and minus on screen is drawn with the right stroke count.
    for id in ["zone", "float", "adaptive", "frame", "racing"] {
        for device in TargetDevice.all {
            let ctx = device.context(.single)
            let engine = PadEngine(scheme: SchemeCatalog.make(id), output: Recorder(), context: ctx)
            let els = engine.render()
            let sc = PadStyle.scene(elements: els, size: ctx.size)
            let wantStrokes = els.filter { $0.role == .system && $0.label == "+" }.count * 2 + els.filter { $0.role == .system && $0.label == "\u{2212}" }.count
            let have = sc.primitives.filter { if case .path = $0.shape { return $0.stroke != nil && $0.fill == nil && $0.strokeWidth > 1.5 && $0.text == nil }; return false }.count
            // d-pad rim strokes are circles/rects, not paths, so every stroked path of this kind is a glyph stroke.
            check(have == wantStrokes, "glyph: \(id) / \(device.name): \(have) glyph strokes, expected \(wantStrokes)")
        }
    }
}

runArcPolishChecks()

print("\(passes) passed, \(failures) failed")
exit(Int32(min(failures, 125)))
