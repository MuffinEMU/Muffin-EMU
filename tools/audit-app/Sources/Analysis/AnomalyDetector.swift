//
//  AnomalyDetector.swift
//  Finds things that went wrong without anyone having written a test for them: log lines the core
//  only writes when something is off, counters that should never move, memory that keeps growing,
//  audio that glitched, a picture that stalled. Every finding is an Anomaly with the evidence that
//  triggered it. The log patterns are data (Catalogue/anomaly-patterns.json), so a new failure
//  signature is one line of JSON.
//
import Foundation

struct AnomalyPattern: Codable {
    var id: String
    /// Case-insensitive substring of a log line.
    var contains: String
    var severity: String
    var subsystem: String
    var message: String
    /// Lines from the audit's own probe output never match (the guest prints its own words).
    var ignoreProbeLines: Bool?
}

struct AnomalyPatternFile: Codable {
    var schema: String
    var patterns: [AnomalyPattern]
}

struct AnomalyDetector {
    var patterns: [AnomalyPattern]

    static func load(data: Data) -> AnomalyDetector {
        if let file = try? JSONDecoder().decode(AnomalyPatternFile.self, from: data) {
            return AnomalyDetector(patterns: file.patterns)
        }
        return AnomalyDetector(patterns: [])
    }

    // MARK: Log

    /// One anomaly per pattern per scan, with the first few matching lines as evidence and the count.
    func scan(log lines: [LogLine], testId: String?) -> [Anomaly] {
        var out: [Anomaly] = []
        for p in patterns {
            let needle = p.contains.lowercased()
            var hits: [LogLine] = []
            for l in lines {
                if l.tag == "guest" || l.tag == "host" { if p.ignoreProbeLines ?? true { continue } }
                if l.text.lowercased().contains(needle) { hits.append(l) }
            }
            guard let first = hits.first else { continue }
            let extra = hits.count > 1 ? " (\(hits.count) lines)" : ""
            out.append(Anomaly(id: "log.\(p.id)", kind: "log_pattern", severity: p.severity, subsystem: p.subsystem,
                               testId: testId, tNs: first.tNs, message: p.message + extra,
                               evidence: hits.prefix(3).map { $0.text }))
        }
        return out
    }

    // MARK: Counters

    /// Judges a test's counter movement: `before` and `after` are state snapshots taken around it, `samples` the
    /// snapshots taken while it ran.
    static func scan(before: JSONValue?, after: JSONValue?, samples: [JSONValue], testId: String?) -> [Anomaly] {
        var out: [Anomaly] = []
        guard let after = after else { return out }
        func add(_ id: String, _ kind: String, _ severity: String, _ subsystem: String, _ message: String, _ evidence: [String]) {
            out.append(Anomaly(id: id, kind: kind, severity: severity, subsystem: subsystem, testId: testId, tNs: after["tNs"]?.double.map { UInt64($0) },
                               message: message, evidence: evidence))
        }
        func number(_ v: JSONValue?, _ path: String) -> Double { v?.path(path)?.double ?? 0 }

        if after.path("gpuThread.gpuError")?.bool == true {
            add("counter.gpu_error", "gpu_error", "fail", "render.gpu",
                "The GPU reported an error that stops it doing this process's work (code \(Int(number(after, "gpuThread.gpuErrorCode")))).",
                ["gpuThread.gpuError = true", "gpuThread.cbLastErrorCode = \(Int(number(after, "gpuThread.cbLastErrorCode")))"])
        }
        if after.path("gpuThread.gpuPresumedLost")?.bool == true {
            add("counter.gpu_lost", "gpu_lost", "fail", "render.gpu", "The core presumes the GPU is lost.", ["gpuThread.gpuPresumedLost = true"])
        }
        let b = before ?? .object([:])
        func grew(_ path: String) -> Double { number(after, path) - number(b, path) }
        if grew("gpuThread.drawableFailures") > 0 {
            add("counter.drawable_failures", "drawable_failures", "fail", "render.present",
                "The screen layer failed to hand out a drawable \(Int(grew("gpuThread.drawableFailures"))) time(s): frames were lost.",
                ["gpuThread.drawableFailures +\(Int(grew("gpuThread.drawableFailures")))"])
        }
        if grew("gpuThread.erroredCommandBuffers") > 0 {
            add("counter.errored_command_buffers", "command_buffer_error", "fail", "render.gpu",
                "\(Int(grew("gpuThread.erroredCommandBuffers"))) command buffer(s) finished with an error.",
                ["gpuThread.erroredCommandBuffers +\(Int(grew("gpuThread.erroredCommandBuffers")))", "cbLastErrorCode = \(Int(number(after, "gpuThread.cbLastErrorCode")))"])
        }
        if grew("gpuThread.timeouts") > 0 {
            add("counter.gpu_timeouts", "gpu_wait_timeout", "warn", "render.gpu",
                "The GPU thread gave up waiting \(Int(grew("gpuThread.timeouts"))) time(s).", ["gpuThread.timeouts +\(Int(grew("gpuThread.timeouts")))"])
        }
        if grew("gpuMemory.texturesEvicted") > 0 {
            add("counter.textures_evicted", "texture_eviction", "info", "render.texture_cache",
                "\(Int(grew("gpuMemory.texturesEvicted"))) texture(s) were evicted to free memory during the test.",
                ["gpuMemory.texturesEvicted +\(Int(grew("gpuMemory.texturesEvicted")))"])
        }
        if grew("perf.pipelineSyncCompiles") > 5 {
            add("counter.sync_compiles", "sync_pipeline_compile", "info", "render.pipeline",
                "\(Int(grew("perf.pipelineSyncCompiles"))) pipelines were compiled on the GPU thread (frames stalled while they built).",
                ["perf.pipelineSyncCompiles +\(Int(grew("perf.pipelineSyncCompiles")))"])
        }
        if grew("audio.underrunCallbacks") > 0 {
            add("counter.audio_underruns", "audio_underrun", "warn", "audio.output",
                "The audio device ran out of samples \(Int(grew("audio.underrunCallbacks"))) time(s) (\(Int(grew("audio.underrunFrames"))) frames of silence padded in).",
                ["audio.underrunCallbacks +\(Int(grew("audio.underrunCallbacks")))"])
        }
        if grew("audio.feedRejects") > 0 {
            add("counter.audio_overruns", "audio_overrun", "info", "audio.output",
                "The audio queue was full \(Int(grew("audio.feedRejects"))) time(s) when the emulated AX tried to add a block.",
                ["audio.feedRejects +\(Int(grew("audio.feedRejects")))"])
        }

        // Memory: lowest headroom seen while the test ran, and whether the footprint only ever grew.
        let available = samples.compactMap { $0.path("memory.availableBytes")?.double }.filter { $0 > 0 }
        if let low = available.min(), low < 200.0 * 1024 * 1024 {
            add("counter.low_memory", "low_memory", "warn", "memory",
                "Only \(Int(low / 1024 / 1024)) MB were left before iOS would end the app.", ["memory.availableBytes min = \(Int(low))"])
        }
        return out
    }

