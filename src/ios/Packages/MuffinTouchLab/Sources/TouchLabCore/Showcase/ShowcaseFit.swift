import CoreGraphics
import Foundation

/// Fit's second chance. The showcase pad's own resolver moves rigid clusters; when that cannot
/// clear the picture this packs the GamePad's blocks (d-pad, face diamond, sticks, shoulder
/// pairs, the + / - and HOME stack) into whatever space the picture leaves, as close to the
/// hardware arrangement as the space allows:
///
/// - each side may be a different size (a cluster shrinks on its own, never under `floor`),
/// - a cluster pins to its corner and its sticks and shoulders go to the nearest free spot
///   from where the hardware puts them,
/// - the shoulder pair stacks, or moves under or beside its stick, when width is tight,
/// - the face diamond flattens (to as little as 2.2 buttons tall) when height is tight,
/// - edge and picture margins loosen from comfortable to snug before a size is given up.
///
/// It returns nil when even that cannot clear the picture; the caller then floats the pad over
/// the picture instead.
enum ShowcaseFitSolver {

    struct Result {
        var placements: [String: ShowcaseLayout.Placement]
        var leftUnit: CGFloat
        var rightUnit: CGFloat
    }

    private struct Margins { var edge: CGFloat, clear: CGFloat, gap: CGFloat }   // in D
    private static let faceHalfHeights: [CGFloat] = [ShowcaseHardware.faceHalfY, 0.8, 0.68, 0.62]
    private static let tiers = [Margins(edge: 0.30, clear: 0.25, gap: 0.15), Margins(edge: 0.12, clear: 0.10, gap: 0.08),
                                Margins(edge: 0.04, clear: 0.04, gap: 0.05)]
    /// How much bigger one side may end up than the other.
    private static let maxAsymmetry: CGFloat = 1.15

    static func solve(safe: CGRect, avoid: [CGRect], wanted: CGFloat, floor: CGFloat) -> Result? {
        guard wanted > 0, floor > 0 else { return nil }
        let start = max(wanted, floor)
        for m in tiers {
            var u = start
            while true {
                // A flatter face diamond is preferred to smaller buttons.
                for fy in faceHalfHeights {
                    if let r = attempt(uL: u, uR: u, safe: safe, avoid: avoid, margins: m, faceHalfY: fy) {
                        return grow(r, from: u, wanted: wanted, safe: safe, avoid: avoid, margins: m, faceHalfY: fy)
                    }
                }
                if u <= floor + 0.01 { break }
                u = max(floor, u * 0.97)
            }
        }
        return nil
    }

    /// With the common size settled, let each side try to be a little bigger on its own.
    private static func grow(_ base: Result, from u: CGFloat, wanted: CGFloat, safe: CGRect, avoid: [CGRect],
                             margins m: Margins, faceHalfY fy: CGFloat) -> Result {
        var best = base, uL = u, uR = u
        let cap = min(wanted, u * maxAsymmetry)
        for left in [true, false] {
            var x = u
            while x * 1.03 <= cap + 0.001 {
                x *= 1.03
                guard let r = attempt(uL: left ? x : uL, uR: left ? uR : x, safe: safe, avoid: avoid, margins: m, faceHalfY: fy) else { break }
                best = r
                if left { uL = x } else { uR = x }
            }
        }
        return best
    }

    // MARK: - Packing

    private struct Packer {
        let safe: CGRect
        let avoid: [CGRect]
        let edge: CGFloat, clear: CGFloat, gap: CGFloat
        var placed: [CGRect] = []

        func fits(_ r: CGRect) -> Bool {
            let s = safe.insetBy(dx: edge, dy: edge)
            guard r.minX >= s.minX - 0.01, r.maxX <= s.maxX + 0.01, r.minY >= s.minY - 0.01, r.maxY <= s.maxY + 0.01 else { return false }
            let core = r.insetBy(dx: 0.01, dy: 0.01)
            for v in avoid where v.insetBy(dx: -clear, dy: -clear).intersects(core) { return false }
            for p in placed where p.insetBy(dx: -gap, dy: -gap).intersects(core) { return false }
            return true
        }

