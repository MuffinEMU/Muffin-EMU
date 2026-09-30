//
//  FrameAnalysis.swift
//  Turns the frames the renderer hands back (a summary plus a small thumbnail each) into pass or fail
//  against what a checkpoint says the scene should look like. Pure Swift with no UIKit, so it is
//  unit-tested on a Mac in CI (tools/audit-app/Tests/logic_tests.swift).
//
import Foundation

struct CapturedFrame {
    var seq: UInt32 = 0
    /// 1 = TV, 2 = GamePad.
    var view: Int = 1
    /// 0 = ok, 1 = unsupported pixel format, 2 = readback failed.
    var status: UInt32 = 0
    var latteFrame: UInt32 = 0
    var tNs: UInt64 = 0
    var srcWidth: Int = 0
    var srcHeight: Int = 0
    var pixelFormat: Int = 0
    var thumbWidth: Int = 0
    var thumbHeight: Int = 0
    var meanR: Double = 0
    var meanG: Double = 0
    var meanB: Double = 0
    var blackFraction: Double = 0
    var whiteFraction: Double = 0
    var minLuma: Int = 0
    var maxLuma: Int = 0
    var hash: UInt64 = 0
    var thumb: [UInt8] = []

    var isUsable: Bool { status == 0 && thumbWidth > 0 && thumbHeight > 0 && thumb.count >= thumbWidth * thumbHeight * 3 }
    var viewName: String { view == 2 ? "pad" : "tv" }

    func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let cx = min(max(x, 0), thumbWidth - 1)
        let cy = min(max(y, 0), thumbHeight - 1)
        let i = (cy * thumbWidth + cx) * 3
        return (Int(thumb[i]), Int(thumb[i + 1]), Int(thumb[i + 2]))
    }
}

/// How the screen came out relative to the way the guest drew it (y = 0 is meant to be the top).
enum Orientation: String, Codable {
    case normal
    case flippedVertically
    case flippedHorizontally
    case rotated180

    /// Maps a point from the guest's screen space to the captured image's.
    func map(x: Double, y: Double) -> (Double, Double) {
        switch self {
        case .normal: return (x, y)
        case .flippedVertically: return (x, 1 - y)
        case .flippedHorizontally: return (1 - x, y)
        case .rotated180: return (1 - x, 1 - y)
        }
    }

    /// Maps a rectangle [x, y, w, h].
    func map(rect r: [Double]) -> [Double] {
        let (x0, y0) = map(x: r[0], y: r[1])
        let (x1, y1) = map(x: r[0] + r[2], y: r[1] + r[3])
        return [min(x0, x1), min(y0, y1), abs(x1 - x0), abs(y1 - y0)]
    }
}

struct FrameAnalysis {
    // MARK: Regions

    /// Mean colour of the thumbnail cells inside `rect` (guest screen space), shrunk by `inset` of its size on each side.
    static func regionMean(_ frame: CapturedFrame, rect: [Double], orientation: Orientation, inset: Double = 0.15) -> (Double, Double, Double)? {
        guard frame.isUsable, rect.count == 4 else { return nil }
        let m = orientation.map(rect: rect)
        let x0 = m[0] + m[2] * inset, x1 = m[0] + m[2] * (1 - inset)
        let y0 = m[1] + m[3] * inset, y1 = m[1] + m[3] * (1 - inset)
        let px0 = Int((x0 * Double(frame.thumbWidth)).rounded(.down))
        let px1 = max(px0, Int((x1 * Double(frame.thumbWidth)).rounded(.up)) - 1)
        let py0 = Int((y0 * Double(frame.thumbHeight)).rounded(.down))
        let py1 = max(py0, Int((y1 * Double(frame.thumbHeight)).rounded(.up)) - 1)
        var sr = 0, sg = 0, sb = 0, n = 0
        for y in py0...py1 {
            for x in px0...px1 {
                let (r, g, b) = frame.pixel(x, y)
                sr += r; sg += g; sb += b; n += 1
            }
        }
        guard n > 0 else { return nil }
        return (Double(sr) / Double(n), Double(sg) / Double(n), Double(sb) / Double(n))
    }

    /// Share of the thumbnail cells inside `rect` whose brightest channel is at most 8.
    static func blackShare(_ frame: CapturedFrame, rect: [Double], orientation: Orientation) -> Double? {
        guard frame.isUsable, rect.count == 4 else { return nil }
        let m = orientation.map(rect: rect)
        let px0 = Int((m[0] * Double(frame.thumbWidth)).rounded(.down))
        let px1 = max(px0, Int(((m[0] + m[2]) * Double(frame.thumbWidth)).rounded(.up)) - 1)
        let py0 = Int((m[1] * Double(frame.thumbHeight)).rounded(.down))
        let py1 = max(py0, Int(((m[1] + m[3]) * Double(frame.thumbHeight)).rounded(.up)) - 1)
        var black = 0, n = 0
        for y in py0...py1 {
            for x in px0...px1 {
                let (r, g, b) = frame.pixel(x, y)
                if max(r, max(g, b)) <= 8 { black += 1 }
                n += 1
            }
        }
        return n > 0 ? Double(black) / Double(n) : nil
    }

