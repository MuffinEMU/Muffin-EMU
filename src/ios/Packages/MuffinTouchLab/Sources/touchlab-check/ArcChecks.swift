import CoreGraphics
import Foundation
import TouchLabCore

// Arc polish: calibration quality checks and previews, fine-tune snapping and undo, the lock
// indicator, quiet mode over video, the idle fade, and swapped hands. Called from main.swift.

private func arcPoints(_ pivot: CGPoint, _ side: ArcSide, _ radius: CGFloat, from: CGFloat, to: CGFloat, steps: Int,
                       jitter: CGFloat = 0, zigzag: CGFloat = 0) -> [CGPoint] {
    var seed: UInt64 = 0xA5A5_1234
    func rnd() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(seed >> 11) / Double(1 << 53)) - 0.5
    }
    return (0...steps).map { i in
        let phi = from + (to - from) * CGFloat(i) / CGFloat(steps)
        let r = radius * (1 + (i % 2 == 0 ? zigzag : -zigzag))
        return CGPoint(x: pivot.x + side.inboardSign * r * sin(phi) + rnd() * jitter,
                       y: pivot.y - r * cos(phi) + rnd() * jitter)
    }
}

private func play(_ eng: PadEngine, id: Int, _ pts: [CGPoint], t0: Double, lift: Bool = true) {
    eng.began(id, at: pts[0], time: t0)
    for (i, p) in pts.enumerated().dropFirst() { eng.moved(id, to: p, time: t0 + Double(i) * 0.02) }
    if lift { eng.ended(id, at: pts[pts.count - 1], time: t0 + Double(pts.count) * 0.02) }
}

private func element(_ eng: PadEngine, label: String) -> RenderElement? {
    eng.render().first { $0.label == label && $0.role != .stickKnob }
}