        /// Best-scoring free spot for a `w` x `h` block, or nil. `seeds` are extra origins to try.
        mutating func place(w: CGFloat, h: CGFloat, seeds: [CGPoint] = [], cost: (CGRect) -> CGFloat) -> CGRect? {
            var xs = [safe.minX + edge, safe.maxX - edge - w] + seeds.map(\.x)
            var ys = [safe.minY + edge, safe.maxY - edge - h] + seeds.map(\.y)
            for v in avoid {
                xs += [v.minX - clear - w, v.maxX + clear]
                ys += [v.minY - clear - h, v.maxY + clear]
            }
            for p in placed {
                xs += [p.maxX + gap, p.minX - gap - w, p.minX, p.maxX - w]
                ys += [p.maxY + gap, p.minY - gap - h, p.minY, p.maxY - h]
            }
            var best: (CGRect, CGFloat)?
            for x in xs {
                for y in ys {
                    let r = CGRect(x: x, y: y, width: w, height: h)
                    guard fits(r) else { continue }
                    let c = cost(r)
                    if best == nil || c < best!.1 - 1e-6 { best = (r, c) }
                }
            }
            guard let (r, _) = best else { return nil }
            placed.append(r)
            return r
        }

        mutating func place(centre: CGPoint, w: CGFloat, h: CGFloat, ideal: CGPoint, penalty: CGFloat = 0) -> CGRect? {
            place(w: w, h: h, seeds: [CGPoint(x: ideal.x - w / 2, y: ideal.y - h / 2)]) { r in
                r.center.distance(to: ideal) + penalty
            }
        }
    }

    // MARK: - One attempt at a pair of sizes