    // MARK: Orientation

    private static let markers: [(x: Double, y: Double, rgb: (Int, Int, Int))] = [
        (0.90, 0.10, (255, 0, 0)),     // top right: red
        (0.10, 0.90, (0, 255, 0)),     // bottom left: green
        (0.10, 0.10, (0, 0, 255)),     // top left: blue
        (0.90, 0.90, (255, 255, 255)), // bottom right: white
    ]

    /// Reads the orientation test's four corner markers and says which way the screen came out, and how
    /// clearly (distance between the best reading and the runner-up; near zero means the frame did not
    /// look like the test's scene at all).
    static func detectOrientation(_ frame: CapturedFrame) -> (Orientation, Double)? {
        guard frame.isUsable else { return nil }
        var scores: [(Orientation, Double)] = []
        for o in [Orientation.normal, .flippedVertically, .flippedHorizontally, .rotated180] {
            var total = 0.0
            for m in markers {
                let (mx, my) = o.map(x: m.x, y: m.y)
                let cx = Int(mx * Double(frame.thumbWidth)), cy = Int(my * Double(frame.thumbHeight))
                var sr = 0, sg = 0, sb = 0, n = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        let (r, g, b) = frame.pixel(cx + dx, cy + dy)
                        sr += r; sg += g; sb += b; n += 1
                    }
                }
                let dr = Double(sr / n - m.rgb.0), dg = Double(sg / n - m.rgb.1), db = Double(sb / n - m.rgb.2)
                total += (dr * dr + dg * dg + db * db).squareRoot()
            }
            scores.append((o, total))
        }
        scores.sort { $0.1 < $1.1 }
        return (scores[0].0, scores[1].1 - scores[0].1)
    }

    // MARK: Expectations

    static func evaluate(_ e: Expectation, frames allFrames: [CapturedFrame], orientation: Orientation) -> ExpectationResult {
        let severity = e.severity ?? "fail"
        let name = e.name ?? e.type
        let wanted = e.view ?? "tv"
        let frames = allFrames.filter { $0.viewName == wanted }
        let usable = frames.filter { $0.isUsable }

        func result(pass: Bool, expected: String, measured: String, values: [String: Double] = [:], severity sev: String? = nil) -> ExpectationResult {
            ExpectationResult(type: e.type, name: name, pass: pass, severity: sev ?? severity,
                              expected: expected, measured: measured, values: values)
        }

        guard let frame = usable.last else {
            let why: String
            if frames.isEmpty { why = "no \(wanted) frame was captured" }
            else if let f = frames.last, f.status == 1 { why = "the renderer's output format (MTLPixelFormat \(f.pixelFormat)) cannot be read back" }
            else { why = "the frame readback failed" }
            // Nothing to judge: recorded as a warning so a missing capture never reads as a pass or as a rendering failure.
            return result(pass: false, expected: describe(e), measured: "inconclusive: \(why)", values: ["inconclusive": 1], severity: "warn")
        }

        switch e.type {
        case "region_color":
            guard let rect = e.rect, let rgb = e.rgb, rgb.count == 3, let mean = regionMean(frame, rect: rect, orientation: orientation) else {
                return result(pass: false, expected: describe(e), measured: "malformed expectation", severity: "warn")
            }
            let tol = Double(e.tol ?? 12)
            let d = maxDiff(mean, rgb)
            return result(pass: d <= tol, expected: describe(e), measured: "mean (\(fmt(mean.0)), \(fmt(mean.1)), \(fmt(mean.2))), off by \(fmt(d))",
                          values: ["r": mean.0, "g": mean.1, "b": mean.2, "maxDiff": d])

        case "quadrants":
            let rect = e.rect ?? [0, 0, 1, 1]
            guard rect.count == 4 else { return result(pass: false, expected: describe(e), measured: "malformed expectation", severity: "warn") }
            let tol = Double(e.tol ?? 12)
            let quads: [(String, [Int]?, [Double])] = [
                ("tl", e.tl, [rect[0], rect[1], rect[2] / 2, rect[3] / 2]),
                ("tr", e.tr, [rect[0] + rect[2] / 2, rect[1], rect[2] / 2, rect[3] / 2]),
                ("bl", e.bl, [rect[0], rect[1] + rect[3] / 2, rect[2] / 2, rect[3] / 2]),
                ("br", e.br, [rect[0] + rect[2] / 2, rect[1] + rect[3] / 2, rect[2] / 2, rect[3] / 2]),
            ]
            var values: [String: Double] = [:]
            var bad: [String] = []
            var parts: [String] = []
            var worst = 0.0
            for (label, want, r) in quads {
                guard let want = want, want.count == 3 else { continue }
                guard let mean = regionMean(frame, rect: r, orientation: orientation) else { continue }
                let d = maxDiff(mean, want)
                worst = max(worst, d)
                values["\(label).r"] = mean.0; values["\(label).g"] = mean.1; values["\(label).b"] = mean.2
                parts.append("\(label) (\(fmt(mean.0)), \(fmt(mean.1)), \(fmt(mean.2)))")
                if d > tol { bad.append("\(label) wanted (\(want[0]), \(want[1]), \(want[2]))") }
            }
            values["maxDiff"] = worst
            return result(pass: bad.isEmpty, expected: describe(e),
                          measured: bad.isEmpty ? parts.joined(separator: "; ") : "off: " + bad.joined(separator: ", ") + " | " + parts.joined(separator: "; "),
                          values: values)

        case "not_black":
            let rect = e.rect ?? [0, 0, 1, 1]
            guard let share = blackShare(frame, rect: rect, orientation: orientation) else {
                return result(pass: false, expected: describe(e), measured: "malformed expectation", severity: "warn")
            }
            let maxShare = e.maxBlackFraction ?? 0.5
            return result(pass: share <= maxShare, expected: describe(e), measured: "\(fmt(share * 100))% black", values: ["blackFraction": share])

        case "mean_color":
            guard let rgb = e.rgb, rgb.count == 3 else { return result(pass: false, expected: describe(e), measured: "malformed expectation", severity: "warn") }
            let mean = (frame.meanR, frame.meanG, frame.meanB)
            let d = maxDiff(mean, rgb)
            return result(pass: d <= Double(e.tol ?? 8), expected: describe(e),
                          measured: "frame mean (\(fmt(mean.0)), \(fmt(mean.1)), \(fmt(mean.2))), off by \(fmt(d))",
                          values: ["r": mean.0, "g": mean.1, "b": mean.2, "maxDiff": d])

        case "orientation":
            guard let (o, confidence) = detectOrientation(frame) else {
                return result(pass: false, expected: describe(e), measured: "no usable frame", severity: "warn")
            }
            let clear = confidence > 120
            let text = clear ? "screen came out \(o.rawValue)" : "the four corner markers could not be read clearly (confidence \(fmt(confidence)))"
            return result(pass: true, expected: describe(e), measured: text, values: ["confidence": confidence, "flippedVertically": o == .flippedVertically || o == .rotated180 ? 1 : 0], severity: "info")

        case "frames_identical":
            guard usable.count >= 2 else {
                return result(pass: false, expected: describe(e), measured: "inconclusive: only \(usable.count) frame(s) captured", values: ["inconclusive": 1], severity: "warn")
            }
            let distinct = Set(usable.map { $0.hash }).count
            var maxDiffCell = 0
            for i in 1..<usable.count {
                maxDiffCell = max(maxDiffCell, thumbDifference(usable[i - 1], usable[i]))
            }
            let allowed = e.maxDistinct ?? 1
            return result(pass: distinct <= allowed, expected: describe(e),
                          measured: "\(distinct) distinct frame(s) in \(usable.count); largest change in any thumbnail cell \(maxDiffCell)/255",
                          values: ["distinct": Double(distinct), "frames": Double(usable.count), "maxCellChange": Double(maxDiffCell)])

        case "frame_counter":
            guard usable.count >= 2 else {
                return result(pass: false, expected: describe(e), measured: "inconclusive: only \(usable.count) frame(s) captured", values: ["inconclusive": 1], severity: "warn")
            }
            let r = analyseCounters(usable, orientation: orientation)
            var problems: [String] = []
            let maxTorn = e.maxTornFraction ?? 0.0
            if r.decoded == 0 { problems.append("no frame number could be decoded") }
            if r.decoded > 0 && Double(r.torn) / Double(r.decoded) > maxTorn { problems.append("\(r.torn) of \(r.decoded) frames show different numbers at the top and bottom (tearing)") }
            if r.backwards > (e.maxBackwards ?? 0) { problems.append("\(r.backwards) frame(s) went backwards or repeated") }
            return result(pass: problems.isEmpty, expected: describe(e),
                          measured: problems.isEmpty ? "\(r.decoded) frames decoded, none torn, \(r.mismatchedSteps) step(s) where the guest's frame count and the core's frame count disagreed" : problems.joined(separator: "; "),
                          values: ["decoded": Double(r.decoded), "torn": Double(r.torn), "backwards": Double(r.backwards), "mismatchedSteps": Double(r.mismatchedSteps)])

        default:
            return result(pass: false, expected: describe(e), measured: "unknown expectation type \(e.type)", severity: "warn")
        }
    }

    // MARK: Frame numbers (tear and ordering)

    struct CounterAnalysis {
        var decoded = 0
        var torn = 0
        var backwards = 0
        var mismatchedSteps = 0
    }

    /// The motion test draws the guest's frame number as 16 black/white squares along the top and again along the bottom.
    static func decodeCounter(_ frame: CapturedFrame, bottom: Bool, orientation: Orientation) -> Int? {
        guard frame.isUsable else { return nil }
        var value = 0
        for bit in 0..<16 {
            let gx = (Double(bit) + 0.5) / 16.0
            let gy = bottom ? 0.965 : 0.035
            let (mx, my) = orientation.map(x: gx, y: gy)
            let cx = Int(mx * Double(frame.thumbWidth)), cy = Int(my * Double(frame.thumbHeight))
            var luma = 0, n = 0
            for dx in -1...1 {
                let (r, g, b) = frame.pixel(cx + dx, cy)
                luma += (r * 54 + g * 183 + b * 19) >> 8
                n += 1
            }
            let l = luma / n
            if l > 70 && l < 186 { return nil } // neither black nor white: not a readable square
            if l >= 186 { value |= 1 << bit }
        }
        return value
    }

    static func analyseCounters(_ frames: [CapturedFrame], orientation: Orientation) -> CounterAnalysis {
        var r = CounterAnalysis()
        var previous: (counter: Int, latte: UInt32)?
        for f in frames.sorted(by: { $0.seq < $1.seq }) {
            let top = decodeCounter(f, bottom: false, orientation: orientation)
            let bottom = decodeCounter(f, bottom: true, orientation: orientation)
            guard let t = top, let b = bottom else { continue }
            r.decoded += 1
            if t != b { r.torn += 1 }
            if let p = previous {
                let step = (t - p.counter) & 0xFFFF
                if step == 0 || step > 0x8000 { r.backwards += 1 }
                else if UInt32(truncatingIfNeeded: step) != f.latteFrame &- p.latte { r.mismatchedSteps += 1 }
            }
            previous = (t, f.latteFrame)
        }
        return r
    }

    // MARK: Helpers

    /// Largest difference in any channel of any thumbnail cell between two frames.
    static func thumbDifference(_ a: CapturedFrame, _ b: CapturedFrame) -> Int {
        guard a.isUsable, b.isUsable, a.thumb.count == b.thumb.count else { return 255 }
        var worst = 0
        for i in 0..<a.thumb.count {
            let d = abs(Int(a.thumb[i]) - Int(b.thumb[i]))
            if d > worst { worst = d }
        }
        return worst
    }

    private static func maxDiff(_ mean: (Double, Double, Double), _ rgb: [Int]) -> Double {
        max(abs(mean.0 - Double(rgb[0])), max(abs(mean.1 - Double(rgb[1])), abs(mean.2 - Double(rgb[2]))))
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.1f", v) }

    static func describe(_ e: Expectation) -> String {
        switch e.type {
        case "region_color":
            let rgb = e.rgb ?? []
            return "region \(rectText(e.rect)) is about (\(rgb.map(String.init).joined(separator: ", "))) within \(e.tol ?? 12)"
        case "quadrants":
            var parts: [String] = []
            for (l, c) in [("tl", e.tl), ("tr", e.tr), ("bl", e.bl), ("br", e.br)] {
                if let c = c { parts.append("\(l) (\(c.map(String.init).joined(separator: ", ")))") }
            }
            return "quadrants of \(rectText(e.rect ?? [0, 0, 1, 1])): " + parts.joined(separator: ", ") + " within \(e.tol ?? 12)"
        case "not_black": return "region \(rectText(e.rect ?? [0, 0, 1, 1])) is at most \(Int((e.maxBlackFraction ?? 0.5) * 100))% black"
        case "mean_color": return "frame mean about (\((e.rgb ?? []).map(String.init).joined(separator: ", "))) within \(e.tol ?? 8)"
        case "orientation": return "report which way the screen came out"
        case "frames_identical": return "at most \(e.maxDistinct ?? 1) distinct frame(s) across the captured burst"
        case "frame_counter": return "frame numbers at the top and bottom of every frame agree, and increase"
        default: return e.type
        }
    }

    private static func rectText(_ r: [Double]?) -> String {
        guard let r = r, r.count == 4 else { return "(whole frame)" }
        return "[" + r.map { String(format: "%.2f", $0) }.joined(separator: ", ") + "]"
    }
}