func runArcPolishChecks() {
    let mini = TargetDevice.all.first { $0.name == "iPad mini" }!
    let open = LayoutContext(size: CGSize(width: 1376, height: 1032), safeInsets: Insets(top: 24, bottom: 20))

    // MARK: Calibration quality

    do {
        let ctx = mini.context(.stacked)
        let u = ctx.unit, w = ctx.size.width, h = ctx.size.height
        let lp = CGPoint(x: 10, y: h + 40), rp = CGPoint(x: w - 10, y: h + 40)
        let rad = 6.2 * u
        let friendly = "Try a longer, smoother sweep"

        func session() -> (ArcPad, PadEngine) {
            let arc = ArcPad()
            let eng = PadEngine(scheme: arc, output: Recorder(), context: ctx)
            arc.startCalibration()
            return (arc, eng)
        }

        // Too short, too wobbly (scatter, and going back and forth), straight: each is refused
        // with a note that says what to do, and the thumb stays the same.
        let cases: [(String, [CGPoint], String)] = [
            ("short", arcPoints(lp, .left, rad, from: 0.5, to: 0.6, steps: 30), "too short"),
            ("scattered", arcPoints(lp, .left, rad, from: 0.3, to: 1.25, steps: 90, jitter: 0.4 * rad), "wobbly"),
            ("back and forth", arcPoints(lp, .left, rad, from: 0.3, to: 1.2, steps: 40)
                + arcPoints(lp, .left, rad, from: 1.2, to: 0.4, steps: 40)
                + arcPoints(lp, .left, rad, from: 0.4, to: 1.2, steps: 40), "wobbly"),
            ("straight", (0...60).map { CGPoint(x: 60 + CGFloat($0) * 6, y: h - 80 - CGFloat($0) * 0.4) }, "curve"),
        ]
        for (name, pts, word) in cases {
            let (arc, eng) = session()
            play(eng, id: 1, pts, t0: 1)
            check(arc.calibrationPhase == .left, "arc polish: a \(name) sweep is not accepted")
            let note = arc.calibrationNote ?? ""
            check(note.contains(word) && note.contains(friendly), "arc polish: the \(name) note says what to do, got '\(note)'")
        }
        // A real thumb sweep, with ordinary jitter, still passes.
        do {
            let (arc, eng) = session()
            play(eng, id: 1, arcPoints(lp, .left, rad, from: 0.3, to: 1.25, steps: 100, jitter: 6), t0: 1)
            check(arc.calibrationPhase == .right && arc.calibrationNote == nil, "arc polish: a jittery but real sweep is accepted")
        }

        // The animated guide: waits for the thumb, moves with the clock, and stops when the review comes.
        do {
            let (arc, eng) = session()
            arc.animationTime = 0.3
            let early = eng.render().first { $0.role == .handle && $0.lit }
            arc.animationTime = 1.4
            let later = eng.render().first { $0.role == .handle && $0.lit }
            check(early != nil && later != nil && early!.shape.center != later!.shape.center, "arc polish: the guide dot travels")
            check(eng.render().contains { $0.role == .guide && $0.dash > 0 }, "arc polish: the guide shows the arc to sweep")
            check(arc.needsTicks, "arc polish: the guide animates, so it asks for ticks")
            check(arc.calibrationStep == "Left thumb, 1 of 2", "arc polish: step text")
            // A finger down hides the guide and draws the trace and the live fit.
            let pts = arcPoints(lp, .left, rad, from: 0.3, to: 0.9, steps: 50, jitter: 4)
            play(eng, id: 1, pts, t0: 1, lift: false)
            let live = eng.render()
            check(!live.contains { $0.role == .guide && $0.dash > 0 }, "arc polish: the guide steps aside under a thumb")
            check(live.contains { $0.role == .guide && $0.tone == .good && $0.width >= 4 }, "arc polish: a clean sweep draws its fit in green")
            check(!arc.needsTicks, "arc polish: no ticks while the thumb drives the redraw")
            eng.ended(1, at: pts[pts.count - 1], time: 3)
            // Scattered samples draw the same fit in amber.
            let (arc2, eng2) = session()
            play(eng2, id: 1, arcPoints(lp, .left, rad, from: 0.3, to: 1.1, steps: 50, zigzag: 0.13), t0: 1, lift: false)
            check(eng2.render().contains { $0.role == .guide && $0.tone == .warn }, "arc polish: a wobbly sweep draws amber")
            _ = arc2
        }

        // The review shows the finished layout, and it is the layout Done saves.
        do {
            let (arc, eng) = session()
            play(eng, id: 1, arcPoints(lp, .left, rad, from: 0.3, to: 1.25, steps: 100, jitter: 5), t0: 1)
            play(eng, id: 2, arcPoints(rp, .right, rad, from: 0.3, to: 1.25, steps: 100, jitter: 5), t0: 5)
            check(arc.calibrationPhase == .review && !arc.needsTicks, "arc polish: review does not animate")
            let review = eng.render()
            let labels = Set(review.filter { $0.role == .face }.map(\.label))
            check(labels == ["A", "B", "X", "Y"], "arc polish: the review shows the fitted layout, got \(labels)")
            let a = review.first { $0.label == "A" && $0.role == .face }!.shape.center
            let upEl = review.first { $0.label == PadButton.up.description && $0.role == .dpad }?.shape.center
            arc.acceptCalibration()
            check(arc.controls.first { $0.button == .a }!.shape.center == a, "arc polish: Done keeps exactly the previewed layout")
            check(upEl != nil && arc.controls.first { $0.button == .up }!.shape.center == upEl!, "arc polish: the d-pad too")
        }

        // Both orientations, on every Arc device: the whole flow, preview and Done.
        for d in arcDevices() {
            let c = d.context(.stacked)
            let arc = ArcPad()
            let eng = PadEngine(scheme: arc, output: Recorder(), context: c)
            let r = 6.2 * c.unit
            let l = CGPoint(x: 10, y: c.size.height + 40), rr = CGPoint(x: c.size.width - 10, y: c.size.height + 40)
            arc.startCalibration()
            play(eng, id: 1, arcPoints(l, .left, r, from: 0.3, to: 1.25, steps: 100, jitter: 4), t0: 1)
            play(eng, id: 2, arcPoints(rr, .right, r, from: 0.3, to: 1.25, steps: 100, jitter: 4), t0: 5)
            check(arc.calibrationPhase == .review, "arc polish \(d.name): both sweeps accepted (\(arc.calibrationNote ?? ""))")
            let faces = eng.render().filter { $0.role == .face }
            check(faces.count == 4, "arc polish \(d.name): the review preview lays out the faces")
            let bounds = c.safeBounds.insetBy(dx: -1, dy: -1)
            check(faces.allSatisfy { bounds.contains($0.shape.center) }, "arc polish \(d.name): the preview stays on screen")
            arc.acceptCalibration()
            check(arc.isLocked && LayoutCheck.problems(arc.controls, in: c.safeBounds).isEmpty, "arc polish \(d.name): Done locks a clean layout")
            // Every message a banner can show fits: wrapped lines never run wider than the screen.
            arc.startCalibration()
            check(arc.isCalibrating == false, "arc polish \(d.name): locked refuses to calibrate again")
            arc.setLocked(false)
            arc.startCalibration()
            let ui = eng.render().filter { $0.role == .system && !$0.label.isEmpty }
            check(ui.allSatisfy { $0.shape.boundingBox.minX >= 0 && $0.shape.boundingBox.maxX <= c.size.width }, "arc polish \(d.name): prompt pills fit the width")
        }
    }

    // MARK: Fine-tune: snap, undo, handles

    do {
        func tuned(_ profiles: [String: ArcProfile] = [:]) -> (ArcPad, PadEngine, Recorder) {
            let arc = ArcPad(profiles: profiles)
            let out = Recorder()
            let eng = PadEngine(scheme: arc, output: out, context: open)
            return (arc, eng, out)
        }
        func drag(_ eng: PadEngine, _ hand: ArcHand, from p: CGPoint, id: Int, t: Double, dphi: CGFloat, dr: CGFloat = 0, steps: Int = 12) {
            let (r0, phi0) = hand.polar(p)
            eng.began(id, at: p, time: t)
            for i in 1...steps {
                let f = CGFloat(i) / CGFloat(steps)
                eng.moved(id, to: hand.point(r: r0 + dr * f, phi: phi0 + dphi * f), time: t + Double(i) * 0.02)
            }
            eng.ended(id, at: p, time: t + 1)
        }

        // Handles: a ring on everything movable while tuning, none otherwise.
        let (arc, eng, _) = tuned()
        check(!eng.render().contains { $0.role == .handle }, "arc polish: no handles in play")
        arc.setFineTuning(true)
        let handles = eng.render().filter { $0.role == .handle }
        check(handles.count >= 14, "arc polish: handles on every movable control, got \(handles.count)")
        check(!arc.canUndo && eng.render().first { $0.label == "Undo" }?.fade ?? 1 < 1, "arc polish: Undo is dimmed with nothing to undo")

        // Snap to the default: a drag that comes back close to 0 settles on exactly 0, with a tick.
        let hand = arc.hands.first { $0.side == .right }!
        let a0 = arc.controls.first { $0.button == .a }!.shape.center
        func tweak() -> ArcTweak? { arc.profiles["landscape"]?.rightTweaks?["arc"] }
        let (r0, phi0) = hand.polar(a0)
        eng.began(1, at: a0, time: 1)
        eng.moved(1, to: hand.point(r: r0, phi: phi0 + 0.02), time: 1.1)
        check(abs(tweak()?.dphi ?? 0) < 1e-9 && !arc.takeSnapTick(), "arc polish: a control at its default stays put through a small drag, no tick")
        for i in 1...10 { eng.moved(1, to: hand.point(r: r0, phi: phi0 + 0.02 + 0.01 * CGFloat(i)), time: 1.2 + Double(i) * 0.02) }
        check(abs((tweak()?.dphi ?? 0) - 0.12) < 0.01, "arc polish: past the snap it follows the thumb, \(tweak()?.dphi ?? -1)")
        _ = arc.takeSnapTick()
        for i in 1...10 { eng.moved(1, to: hand.point(r: r0, phi: phi0 + 0.12 - 0.01 * CGFloat(i)), time: 2 + Double(i) * 0.02) }
        check((tweak()?.dphi ?? 1) == 0 && arc.takeSnapTick(), "arc polish: coming back near the default snaps to 0 with one tick, \(tweak()?.dphi ?? -1)")
        check(!arc.takeSnapTick(), "arc polish: the tick is delivered once")
        check(eng.render().contains { $0.role == .guide && $0.tone == .good }, "arc polish: the snap guide turns green when engaged")
        eng.ended(1, at: a0, time: 3)

        // Equal spacing on the outer ring: with ZR and plus moved, R settles midway between them.
        var prof = ArcProfile()
        prof.rightTweaks = ["s0": ArcTweak(dphi: 0.10, dr: 0), "sys": ArcTweak(dphi: 0.30, dr: 0.05)]
        let (arc2, eng2, _) = tuned(["landscape": prof])
        arc2.setFineTuning(true)
        let rBtn = arc2.controls.first { $0.button == .r }!.shape.center
        let hand2 = arc2.hands.first { $0.side == .right }!
        drag(eng2, hand2, from: rBtn, id: 2, t: 1, dphi: 0.17)
        check(abs((arc2.profiles["landscape"]?.rightTweaks?["s1"]?.dphi ?? 0) - 0.20) < 1e-9, "arc polish: R settles at equal spacing, \(arc2.profiles["landscape"]?.rightTweaks?["s1"]?.dphi ?? -1)")
        check(arc2.takeSnapTick(), "arc polish: and ticks")
        // Radial: lines up with the plus ring.
        let rBtn2 = arc2.controls.first { $0.button == .r }!.shape.center
        let short: CGFloat = 1032
        drag(eng2, arc2.hands.first { $0.side == .right }!, from: rBtn2, id: 3, t: 5, dphi: 0, dr: 0.05 * short - 0.05 * open.unit)
        check(abs((arc2.profiles["landscape"]?.rightTweaks?["s1"]?.dr ?? 0) - 0.05) < 1e-9, "arc polish: R lines up with the plus ring in and out")
        // Snapping off: the control goes exactly where the thumb does.
        var prof3 = prof
        prof3.rightTweaks = nil
        let (arc3, eng3, _) = tuned(["landscape": prof3])
        arc3.options.snapGuides = false
        arc3.setFineTuning(true)
        let a3 = arc3.controls.first { $0.button == .a }!.shape.center
        let hand3 = arc3.hands.first { $0.side == .right }!
        drag(eng3, hand3, from: a3, id: 4, t: 1, dphi: 0.02)
        check(abs((arc3.profiles["landscape"]?.rightTweaks?["arc"]?.dphi ?? 0) - 0.02) < 0.004 && !arc3.takeSnapTick(), "arc polish: snap guides off means no snapping")

        // Undo.
        let (u, ue, _) = tuned()
        u.setFineTuning(true)
        let start = u.controls.map(\.shape)
        let uh = u.hands.first { $0.side == .right }!
        drag(ue, uh, from: u.controls.first { $0.button == .a }!.shape.center, id: 5, t: 1, dphi: 0.3, dr: 20)
        let one = u.controls.map(\.shape)
        drag(ue, u.hands.first { $0.side == .right }!, from: u.controls.first { $0.button == .a }!.shape.center, id: 6, t: 3, dphi: -0.5)
        check(u.canUndo && u.controls.map(\.shape) != one, "arc polish: two drags, something to undo")
        check(u.undoLastChange() && u.controls.map(\.shape) == one, "arc polish: undo puts back the last drag only")
        check(u.undoLastChange() && u.controls.map(\.shape) == start && u.profiles["landscape"] == nil, "arc polish: undo again reaches the start")
        check(!u.undoLastChange() && !u.canUndo, "arc polish: nothing left to undo")
        // A touch that moves nothing is not a change.
        ue.began(7, at: u.controls.first { $0.button == .a }!.shape.center, time: 9)
        ue.ended(7, at: .zero, time: 9.1)
        check(!u.canUndo, "arc polish: a still touch leaves nothing to undo")
        // The Undo and Done pills take touches and work.
        drag(ue, u.hands.first { $0.side == .right }!, from: u.controls.first { $0.button == .a }!.shape.center, id: 8, t: 10, dphi: 0.3)
        let moved = u.controls.map(\.shape)
        let undoPill = element(ue, label: "Undo")!.shape.center
        check(ue.claims(undoPill) && u.canUndo, "arc polish: the Undo pill takes a touch")
        ue.began(9, at: undoPill, time: 12); ue.ended(9, at: undoPill, time: 12.05)
        check(u.controls.map(\.shape) == start && moved != start, "arc polish: tapping Undo undoes")
        let donePill = element(ue, label: "Done")!.shape.center
        ue.began(10, at: donePill, time: 13); ue.ended(10, at: donePill, time: 13.05)
        check(!u.isFineTuning && !ue.render().contains { $0.role == .handle }, "arc polish: Done leaves fine-tuning")
        // Reset is undoable; locked refuses undo.
        u.setFineTuning(true)
        drag(ue, u.hands.first { $0.side == .right }!, from: u.controls.first { $0.button == .a }!.shape.center, id: 11, t: 20, dphi: 0.3)
        let tunedShapes = u.controls.map(\.shape)
        u.resetToDefault()
        check(u.controls.map(\.shape) == start && u.undoLastChange() && u.controls.map(\.shape) == tunedShapes, "arc polish: reset can be undone")
        u.setLocked(true)
        check(!u.canUndo && !u.undoLastChange(), "arc polish: locked refuses undo")
        // Stacks are per orientation.
        u.setLocked(false)
        u.layout(LayoutContext(size: CGSize(width: 1032, height: 1376), safeInsets: Insets(top: 24, bottom: 20)))
        check(!u.canUndo, "arc polish: undo is per orientation")
    }

    // MARK: Lock indicator

    do {
        for (device, display) in [("iPad mini", TargetDevice.Display.stacked), ("iPhone SE", .single)] {
            let d = TargetDevice.all.first { $0.name == device }!
            let ctx = d.context(display)
            var now = 100.0
            let arc = ArcPad()
            arc.clock = { now }
            let eng = PadEngine(scheme: arc, output: Recorder(), context: ctx)
            let u = ctx.unit
            check(arc.statusText == "Unlocked" && element(eng, label: "Locked") == nil, "arc polish \(device): no badge while unlocked")
            let l = CGPoint(x: 10, y: ctx.size.height + 40), r = CGPoint(x: ctx.size.width - 10, y: ctx.size.height + 40)
            arc.startCalibration()
            play(eng, id: 1, arcPoints(l, .left, 6.2 * u, from: 0.3, to: 1.25, steps: 100, jitter: 4), t0: 1)
            play(eng, id: 2, arcPoints(r, .right, 6.2 * u, from: 0.3, to: 1.25, steps: 100, jitter: 4), t0: 5)
            arc.acceptCalibration()
            check(arc.statusText == "Locked" && element(eng, label: "Locked") != nil, "arc polish \(device): Locked shows right after locking")
            check(arc.needsTicks, "arc polish \(device): the chip asks for ticks so it can fade")
            now += 10
            let persistent = element(eng, label: "Locked") != nil
            check(persistent == (display == .stacked), "arc polish \(device): the badge stays on a clear screen and goes quiet over video, got \(persistent)")
            arc.options.lockBadge = false
            check(element(eng, label: "Locked") == nil, "arc polish \(device): the badge can be turned off")
            arc.setLocked(false)
            check(element(eng, label: "Locked") == nil, "arc polish \(device): unlocking removes it")
            arc.setLocked(true)
            check(element(eng, label: "Locked") != nil, "arc polish \(device): locking shows it again for a moment")
        }
    }

    // MARK: Quiet over video, idle fade

    do {
        let se = TargetDevice.all.first { $0.name == "iPhone SE" }!
        let ctx = se.context(.single)
        let arc = ArcPad()
        let eng = PadEngine(scheme: arc, output: Recorder(), context: ctx)
        func controlsOnly() -> [RenderElement] { eng.render().filter { $0.role != .guide && $0.role != .touchscreen } }
        check(arc.avoidance == .none, "arc polish: iPhone SE single draws over the video")
        check(controlsOnly().allSatisfy { $0.fade < 0.7 }, "arc polish: over the video everything rests dim")
        check(eng.render().filter { $0.role == .guide }.allSatisfy { $0.width <= 2 }, "arc polish: over the video the arc band is thin")
        let wide = ArcPad()
        let weng = PadEngine(scheme: wide, output: Recorder(), context: TargetDevice.all.first { $0.name == "iPad mini" }!.context(.stacked))
        check(weng.render().contains { $0.role == .guide && $0.width > 10 } && weng.render().filter { $0.role != .guide }.allSatisfy { $0.fade == 1 }, "arc polish: on a clear screen the arc keeps its full band and strength")
        let b = arc.controls.first { $0.button == .b }!.shape.center
        eng.began(1, at: b, time: 1)
        check(arc.needsTicks, "arc polish: a thumb on the arc brightens it, so ticks run")
        for i in 1...40 { eng.tick(time: 1 + Double(i) / 30) }
        let held = controlsOnly()
        check(held.filter { $0.shape.center.x > ctx.size.width / 2 }.allSatisfy { $0.fade > 0.99 }, "arc polish: the hand under the thumb is at full strength")
        check(held.filter { $0.shape.center.x < ctx.size.width / 2 }.allSatisfy { $0.fade < 0.7 }, "arc polish: the other hand stays dim")
        check(!arc.needsTicks, "arc polish: settled, no ticks")
        eng.ended(1, at: b, time: 3)
        check(arc.needsTicks, "arc polish: letting go starts the fade back")
        for i in 1...60 { eng.tick(time: 3 + Double(i) / 30) }
        check(controlsOnly().allSatisfy { $0.fade < 0.7 } && !arc.needsTicks, "arc polish: and it settles dim again")
        arc.options.quietOverVideo = false
        check(eng.render().filter { $0.role != .guide }.allSatisfy { $0.fade == 1 }, "arc polish: quiet mode can be turned off")

        // Idle fade: off by default, on request.
        let mini = TargetDevice.all.first { $0.name == "iPad mini" }!.context(.stacked)
        let idle = ArcPad()
        let ieng = PadEngine(scheme: idle, output: Recorder(), context: mini)
        check(!idle.needsTicks, "arc polish: nothing ticks by default")
        idle.options.idleFadeSeconds = 2
        check(idle.needsTicks, "arc polish: idle fade on asks for ticks")
        for i in 0...180 { ieng.tick(time: 100 + Double(i) / 30) }
        check(ieng.render().filter { $0.role != .touchscreen }.allSatisfy { $0.fade < 0.2 } && !idle.needsTicks, "arc polish: after 2 s idle the pad fades right back")
        let any = idle.controls.first { $0.button == .a }!.shape.center
        ieng.began(1, at: any, time: 107)
        check(idle.needsTicks, "arc polish: a touch brings it back")
        for i in 1...10 { ieng.tick(time: 107 + Double(i) / 30) }
        check(ieng.render().filter { $0.role != .touchscreen && $0.role != .guide }.allSatisfy { $0.fade > 0.95 }, "arc polish: straight back under a thumb")
        check(Recorder().held.isEmpty, "arc polish: recorder sanity")
        ieng.ended(1, at: any, time: 108)
        idle.options.idleFadeSeconds = nil
        check(ieng.render().filter { $0.role != .touchscreen && $0.role != .guide }.allSatisfy { $0.fade == 1 }, "arc polish: turning it off restores the pad")
    }

    // MARK: Swapped hands

    do {
        for d in arcDevices() {
            for display in TargetDevice.Display.allCases {
                let ctx = d.context(display)
                let arc = ArcPad()
                let out = Recorder()
                let eng = PadEngine(scheme: arc, output: out, context: ctx)
                arc.layout(ctx)
                let plain = arc.controls.map(\.shape)
                arc.options.swapHands = true
                let name = "arc swapped / \(d.name) / \(display.rawValue)"
                check(!arc.usingFallback, "\(name): fell back")
                check(LayoutCheck.problems(arc.controls, in: ctx.safeBounds).isEmpty, "\(name): overlaps")
                func pos(_ b: PadButton) -> CGPoint { arc.controls.first { $0.button == b }!.shape.center }
                let half = ctx.size.width / 2
                if !arc.usingFallback {
                    if ctx.size.width > ctx.size.height {
                    check([PadButton.a, .b, .x, .y].allSatisfy { pos($0).x < half }, "\(name): face side is on the left")
                    check([PadButton.up, .down, .left, .right].allSatisfy { pos($0).x > half }, "\(name): d-pad side is on the right")
                    }
                    check(pos(.a).y < pos(.b).y && pos(.b).y < pos(.x).y && pos(.x).y < pos(.y).y, "\(name): A, B, X, Y still read from the top")
                    check(pos(.up).y < pos(.down).y && pos(.down).y < pos(.left).y && pos(.left).y < pos(.right).y, "\(name): d-pad still reads from the top")
                    for b in [PadButton.a, .y, .up, .right] {
                        eng.began(1, at: pos(b), time: 1)
                        check(out.held == [b], "\(name): pressing \(b) gives \(out.held.map(\.description))")
                        eng.ended(1, at: pos(b), time: 1.1)
                    }
                    check(arc.hands.filter(\.faces).allSatisfy { $0.side == .left } && arc.hands.filter { !$0.faces }.allSatisfy { $0.side == .right }, "\(name): hands carry the swapped controls")
                }
                arc.options.swapHands = false
                check(arc.controls.map(\.shape) == plain, "\(name): swapping back restores the layout exactly")
            }
        }
        // Each thumb keeps its own calibration; fine-tune lands under the thumb that moved it.
        let arc = ArcPad()
        let eng = PadEngine(scheme: arc, output: Recorder(), context: open)
        arc.options.swapHands = true
        arc.setFineTuning(true)
        let hand = arc.hands.first { $0.side == .left }!
        let a = arc.controls.first { $0.button == .a }!.shape.center
        let (r0, phi0) = hand.polar(a)
        eng.began(1, at: a, time: 1)
        for i in 1...10 { eng.moved(1, to: hand.point(r: r0, phi: phi0 + 0.03 * CGFloat(i)), time: 1 + Double(i) * 0.02) }
        eng.ended(1, at: a, time: 2)
        check(arc.profiles["landscape"]?.leftTweaks?["arc"] != nil && arc.profiles["landscape"]?.rightTweaks == nil, "arc swapped: A's fine-tune is saved under the left thumb")
        check(!ArcPad.encode(arc.profiles).contains("swap"), "arc swapped: the saved calibration holds no option")
    }

    // MARK: Saved data

    do {
        // A profile written before any of this existed loads and plays as it did.
        let old = "{\"landscape\":{\"left\":{\"pivotX\":0.0,\"pivotY\":1.1,\"radius\":0.3,\"spread\":0.01,\"rest\":0.7,\"lo\":0.3,\"hi\":1.2},\"locked\":true,\"rightTweaks\":{\"arc\":{\"dphi\":0.1,\"dr\":0.01}}}}"
        let profiles = ArcPad.decode(old)
        check(profiles["landscape"]?.locked == true && profiles["landscape"]?.left != nil, "arc polish: an old saved profile still loads")
        let arc = ArcPad(profiles: profiles)
        arc.layout(open)
        check(!arc.usingFallback && arc.isLocked && LayoutCheck.problems(arc.controls, in: open.safeBounds).isEmpty, "arc polish: and lays out locked")
        check(arc.options == ArcOptions() && !arc.options.swapHands && arc.options.idleFadeSeconds == nil, "arc polish: every new option defaults to today's behaviour")

        let opts = ArcOptions(swapHands: true, idleFadeSeconds: 8, quietOverVideo: false, snapGuides: false, lockBadge: false)
        check(ArcOptions.decode(ArcOptions.encode(opts)) == opts, "arc polish: options round-trip")
        check(ArcOptions.decode("garbage") == ArcOptions() && ArcOptions.decode("{}") == ArcOptions(), "arc polish: bad or empty options are the defaults")
        check(ArcOptions.decode("{\"swapHands\":true}").swapHands && ArcOptions.decode("{\"swapHands\":true}").quietOverVideo, "arc polish: missing option keys keep their defaults")
        check(ArcOptions(idleFadeSeconds: 0.2).validIdleFade == 1 && ArcOptions(idleFadeSeconds: 9999).validIdleFade == 600, "arc polish: idle seconds are clamped")
        var saved: ArcOptions?
        let watcher = ArcPad()
        watcher.onOptions = { saved = $0 }
        watcher.options.swapHands = true
        check(saved?.swapHands == true, "arc polish: a changed option is reported for saving")
    }
}
