import CoreGraphics
import Foundation
import TouchLabCore

// Zone: the polish fixes, and per-button / per-group editing.

private final class ZoneRecorder: PadOutput {
    var held: Set<PadButton> = []
    func setButton(_ button: PadButton, pressed: Bool) { if pressed { held.insert(button) } else { held.remove(button) } }
    func setStick(_ stick: PadStick, _ value: StickValue) {}
    func setTouchscreen(_ point: CGPoint?) {}
    func releaseAll() { held = [] }
}

func runZoneChecks() {
    // Both centre dots are named, L3 on the d-pad as R3 is on the diamond; the flat look names neither
    // on the d-pad, as it always drew it. HOME keeps half a button clear of the bottom edge in the polished
    // look (it sat 0.21 of a button off it, 7 pt on a phone with no home indicator).
    for d in TargetDevice.all {
        let ctx = d.context(.single)
        var flat = ctx; flat.showcaseStyle = false
        for (c, polished) in [(ctx, true), (flat, false)] {
            let pad = ZonePad()
            let e = PadEngine(scheme: pad, output: ZoneRecorder(), context: c)
            let dots = e.render().filter { $0.role == .dot }
            check(dots.contains { $0.label == "L3" } == polished, "zone \(d.name): the d-pad's centre dot is \(polished ? "" : "not ")named L3")
            check(dots.contains { $0.label == "R3" }, "zone \(d.name): the diamond's centre dot is named R3")
            guard let home = pad.controls.first(where: { $0.button == .home }),
                  let face = pad.controls.first(where: { $0.button == .a }) else { continue }
            let clearance = (c.safeBounds.maxY - home.shape.boundingBox.maxY) / face.shape.boundingBox.width
            check(polished ? clearance >= 0.499 : abs(clearance - 0.2135) < 0.01, "zone \(d.name): HOME is \(clearance) of a button from the bottom edge")
        }
    }

    // A stick is drawn at the size it is caught at, on every device: the ring is the catchment
    // circle, and the knob fills the same share of it whatever size the arrangement settled on.
    for d in TargetDevice.all {
        for display in TargetDevice.Display.allCases {
            let ctx = d.context(display)
            let pad = ZonePad()
            let e = PadEngine(scheme: pad, output: ZoneRecorder(), context: ctx)
            let rings = e.render().filter { $0.role == .stickBase }
            let knobs = e.render().filter { $0.role == .stickKnob }
            let sticks = pad.controls.filter { if case .stick = $0.kind { return true } else { return false } }
            check(rings.count == 2 && knobs.count == 2 && sticks.count == 2, "zone \(d.name) \(display): both sticks are drawn")
            guard rings.count == 2, knobs.count == 2, sticks.count == 2 else { continue }
            for (ring, stick) in zip(rings, sticks) {
                check(abs(ring.shape.boundingBox.width - stick.shape.boundingBox.width) < 0.01,
                      "zone \(d.name) \(display): a stick's ring (\(ring.shape.boundingBox.width)) is drawn at its catchment (\(stick.shape.boundingBox.width))")
            }
            for (knob, stick) in zip(knobs, sticks) {
                let want = PadParts.knobDiameter / PadParts.stickBaseDiameter * stick.shape.boundingBox.width
                check(abs(knob.shape.boundingBox.width - want) < 0.01, "zone \(d.name) \(display): a knob keeps its share of the ring")
            }
        }
    }

    runZoneEditChecks()
}

private func tap(_ e: PadEngine, _ out: ZoneRecorder, at p: CGPoint) -> Set<PadButton> {
    out.releaseAll()
    e.began(900, at: p, time: 1)
    let held = out.held
    e.ended(900, at: p, time: 1.05)
    return held
}

private func problems(_ pad: ControlScheme, _ ctx: LayoutContext) -> [String] {
    LayoutCheck.problems(pad.controls.map(PadEditor.drawn), in: ctx.safeBounds)
}