    /// Footprint growth across a test, from the samples (MB). Reported as an anomaly above `thresholdMB`.
    static func memoryGrowth(samples: [JSONValue], thresholdMB: Double, testId: String?) -> (growthMB: Double, anomaly: Anomaly?) {
        let f = samples.compactMap { $0.path("memory.footprintBytes")?.double }.filter { $0 > 0 }
        guard f.count >= 4 else { return (0, nil) }
        // Compare the median of the first quarter with the median of the last quarter, which ignores a spike.
        let q = max(1, f.count / 4)
        func median(_ a: ArraySlice<Double>) -> Double { let s = a.sorted(); return s[s.count / 2] }
        let growth = (median(f.suffix(q)) - median(f.prefix(q))) / 1024 / 1024
        guard growth > thresholdMB else { return (growth, nil) }
        let a = Anomaly(id: "memory.growth", kind: "memory_growth", severity: "warn", subsystem: "memory.lifecycle", testId: testId, tNs: nil,
                        message: String(format: "Memory footprint grew by %.0f MB over the test (threshold %.0f MB).", growth, thresholdMB),
                        evidence: ["first quarter median \(Int(median(f.prefix(q)) / 1024 / 1024)) MB", "last quarter median \(Int(median(f.suffix(q)) / 1024 / 1024)) MB"])
        return (growth, a)
    }

    /// Pacing anomalies from a test's present intervals.
    static func pacing(_ s: FramePacingStats?, testId: String?) -> [Anomaly] {
        guard let s = s, s.count >= 30 else { return [] }
        var out: [Anomaly] = []
        if s.dropped > 0 {
            out.append(Anomaly(id: "pacing.timestamps_lost", kind: "pacing_data_lost", severity: "info", subsystem: "timing.pacing", testId: testId, tNs: nil,
                               message: "\(s.dropped) present timestamps were lost, so the pacing figures undercount long frames.", evidence: ["dropped = \(s.dropped)"]))
        }
        if s.veryLong > 0 && Double(s.veryLong) / Double(s.count) > 0.01 {
            out.append(Anomaly(id: "pacing.stutter", kind: "frame_stutter", severity: "warn", subsystem: "timing.pacing", testId: testId, tNs: nil,
                               message: String(format: "%d of %d frames took more than 2.5x the median (%.1f ms); worst %.1f ms.", s.veryLong, s.count, s.p50Ms, s.maxMs),
                               evidence: [String(format: "p50 %.1f ms, p95 %.1f ms, p99 %.1f ms, max %.1f ms", s.p50Ms, s.p95Ms, s.p99Ms, s.maxMs)]))
        }
        return out
    }
}
