import CoreGraphics

/// Building blocks shared by the schemes. Every size is in units of one face-button
/// diameter (`u`), and the proportions are the ones MuffinEMU measured off the reference
/// pad (ControllerGeometry) - cross spacing, stick size, shoulder and system-button sizes.
/// Schemes decide WHERE clusters go; these decide what a cluster is.
public enum PadParts {
    /// Centre-to-button spacing of the d-pad and A/B/X/Y, the same both ways. The
    /// reference pad measured 1.240 across but 1.155 down; the real GamePad's clusters
    /// are even, so both use the wider spacing (keeping buttons no closer together).
    public static let crossX: CGFloat = 1.240
    public static let crossY: CGFloat = crossX
    public static let dotDiameter: CGFloat = 0.706
    public static let systemDiameter: CGFloat = 0.773
    public static let shoulderSize = CGSize(width: 1.151, height: 0.874)
    public static let shoulderCorner: CGFloat = 0.235
    public static let stickBaseDiameter: CGFloat = 2 * crossX + 1.0
    public static let knobDiameter: CGFloat = 1.15
    public static var stickTravel: CGFloat { (stickBaseDiameter - knobDiameter) / 2 }
    /// Half-extent of a d-pad or face diamond, centre to outer button edge.
    public static var clusterRadius: CGFloat { crossX + 0.5 }

    public enum Group {
        public static let face = 21
        public static let leftShoulders = 11
        public static let rightShoulders = 12
    }

    /// A/B/X/Y in the Wii U diamond (X top, Y left, A right, B bottom) plus the R3 dot.
    /// Faces slide into each other and chord across the gaps.
    public static func faceDiamond(_ c: CGPoint, u: CGFloat, cluster: Int = -1, scale k: CGFloat = 1,
                                   reach: CGFloat = 0.45, rDot: Bool = true) -> [PadControl] {
        let r = 0.5 * u * k
        func face(_ b: PadButton, _ dx: CGFloat, _ dy: CGFloat) -> PadControl {
            PadControl(.button(b), shape: .circle(center: c + CGPoint(x: dx * u * k, y: dy * u * k), radius: r),
                       role: .face, label: b.description, group: Group.face, cluster: cluster,
                       reach: reach * u, chords: true)
        }
        var out = [face(.x, 0, -crossY), face(.y, -crossX, 0), face(.a, crossX, 0), face(.b, 0, crossY)]
        if rDot {
            out.append(PadControl(.button(.stickR), shape: .circle(center: c, radius: dotDiameter / 2 * u * k),
                                  role: .dot, label: "R3", cluster: cluster, reach: 0.08 * u, priority: 2))
        }
        return out
    }

    /// Eight-way d-pad with the L3 dot in its centre, catchment a little past the arms.
    public static func dpad(_ c: CGPoint, u: CGFloat, cluster: Int = -1, scale k: CGFloat = 1,
                            click: PadButton? = .stickL) -> PadControl {
        PadControl(.dpad(click: click, clickRadius: dotDiameter / 2 * u * k,
                         armOffset: CGPoint(x: crossX * u * k, y: crossY * u * k), armSize: u * k),
                   shape: .circle(center: c, radius: (clusterRadius + 0.3) * u * k),
                   role: .dpad, cluster: cluster)
    }

    public static func stick(_ s: PadStick, at c: CGPoint, u: CGFloat, cluster: Int = -1, scale k: CGFloat = 1,
                             click: PadButton? = nil) -> PadControl {
        PadControl(.stick(s, travel: stickTravel * u * k, click: click),
                   shape: .circle(center: c, radius: stickBaseDiameter / 2 * u * k),
                   role: .stickBase, label: s == .left ? "L" : "R", cluster: cluster, reach: 0.25 * u)
    }

    public static func shoulder(_ b: PadButton, _ rect: CGRect, u: CGFloat, group: Int, cluster: Int = -1) -> PadControl {
        PadControl(.button(b), shape: .roundedRect(rect, cornerRadius: shoulderCorner * u),
                   role: .shoulder, label: b.description, group: group, cluster: cluster, reach: 0.3 * u)
    }

    public static func system(_ b: PadButton, at c: CGPoint, u: CGFloat, cluster: Int = -1) -> PadControl {
        PadControl(.button(b), shape: .circle(center: c, radius: systemDiameter / 2 * u),
                   role: .system, label: b.description, cluster: cluster, reach: 0.25 * u)
    }
}

/// The hardware-faithful arrangement Zone and Adaptive share: like the real GamePad,
/// each stick sits ABOVE its d-pad / face diamond, the shoulders are on the top edge at
/// the outer corners, and HOME is bottom-centre. Plus and minus keep the offset MuffinEMU
/// measured from its reference pad.
///
/// Where the screen is too short for stick-above-cluster (phones in landscape), the sticks
/// move inboard of the clusters instead, and if that still collides the whole thing
/// shrinks - `fit` never returns overlapping controls. The layout checks enforce that on
/// every target device.
public enum GamePadArrangement {
    public struct Clusters {
        public static let dpad = 1
        public static let face = 2
        public static let leftStick = 3
        public static let rightStick = 4
        public static let leftShoulders = 5
        public static let rightShoulders = 6
        public static let system = 7
    }