private func runZoneEditChecks() {
    // The stored form survives a round trip, drops what is unusable, and nothing means no edits.
    var sample = PadEdits()
    sample["c.a"] = PadEdit(dx: 0.5, dy: -0.25, scale: 1.2)
    sample["g.face"] = PadEdit(dx: -1, dy: 0, scale: 0.9)
    check(PadEdits(encoded: sample.encoded) == sample, "zone edits: the stored form reads back as written")
    check(PadEdits().encoded.isEmpty && PadEdits(encoded: "").isEmpty && PadEdits(encoded: "nonsense").isEmpty,
          "zone edits: nothing, an empty string and garbage are all no edits")
    check(PadEdits(encoded: "{\"c.a\":[1e999,0,1]}").isEmpty, "zone edits: a non-finite value is dropped")
    var wild = PadEdits(); wild["c.a"] = PadEdit(dx: 999, dy: -999, scale: 50)
    check(wild["c.a"] == PadEdit(dx: 40, dy: -40, scale: 1.6), "zone edits: a stored edit is held to the allowed range")
    var none = PadEdits(); none["c.a"] = .identity
    check(none.isEmpty, "zone edits: an unchanged edit is not stored")

    var movedAll = 0, resolvedAll = 0
    for d in TargetDevice.all {
        for display in TargetDevice.Display.allCases {
            let ctx = d.context(display)
            let label = "zone \(d.name) \(display)"

            // With no edits the pad is the arrangement itself, control for control.
            let plain = ZonePad()
            plain.layout(ctx)
            let built = GamePadArrangement.build(ctx)
            check(plain.controls.count == built.count && zip(plain.controls, built).allSatisfy { $0.shape == $1.shape && $0.reach == $1.reach },
                  "\(label): with no edits the layout is the arrangement exactly")

            let probeOut = ZoneRecorder()
            let pad = ZonePad()
            var withEdits = ctx
            withEdits.edits = PadEdits()
            let engine = PadEngine(scheme: pad, output: probeOut, context: withEdits)
            let u = pad.editUnit
            let a0 = pad.controls.first { $0.button == .a }!
            let home = a0.shape

            // An edit that fits is applied as asked, and the catchment goes with the control.
            var edits = PadEdits()
            edits["c.a"] = PadEdit(dx: 0.25, dy: -0.2, scale: 1.1)
            let asked = pad.resolveEdit(edits["c.a"], for: "c.a", start: .identity)
            check(abs(asked.dx - 0.25) < 0.01 && abs(asked.dy + 0.2) < 0.01 && abs(asked.scale - 1.1) < 0.01,
                  "\(label): a small move and resize of A is allowed as asked (got \(asked))")
            var next = withEdits; next.edits = edits
            engine.setContext(next)
            let a1 = pad.controls.first { $0.button == .a }!
            check(abs(a1.shape.center.x - (home.center.x + 0.25 * u)) < 0.01 && abs(a1.shape.center.y - (home.center.y - 0.2 * u)) < 0.01,
                  "\(label): A moved by the edit")
            check(abs(a1.shape.boundingBox.width - home.boundingBox.width * 1.1) < 0.01, "\(label): A resized by the edit")
            check(tap(engine, probeOut, at: a1.shape.center) == [.a], "\(label): A is pressed where it now is")
            check(problems(pad, next).isEmpty, "\(label): an edited layout still has no overlaps or controls outside the safe area")
            let y0 = pad.controls.first { $0.button == .y }!
            check(abs(y0.shape.center.x - built.first { $0.button == .y }!.shape.center.x) < 0.01, "\(label): Y is where it was")

            // Resetting puts the layout back exactly.
            engine.setContext(withEdits)
            check(zip(pad.controls, built).allSatisfy { $0.shape == $1.shape }, "\(label): reset returns the original layout")

            // A request that would collide, leave the screen or land on a screen it began clear of
            // comes back cut down to one that doesn't.
            for key in ["c.a", "c.dpad", "c.stick.left", "c.stick.right", "c.zl", "c.r", "c.home", "c.plus", "g.face",
                        "g.shoulders.left", "g.shoulders.right", "g.system"] {
                for request in [PadEdit(dx: 30, dy: 30, scale: 1.6), PadEdit(dx: -30, dy: -30, scale: 0.7),
                                PadEdit(dx: 3, dy: 0, scale: 1), PadEdit(dx: 0, dy: -3, scale: 1.3), PadEdit(dx: -2, dy: 2, scale: 1.5)] {
                    let got = pad.resolveEdit(request, for: key, start: .identity)
                    var e = PadEdits(); e[key] = got
                    var c2 = withEdits; c2.edits = e
                    let p2 = ZonePad(); p2.layout(c2)
                    resolvedAll += 1
                    let bad = problems(p2, c2)
                    check(bad.isEmpty, "\(label): \(key) resolved from \(request) to \(got) is valid but has \(bad)")
                    // The resolved edit is itself applied exactly (nothing further cut back).
                    let q = ZonePad(); q.layout(c2)
                    let h = ZonePad(); h.layout(withEdits)
                    // Nothing was moved onto the GamePad screen or the picture it began clear of.
                    let screens = ([ctx.touchscreenRect].compactMap { $0 }) + ctx.videoRects
                    for (now, was) in zip(q.controls, h.controls) {
                        for r in screens where !r.intersects(was.shape.boundingBox) {
                            check(!r.intersects(now.shape.boundingBox), "\(label): \(key) edit \(got) moved \(now.label) onto a screen it was clear of")
                        }
                    }
                    let moved = zip(q.controls, h.controls).filter { $0.shape != $1.shape }.count
                    check(moved > 0 || got.isIdentity, "\(label): \(key) resolved to \(got) but nothing moved")
                    movedAll += moved
                }
            }

            // Edits stored on another screen that do not fit here are eased back, not applied, so the
            // layout is still valid. (The extreme ones: far past any screen.)
            var extreme = PadEdits()
            for key in ["c.a", "c.dpad", "c.stick.left", "c.zl", "g.shoulders.right", "g.system"] { extreme[key] = PadEdit(dx: 12, dy: -9, scale: 1.6) }
            var c3 = withEdits; c3.edits = extreme
            let p3 = ZonePad(); p3.layout(c3)
            check(problems(p3, c3).isEmpty, "\(label): edits that do not fit this screen leave a valid layout")
        }
    }
    check(movedAll > 0 && resolvedAll > 0, "zone edits: the resolve checks ran (\(resolvedAll) cases)")

    // A group moves and resizes all of its members together; a control inside it still has its own edit.
    do {
        let d = TargetDevice.all.first { $0.name == "iPad Pro 11 (A12Z)" }!
        let ctx = d.context(.single)
        let base = ZonePad(); base.layout(ctx)
        let u = base.editUnit
        var e = PadEdits()
        e[GamePadEditing.Key.face] = PadEdit(dx: -0.5, dy: -0.25, scale: 1)
        var c = ctx; c.edits = e
        let pad = ZonePad(); pad.layout(c)
        for b in [PadButton.a, .b, .x, .y] {
            let was = base.controls.first { $0.button == b }!.shape.center
            let now = pad.controls.first { $0.button == b }!.shape.center
            check(abs(now.x - (was.x - 0.5 * u)) < 0.01 && abs(now.y - (was.y - 0.25 * u)) < 0.01, "zone edits: the face group moves \(b) with it")
        }
        let r3Was = base.controls.first { $0.role == .dot && $0.button == .stickR }!.shape.center
        let r3Now = pad.controls.first { $0.role == .dot && $0.button == .stickR }!.shape.center
        check(abs(r3Now.x - (r3Was.x - 0.5 * u)) < 0.01, "zone edits: the R3 dot goes with the face group")
        check(pad.controls.first { $0.button == .home }!.shape == base.controls.first { $0.button == .home }!.shape, "zone edits: HOME stays put")
        // Growing the group grows the spread and the buttons, about the diamond's centre.
        e[GamePadEditing.Key.face] = PadEdit(dx: 0, dy: 0, scale: 1.2)
        c.edits = e
        let big = ZonePad(); big.layout(c)
        let a0 = base.controls.first { $0.button == .a }!.shape, a1 = big.controls.first { $0.button == .a }!.shape
        let centre = base.controls.first { $0.role == .dot && $0.button == .stickR }!.shape.center
        check(abs((a1.center.x - centre.x) - 1.2 * (a0.center.x - centre.x)) < 0.01 && abs(a1.boundingBox.width - 1.2 * a0.boundingBox.width) < 0.01,
              "zone edits: a face group edit scales the buttons and their spread about the diamond's centre")
        // Control edit on top of the group edit.
        e["c.a"] = PadEdit(dx: 0.1, dy: 0, scale: 1)
        c.edits = e
        let both = ZonePad(); both.layout(c)
        let a2 = both.controls.first { $0.button == .a }!.shape
        check(abs(a2.center.x - (a1.center.x + 0.1 * u)) < 0.01, "zone edits: a control edit stacks on its group's")
        // The stick edit scales the knob with the ring.
        var s = PadEdits(); s["c.stick.left"] = PadEdit(dx: 0, dy: 0, scale: 1.2)
        var cs = ctx; cs.edits = s
        let sp = PadEngine(scheme: ZonePad(), output: ZoneRecorder(), context: cs)
        let ring = sp.render().first { $0.role == .stickBase }!, knob = sp.render().first { $0.role == .stickKnob }!
        let plainEngine = PadEngine(scheme: ZonePad(), output: ZoneRecorder(), context: ctx)
        let ring0 = plainEngine.render().first { $0.role == .stickBase }!, knob0 = plainEngine.render().first { $0.role == .stickKnob }!
        check(abs(ring.shape.boundingBox.width - 1.2 * ring0.shape.boundingBox.width) < 0.01 &&
              abs(knob.shape.boundingBox.width - 1.2 * knob0.shape.boundingBox.width) < 0.01, "zone edits: a stick's ring and knob grow together")
    }

    // Picking: a tap selects the control under it, or its whole cluster, whichever granularity is set.
    do {
        let d = TargetDevice.all.first { $0.name == "iPad Pro 11 (A12Z)" }!
        let pad = ZonePad(); pad.layout(d.context(.single))
        func at(_ b: PadButton) -> CGPoint { pad.controls.first { $0.button == b && $0.role != .dot }!.shape.center }
        pad.editGranularity = .control
        check(pad.editTarget(at: at(.a)) == "c.a" && pad.editTarget(at: at(.zl)) == "c.zl" && pad.editTarget(at: at(.home)) == "c.home",
              "zone edits: control mode selects the control tapped")
        let dpadCentre = pad.controls.first { if case .dpad = $0.kind { return true } else { return false } }!.shape.center
        check(pad.editTarget(at: dpadCentre) == GamePadEditing.Key.dpad, "zone edits: the d-pad selects itself, dot and all")
        pad.editGranularity = .group
        check(pad.editTarget(at: at(.a)) == GamePadEditing.Key.face && pad.editTarget(at: at(.l)) == GamePadEditing.Key.leftShoulders &&
              pad.editTarget(at: at(.zr)) == GamePadEditing.Key.rightShoulders && pad.editTarget(at: at(.plus)) == GamePadEditing.Key.system,
              "zone edits: group mode selects the cluster tapped")
        check(pad.editOutlines().count == 7, "zone edits: group mode offers the d-pad, face buttons, two sticks, two shoulder pairs and the system buttons")
        pad.editGranularity = .control
        check(pad.editOutlines().count == 14, "zone edits: control mode offers all fourteen controls")
    }
}
