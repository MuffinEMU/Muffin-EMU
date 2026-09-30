//
//  CheckEvaluator.swift
//  Evaluates the catalogue's whole-test checks (audio windows, memory growth, frame pacing, guest errors)
//  from the measurements the runner collected. Pure Swift.
//
import Foundation

struct CheckInputs {
    /// Audio counters (the snapshot's "audio" object) at the start and end of each guest audio step.
    var audioWindows: [Int: (start: JSONValue, end: JSONValue)] = [:]
    var footprintGrowthMB: Double = 0
    var footprintSamples: Int = 0
    var pacing: FramePacingStats?
    var guestErrors: Int = 0
}

enum CheckEvaluator {
    static func evaluate(_ c: CheckDef, _ inputs: CheckInputs) -> CheckResult {
        let severity = c.severity ?? "fail"
        let name = c.name ?? c.type
        func make(_ pass: Bool, _ summary: String, _ values: [String: Double] = [:], severity sev: String? = nil) -> CheckResult {
            CheckResult(type: c.type, name: name, pass: pass, severity: sev ?? severity, summary: summary, values: values)
        }

        switch c.type {
        case "audio_window":
            guard let step = c.step, let w = inputs.audioWindows[step] else {
                return make(false, "no audio measurement was taken for step \(c.step ?? -1)", ["inconclusive": 1], severity: "warn")
            }
            let s = w.start, e = w.end
            func d(_ key: String) -> Double { (e[key]?.double ?? 0) - (s[key]?.double ?? 0) }
            let frames = d("frames")
            let valid = d("validFrames")
            let underrunFrames = d("underrunFrames")
            let jumps = d("discontinuities")
            // Level over just this window: the snapshot's rms is cumulative since the test began.
            let vA = e["validFrames"]?.double ?? 0, vB = s["validFrames"]?.double ?? 0
            let rA = e["rms"]?.double ?? 0, rB = s["rms"]?.double ?? 0
            let rms = vA > vB ? ((rA * rA * vA - rB * rB * vB) / (vA - vB)).squareRoot() : 0
            let peak = e["peak"]?.double ?? 0

            var problems: [String] = []
            if frames < 4800 { problems.append("the device asked for only \(Int(frames)) frames in the window (audio was not running)") }
            if let m = c.minRms, rms < m { problems.append(String(format: "level %.3f is below the %.3f that means a tone is playing", rms, m)) }
            if let m = c.maxUnderrunFrames, underrunFrames > Double(m) { problems.append("\(Int(underrunFrames)) frames were silence padded in because the queue ran dry (allowed \(m))") }
            if let m = c.maxDiscontinuities, jumps > Double(m) { problems.append("\(Int(jumps)) sample-to-sample jumps above 12000 (allowed \(m)): clicks") }
            if let m = c.minPeak, peak < Double(m) { problems.append("peak \(Int(peak)) is below \(m)") }
            if let m = c.maxPeak, peak > Double(m) { problems.append("peak \(Int(peak)) is above \(m): clipping or wrong gain") }
            let values = ["frames": frames, "validFrames": valid, "underrunFrames": underrunFrames, "discontinuities": jumps, "rms": rms, "peak": peak]
            return make(problems.isEmpty, problems.isEmpty
                        ? String(format: "%.0f frames, level %.3f, peak %.0f, no underruns or clicks beyond the limits", frames, rms, peak)
                        : problems.joined(separator: "; "), values)

        case "memory_growth":
            guard inputs.footprintSamples >= 4 else { return make(false, "too few memory samples (\(inputs.footprintSamples))", ["inconclusive": 1], severity: "warn") }
            let limit = c.maxGrowthMB ?? 64
            return make(inputs.footprintGrowthMB <= limit, String(format: "footprint changed by %.0f MB over the test (limit %.0f MB)", inputs.footprintGrowthMB, limit),
                        ["growthMB": inputs.footprintGrowthMB, "limitMB": limit])

        case "frame_pacing":
            guard let p = inputs.pacing, p.count >= 30 else { return make(false, "too few present timestamps to judge pacing", ["inconclusive": 1], severity: "warn") }
            var problems: [String] = []
            if let m = c.minFps, p.fps < m { problems.append(String(format: "%.1f fps is below %.1f", p.fps, m)) }
            if let m = c.maxP99Ms, p.p99Ms > m { problems.append(String(format: "99th percentile frame time %.1f ms is above %.1f ms", p.p99Ms, m)) }
            if let m = c.maxLongFraction, Double(p.long) / Double(p.count) > m {
                problems.append(String(format: "%.1f%% of frames took over 1.5x the median", 100.0 * Double(p.long) / Double(p.count)))
            }
            return make(problems.isEmpty, problems.isEmpty ? String(format: "%.1f fps, p99 %.1f ms over %d frames", p.fps, p.p99Ms, p.count) : problems.joined(separator: "; "),
                        ["fps": p.fps, "p50Ms": p.p50Ms, "p99Ms": p.p99Ms, "maxMs": p.maxMs, "count": Double(p.count)])

        case "guest_clean":
            return make(inputs.guestErrors == 0, inputs.guestErrors == 0 ? "the guest reported no errors" : "the guest reported \(inputs.guestErrors) error(s)", ["errors": Double(inputs.guestErrors)])

        default:
            return make(false, "unknown check type \(c.type)", severity: "warn")
        }
    }
}