    public static func build(_ ctx: LayoutContext) -> [PadControl] {
        var u = ctx.unit
        for _ in 0..<8 {
            for inboard in [false, true] {
                let set = arrangement(ctx, u: u, sticksInboard: inboard)
                if LayoutCheck.problems(set, in: ctx.safeBounds).isEmpty { return set }
            }
            u *= 0.92
        }
        return arrangement(ctx, u: u, sticksInboard: true)
    }

    static func arrangement(_ ctx: LayoutContext, u: CGFloat, sticksInboard: Bool) -> [PadControl] {
        let s = ctx.safeBounds
        let cy = s.maxY - (PadParts.clusterRadius + 0.75) * u
        let cl = CGPoint(x: s.minX + (PadParts.clusterRadius + 0.85) * u, y: cy)
        let cr = CGPoint(x: s.maxX - (PadParts.clusterRadius + 0.85) * u, y: cy)
        let stickR = PadParts.stickBaseDiameter / 2 * u

        let sl: CGPoint, sr: CGPoint
        if sticksInboard {
            let dx = PadParts.clusterRadius * u + stickR + 0.55 * u
            sl = CGPoint(x: cl.x + dx, y: cy - 0.9 * u)
            sr = CGPoint(x: cr.x - dx, y: cy - 0.9 * u)
        } else {
            let dy = PadParts.clusterRadius * u + stickR + 0.75 * u
            sl = CGPoint(x: cl.x + 0.3 * u, y: cy - dy)
            sr = CGPoint(x: cr.x - 0.3 * u, y: cy - dy)
        }

        let sh = CGSize(width: 1.9 * u, height: 1.0 * u)
        let top = s.minY + 0.25 * u
        let zl = CGRect(x: s.minX + 0.25 * u, y: top, width: sh.width, height: sh.height)
        let l = zl.offsetBy(dx: sh.width + 0.3 * u, dy: 0)
        let zr = CGRect(x: s.maxX - 0.25 * u - sh.width, y: top, width: sh.width, height: sh.height)
        let r = zr.offsetBy(dx: -(sh.width + 0.3 * u), dy: 0)

        typealias C = Clusters
        return [
            PadParts.shoulder(.zl, zl, u: u, group: PadParts.Group.leftShoulders, cluster: C.leftShoulders),
            PadParts.shoulder(.l, l, u: u, group: PadParts.Group.leftShoulders, cluster: C.leftShoulders),
            PadParts.shoulder(.zr, zr, u: u, group: PadParts.Group.rightShoulders, cluster: C.rightShoulders),
            PadParts.shoulder(.r, r, u: u, group: PadParts.Group.rightShoulders, cluster: C.rightShoulders),
            PadParts.stick(.left, at: sl, u: u, cluster: C.leftStick),
            PadParts.stick(.right, at: sr, u: u, cluster: C.rightStick),
            PadParts.dpad(cl, u: u, cluster: C.dpad),
            PadParts.system(.minus, at: cl + CGPoint(x: 2.353 * u, y: -1.025 * u), u: u, cluster: C.dpad),
            PadParts.system(.plus, at: cr + CGPoint(x: -2.353 * u, y: -1.025 * u), u: u, cluster: C.face),
            PadParts.system(.home, at: CGPoint(x: s.midX, y: s.maxY - 0.6 * u), u: u, cluster: C.system),
        ] + PadParts.faceDiamond(cr, u: u, cluster: C.face)
    }
}

/// Static checks every scheme's layout must pass: nothing overlaps anything else, nothing
/// leaves the safe area. Used by `GamePadArrangement.fit` to pick a size, and by the
/// check suite across every target device.
public enum LayoutCheck {
    public static func problems(_ controls: [PadControl], in bounds: CGRect) -> [String] {
        var out: [String] = []
        let drawn = controls.filter { !$0.isZone }
        for c in drawn {
            let box = c.shape.boundingBox
            if box.minX < bounds.minX - 0.5 || box.maxX > bounds.maxX + 0.5 ||
                box.minY < bounds.minY - 0.5 || box.maxY > bounds.maxY + 0.5 {
                out.append("\(name(c)) leaves the safe area")
            }
        }
        for i in drawn.indices {
            for j in drawn.indices where j > i {
                let a = drawn[i], b = drawn[j]
                // The R3/L3 dots live inside their clusters on purpose.
                if a.role == .dot || b.role == .dot { continue }
                if a.shape.overlaps(b.shape) { out.append("\(name(a)) overlaps \(name(b))") }
            }
        }
        return out
    }

    static func name(_ c: PadControl) -> String {
        switch c.kind {
        case .button(let b): return b.description
        case .dpad: return "d-pad"
        case .stick(let s, _, _), .floatingStick(let s, _, _, _, _), .swipeStick(let s, _):
            return s == .left ? "left stick" : "right stick"
        }
    }
}
