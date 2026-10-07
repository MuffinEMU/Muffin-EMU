import CoreGraphics

/// Scheme 4 - Frame Pad.
///
/// Controls that never cover the game. Frame reads where the video is
/// (`LayoutContext.videoRects`) and builds the pad in the space left over:
///
/// - Side columns when the video leaves room left and right (two screens stacked on an
///   iPad in landscape leaves ~220pt a side). Each column top to bottom: shoulder pair,
///   stick, d-pad / face diamond, then minus / plus.
/// - A bottom band when the video sits at the top (iPad portrait): each half holds its
///   shoulders above a stick beside its d-pad / face diamond.
/// - Buttons are sized to the space, not to a fixed unit, and every control's catchment
///   runs out to the edge of its column, so the whole margin is live and nothing on the
///   game is.
/// - When no arrangement fits at a usable size (a single 16:9 screen on a 4:3 iPad, where
///   the margins are thin strips), it falls back to Zone's layout over the video rather
///   than shipping thumb-hostile buttons.
///
/// The GamePad image stays a real touchscreen: every touch on it that no control claims
/// goes to the Wii U touchscreen - the reason to keep controls off it in the first place.
public final class FramePad: ControlScheme {
    public static let schemeInfo = SchemeInfo(
        id: "frame",
        name: "Frame",
        summary: "Controls fill the space around the game and never cover it. The GamePad screen stays touchable.")

    public enum Mode: Equatable, Sendable { case columns, band, overlay }

    /// Smallest face-button diameter Frame will lay out, in points.
    public var minimumUnit: CGFloat = 40
    public private(set) var mode: Mode = .overlay

    /// A's size as a multiple of its usual one (1...1.8).
    public let aScale: CGFloat

    public init(aScale: CGFloat = 1) {
        self.aScale = aScale
        super.init(info: Self.schemeInfo)
    }

    override public func makeControls(_ ctx: LayoutContext) -> [PadControl] {
        let s = ctx.safeBounds
        let maxU = ctx.unit
        let video = ctx.videoRects.reduce(CGRect.null) { $0.union($1) }

        guard !video.isNull else {
            mode = .overlay
            return GamePadArrangement.build(ctx, aScale: aScale)
        }

        let leftCol = CGRect(x: s.minX, y: s.minY, width: max(video.minX - s.minX, 0), height: s.height)
        let rightCol = CGRect(x: video.maxX, y: s.minY, width: max(s.maxX - video.maxX, 0), height: s.height)
        let band = CGRect(x: s.minX, y: video.maxY, width: s.width, height: max(s.maxY - video.maxY, 0))

        // Height in units a column needs: shoulders 1.0, gap .35, stick 3.48, gap .45,
        // diamond 3.48, gap .35, system row .8, margins .5.
        // Width is the d-pad's catchment circle (2 x 2.04) plus a margin.
        let columnUnits = CGSize(width: 4.3, height: 10.45)
        let colU = min(min(leftCol.width, rightCol.width) / columnUnits.width, s.height / columnUnits.height, maxU)
        // Band half: stick + diamond side by side (3.48 + .5 + 3.48 + margins) wide,
        // shoulders + stick tall.
        let bandUnits = CGSize(width: 8.2, height: 5.3)
        let bandU = min(band.width / 2 / bandUnits.width, band.height / bandUnits.height, maxU)

        if colU >= bandU, colU >= minimumUnit {
            mode = .columns
            return column(leftCol, side: .left, u: colU) + column(rightCol, side: .right, u: colU)
        }
        if bandU >= minimumUnit {
            mode = .band
            let left = CGRect(x: band.minX, y: band.minY, width: band.width / 2, height: band.height)
            let right = CGRect(x: band.midX, y: band.minY, width: band.width / 2, height: band.height)
            return bandHalf(left, side: .left, u: bandU) + bandHalf(right, side: .right, u: bandU)
                + [home(CGPoint(x: band.midX, y: band.maxY - 0.55 * bandU), u: bandU, bottomLimit: s.maxY)]
        }
        mode = .overlay
        return GamePadArrangement.build(ctx, aScale: aScale)
    }

    private enum Side { case left, right }