    private static func attempt(uL: CGFloat, uR: CGFloat, safe: CGRect, avoid: [CGRect], margins m: Margins,
                                faceHalfY fy: CGFloat) -> Result? {
        let G = ShowcaseHardware.self
        let um = min(uL, uR)
        let edge = m.edge * um
        var pk = Packer(safe: safe, avoid: avoid, edge: m.edge * um, clear: m.clear * um, gap: m.gap * um)
        var out: [String: ShowcaseLayout.Placement] = [:]
        let armX = G.stickArm * cos(G.stickArmAngle), armY = G.stickArm * sin(G.stickArmAngle)

        func circle(_ id: String, _ c: CGPoint, _ d: CGFloat) { out[id] = .circle(centre: c, diameter: d) }
        func pill(_ id: String, _ c: CGPoint, _ u: CGFloat) {
            out[id] = .pill(centre: c, size: CGSize(width: G.shoulderSize.width * u, height: G.shoulderSize.height * u),
                            corner: G.shoulderCorner * u)
        }

        // The system stack's size, which the face diamond reserves room for beneath itself.
        let rowH = G.systemDiameter * uR, homeD = G.homeDiameter * uR
        let stackW = (2 * G.systemDiameter + 0.25) * uR
        let stackH = rowH + 0.2 * uR + homeD
        let reserve = 0.45 * uR + stackH

        // 1. The face diamond, bottom right. Flatter when the height is short.
        var faceC: CGPoint?, faceH: CGFloat = 0
        outer: for reserveBelow in [reserve, 0] {
            do {
                let w = (2 * G.faceHalfX + 1) * uR, h = (2 * fy + 1) * uR
                // Hug the bottom edge, and sit far enough in for the stick to fit outboard of the diamond.
                let inset = max(0, armX + G.stickBase / 2 - (G.faceHalfX + 0.5)) * uR
                let corner: (CGRect) -> CGFloat = {
                    abs(safe.maxX - edge - inset - $0.maxX) + abs(safe.maxY - edge - $0.maxY)
                }
                let seed = CGPoint(x: safe.maxX - edge - inset - w, y: safe.maxY - edge - h - reserveBelow)
                if let r = pk.place(w: w, h: h + reserveBelow, seeds: [seed], cost: corner) {
                    // Keep only the diamond itself; the reserve is for the stack below it.
                    pk.placed.removeLast()
                    let face = CGRect(x: r.minX, y: r.minY, width: w, height: h)
                    pk.placed.append(face)
                    faceC = face.center
                    faceH = h
                    for (id, dx, dy) in [("X", CGFloat(0), -fy), ("Y", -G.faceHalfX, 0), ("A", G.faceHalfX, 0), ("B", 0, fy)] {
                        circle(id, CGPoint(x: face.midX + dx * uR, y: face.midY + dy * uR), G.faceDiameter * uR)
                    }
                    circle("R3", face.center, 0.706 * uR)
                    break outer
                }
            }
        }
        guard let fc = faceC else { return nil }

        // 2. The d-pad, bottom left, level with the diamond where it can be.
        let dw = G.dpadWidth * uL, dh = G.dpadHeight * uL
        let dInset = max(0, armX + G.stickBase / 2 - G.dpadWidth / 2) * uL
        let dSeed = CGPoint(x: safe.minX + edge + dInset, y: fc.y - dh / 2)
        guard let dr = pk.place(w: dw, h: dh, seeds: [dSeed], cost: { r in
            abs(r.minX - (safe.minX + edge + dInset)) + 1.5 * abs(r.midY - fc.y)
        }) else { return nil }
        out["dpad"] = .cross(centre: dr.center, size: CGSize(width: dw, height: dh), arm: G.dpadArm * uL)
        circle("L3", dr.center, 0.706 * uL)

        // 3. The + / - pair over HOME, under the diamond.
        let sys = CGPoint(x: fc.x - 0.55 * uR, y: fc.y + faceH / 2 + 0.45 * uR + stackH / 2)
        func placeSystem() -> Bool {
            if let r = pk.place(centre: sys, w: stackW, h: stackH, ideal: sys) {
                let rowY = r.minY + rowH / 2
                circle("plus", CGPoint(x: r.midX - (G.systemDiameter / 2 + 0.125) * uR, y: rowY), G.systemDiameter * uR)
                circle("minus", CGPoint(x: r.midX + (G.systemDiameter / 2 + 0.125) * uR, y: rowY), G.systemDiameter * uR)
                circle("HOME", CGPoint(x: r.midX, y: r.maxY - homeD / 2), homeD)
                return true
            }
            // No room for the stack: the row and HOME find their own spots.
            guard let row = pk.place(centre: sys, w: stackW, h: rowH, ideal: sys) else { return false }
            circle("plus", CGPoint(x: row.midX - (G.systemDiameter / 2 + 0.125) * uR, y: row.midY), G.systemDiameter * uR)
            circle("minus", CGPoint(x: row.midX + (G.systemDiameter / 2 + 0.125) * uR, y: row.midY), G.systemDiameter * uR)
            guard let home = pk.place(centre: sys, w: homeD, h: homeD, ideal: CGPoint(x: row.midX, y: row.maxY + 0.2 * uR + homeD / 2))
            else { return false }
            circle("HOME", home.center, homeD)
            return true
        }
        guard placeSystem() else { return nil }

        // 4. The sticks, as near the hardware's arm from their cluster as there is room for.
        var stickC: [PadStick: CGPoint] = [:]
        for (stick, from, u, sign) in [(PadStick.right, fc, uR, CGFloat(1)), (.left, dr.center, uL, -1)] {
            let side = G.stickBase * u
            let ideal = CGPoint(x: from.x + sign * armX * u, y: from.y - armY * u)
            // Close to where the hardware has it, or not at all (the caller tries something flatter).
            guard let r = pk.place(centre: ideal, w: side, h: side, ideal: ideal), r.center.distance(to: ideal) <= 7 * u else { return nil }
            stickC[stick] = r.center
            let suffix = stick == .left ? "L" : "R"
            circle("stick\(suffix)", r.center, side)
            circle("knob\(suffix)", r.center, G.stickKnob * u)
        }

        // 5. The shoulders: a pair over its stick, else stacked over it, else a column beside
        // it, else under or beside it as a pair, else one at a time.
        for (suffix, stick, u, sign) in [("L", PadStick.left, uL, CGFloat(-1)), ("R", .right, uR, 1)] {
            guard let s = stickC[stick] else { return nil }
            let pw = G.shoulderSize.width * u, ph = G.shoulderSize.height * u
            let spread = G.shoulderSpread * u
            let above = s.y + G.shoulderDY * u
            // (block width, block height, ideal block centre, [(id, offset from block centre)])
            let outer = "\(suffix)", inner = "Z\(suffix)"
            let pairW = 2 * spread + pw
            let colH = 2 * ph + 0.12 * u
            let variants: [(CGFloat, CGFloat, CGPoint, [(String, CGPoint)])] = [
                (pairW, ph, CGPoint(x: s.x, y: above),
                 [(outer, CGPoint(x: sign * spread, y: 0)), (inner, CGPoint(x: -sign * spread, y: 0))]),
                (pw, colH, CGPoint(x: s.x, y: s.y - (G.stickBase / 2 + G.shoulderGap) * u - colH / 2),
                 [(outer, CGPoint(x: 0, y: colH / 2 - ph / 2)), (inner, CGPoint(x: 0, y: -(colH / 2 - ph / 2)))]),
                (pairW, ph, CGPoint(x: s.x, y: s.y + (G.stickBase / 2 + G.shoulderGap) * u + ph / 2),
                 [(outer, CGPoint(x: sign * spread, y: 0)), (inner, CGPoint(x: -sign * spread, y: 0))]),
                (pairW, ph, CGPoint(x: s.x + sign * (G.stickBase / 2 + 0.2 * u + pairW / 2), y: s.y),
                 [(outer, CGPoint(x: sign * spread, y: 0)), (inner, CGPoint(x: -sign * spread, y: 0))]),
                (pairW, ph, CGPoint(x: s.x - sign * (G.stickBase / 2 + 0.2 * u + pairW / 2), y: s.y),
                 [(outer, CGPoint(x: sign * spread, y: 0)), (inner, CGPoint(x: -sign * spread, y: 0))]),
                (pw, colH, CGPoint(x: s.x + sign * (G.stickBase / 2 + 0.2 * u + pw / 2), y: s.y),
                 [(outer, CGPoint(x: 0, y: colH / 2 - ph / 2)), (inner, CGPoint(x: 0, y: -(colH / 2 - ph / 2)))]),
                (pw, colH, CGPoint(x: s.x - sign * (G.stickBase / 2 + 0.2 * u + pw / 2), y: s.y),
                 [(outer, CGPoint(x: 0, y: colH / 2 - ph / 2)), (inner, CGPoint(x: 0, y: -(colH / 2 - ph / 2)))]),
            ]
            var done = false
            var bestTrial: (Packer, [(String, CGPoint)], CGFloat)?
            for (i, v) in variants.enumerated() {
                var trial = pk
                guard let r = trial.place(centre: v.2, w: v.0, h: v.1, ideal: v.2, penalty: CGFloat(i) * 0.6 * u),
                      r.center.distance(to: v.2) <= 4 * u else { continue }
                let c = r.center.distance(to: v.2) + CGFloat(i) * 0.6 * u
                if bestTrial == nil || c < bestTrial!.2 {
                    bestTrial = (trial, v.3.map { ($0.0, CGPoint(x: r.midX + $0.1.x, y: r.midY + $0.1.y)) }, c)
                }
            }
            if let (trial, pills, _) = bestTrial {
                pk = trial
                for (id, c) in pills { pill(id, c, u) }
                done = true
            }
            if !done {
                for (id, dx) in [(outer, sign * spread), (inner, -sign * spread)] {
                    let ideal = CGPoint(x: s.x + dx, y: above)
                    guard let r = pk.place(centre: ideal, w: pw, h: ph, ideal: ideal), r.center.distance(to: ideal) <= 4 * u
                    else { return nil }
                    pill(id, r.center, u)
                }
            }
        }
        return Result(placements: out, leftUnit: uL, rightUnit: uR)
    }
}