    private func column(_ col: CGRect, side: Side, u: CGFloat) -> [PadControl] {
        let cx = col.midX
        // Spread spare height evenly between the four blocks rather than piling it at
        // the bottom - a tall column puts the diamond where a resting thumb is.
        let needed = 10.45 * u
        let spare = max(col.height - needed, 0) / 5
        var y = col.minY + 0.25 * u + spare

        let sh = CGSize(width: min(1.7 * u, (col.width - 0.8 * u) / 2), height: 1.0 * u)
        let outer = CGRect(x: side == .left ? cx - sh.width - 0.15 * u : cx + 0.15 * u, y: y, width: sh.width, height: sh.height)
        let inner = CGRect(x: side == .left ? cx + 0.15 * u : cx - sh.width - 0.15 * u, y: y, width: sh.width, height: sh.height)
        y += 1.0 * u + 0.35 * u + spare

        let stickCentre = CGPoint(x: cx, y: y + PadParts.stickBaseDiameter / 2 * u)
        y += PadParts.stickBaseDiameter * u + 0.45 * u + spare
        let diamond = CGPoint(x: cx, y: y + PadParts.stickBaseDiameter / 2 * u)
        y += PadParts.stickBaseDiameter * u + 0.35 * u + spare
        let systemCentre = CGPoint(x: cx, y: min(y + 0.4 * u, col.maxY - 0.45 * u))

        // Catchment out to the column walls: generous, and the video is never in reach
        // because the column stops where it starts.
        let a = PadParts.clampedAScale(aScale), nb = PadParts.neighbourScale(forA: a)
        let wall = (col.width / 2 - (PadParts.crossX + 0.25 * (a + nb)) * u) / u
        let reach = max(0.3 / a, min(wall / a, 0.8))
        let faceAt = diamond - CGPoint(x: 0.25 * (a - nb) * u, y: 0)
        var out: [PadControl]
        if side == .left {
            out = [
                PadParts.shoulder(.zl, outer, u: u, group: PadParts.Group.leftShoulders),
                PadParts.shoulder(.l, inner, u: u, group: PadParts.Group.leftShoulders),
                PadParts.stick(.left, at: stickCentre, u: u, click: .stickL),
                PadParts.dpad(diamond, u: u, click: nil),
                PadParts.system(.minus, at: systemCentre, u: u),
            ]
        } else {
            out = [
                PadParts.shoulder(.zr, outer, u: u, group: PadParts.Group.rightShoulders),
                PadParts.shoulder(.r, inner, u: u, group: PadParts.Group.rightShoulders),
                PadParts.stick(.right, at: stickCentre, u: u, click: .stickR),
                // HOME shares the plus row: the video owns the bottom-centre spot it has
                // on the hardware.
                PadParts.system(.plus, at: systemCentre + CGPoint(x: -0.6 * u, y: 0), u: u),
                PadParts.system(.home, at: systemCentre + CGPoint(x: 0.6 * u, y: 0), u: u),
            ] + PadParts.faceDiamond(faceAt, u: u, reach: reach, rDot: false, aScale: a)
        }
        return out
    }

    private func bandHalf(_ half: CGRect, side: Side, u: CGFloat) -> [PadControl] {
        let spareY = max(half.height - 5.3 * u, 0) / 3
        let top = half.minY + 0.2 * u + spareY
        let sh = CGSize(width: 1.9 * u, height: 1.0 * u)
        let rowY = top + 1.0 * u + 0.4 * u + spareY + PadParts.stickBaseDiameter / 2 * u
        let spareX = max(half.width - 8.2 * u, 0) / 3
        let outerX = side == .left ? half.minX + 0.35 * u + spareX : half.maxX - 0.35 * u - spareX
        let dir: CGFloat = side == .left ? 1 : -1
        let outerCentre = CGPoint(x: outerX + dir * PadParts.stickBaseDiameter / 2 * u, y: rowY)
        let innerCentre = CGPoint(x: outerCentre.x + dir * (PadParts.stickBaseDiameter + 0.55) * u + dir * spareX, y: rowY)

        let zOuter = CGRect(x: side == .left ? half.minX + 0.35 * u : half.maxX - 0.35 * u - sh.width,
                            y: top, width: sh.width, height: sh.height)
        let zInner = zOuter.offsetBy(dx: dir * (sh.width + 0.3 * u), dy: 0)
        let sysCentre = CGPoint(x: zInner.midX + dir * (sh.width / 2 + 0.9 * u), y: zInner.midY)

        if side == .left {
            // Stick outside, d-pad inside - the GamePad's own left-hand order, read
            // across instead of down.
            return [
                PadParts.shoulder(.zl, zOuter, u: u, group: PadParts.Group.leftShoulders),
                PadParts.shoulder(.l, zInner, u: u, group: PadParts.Group.leftShoulders),
                PadParts.system(.minus, at: sysCentre, u: u),
                PadParts.stick(.left, at: outerCentre, u: u, click: .stickL),
                PadParts.dpad(innerCentre, u: u, click: nil),
            ]
        } else {
            return [
                PadParts.shoulder(.zr, zOuter, u: u, group: PadParts.Group.rightShoulders),
                PadParts.shoulder(.r, zInner, u: u, group: PadParts.Group.rightShoulders),
                PadParts.system(.plus, at: sysCentre, u: u),
                PadParts.stick(.right, at: innerCentre, u: u, click: .stickR),
            ] + PadParts.faceDiamond(outerCentre - CGPoint(x: 0.5 * (PadParts.clampedAScale(aScale) - 1) * u, y: 0), u: u, rDot: false, aScale: aScale)
        }
    }

    private func home(_ c: CGPoint, u: CGFloat, bottomLimit: CGFloat) -> PadControl {
        PadParts.system(.home, at: CGPoint(x: c.x, y: min(c.y, bottomLimit - PadParts.systemDiameter / 2 * u)), u: u)
    }
}
