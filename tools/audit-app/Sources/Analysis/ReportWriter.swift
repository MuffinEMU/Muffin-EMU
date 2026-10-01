//
//  ReportWriter.swift
//  Writes a report to disk: report.json (machine-readable), report.md (human-readable) and the
//  per-test log slices and thumbnails next to them. Pure Foundation, so CI exercises it on a Mac.
//
import Foundation

enum ReportWriter {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    static func json(_ report: AuditReport) throws -> Data {
        try encoder().encode(report)
    }

    /// Writes `report.json` and `report.md` into `folder` (created if needed). Returns the two URLs.
    @discardableResult
    static func write(_ report: AuditReport, to folder: URL) throws -> (json: URL, markdown: URL) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let jsonURL = folder.appendingPathComponent("report.json")
        let mdURL = folder.appendingPathComponent("report.md")
        try json(report).write(to: jsonURL, options: .atomic)
        try markdown(report).data(using: .utf8)!.write(to: mdURL, options: .atomic)
        return (jsonURL, mdURL)
    }

    static func writeLogSlice(_ lines: [LogLine], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let text = lines.map { l -> String in
            let t = String(format: "%14.3f", Double(l.tNs) / 1_000_000_000.0)
            return "\(t)  \(l.tag.map { "[\($0)] " } ?? "")\(l.text)"
        }.joined(separator: "\n") + "\n"
        try text.data(using: .utf8)!.write(to: url, options: .atomic)
    }

    // MARK: Markdown

    static func markdown(_ r: AuditReport) -> String {
        var o: [String] = []
        let s = r.summary

        o.append("# MuffinEMU Audit report")
        o.append("")
        o.append("**Verdict: \(s.verdict.uppercased())** - \(s.counts["pass", default: 0]) passed, \(s.counts["fail", default: 0]) failed, \(s.counts["error", default: 0]) could not complete, \(s.counts["skip", default: 0]) skipped, in \(Int(s.durationSec)) s.")
        o.append("")
        o.append("## What was tested")
        o.append("")
        o.append("| | |")
        o.append("|---|---|")
        o.append("| MuffinEMU ref | `\(r.build.muffinRef)` at `\(r.build.muffinSha.prefix(10))` (version \(r.build.muffinVersion.isEmpty ? "untagged" : r.build.muffinVersion)) |")
        o.append("| Core fingerprint | `\(r.build.coreFingerprint)` |")
        o.append("| Audit app | \(r.build.auditAppVersion) (\(r.build.auditAppBuild)), tools `\(r.build.auditToolsSha.prefix(10))`, guest `\(r.build.guestBuild)`, workflow run \(r.build.workflowRun) |")
        o.append("| Device | \(r.device.machine), \(r.device.systemName) \(r.device.systemVersion), \(r.device.chip), \(r.device.physicalMemoryMB) MB |")
        o.append("| Capabilities | `\(r.device.capsLine)` |")
        o.append("| Renderer | \(r.config.renderer) (core reports \(r.config.graphicsApiReported)); CPU \(r.config.cpuModeReported), \(r.config.coresRunning) core(s); pad surface \(r.config.padSurface ? "on" : "off"); frame readback \(r.config.captureAvailable ? "available" : "unavailable") |")
        o.append("| Run | \(r.config.mode), seed \(r.config.seed), suites \(r.config.suites.joined(separator: ", ")), \(r.config.attended ? "attended" : "unattended") |")
        o.append("| Started | \(r.createdAt) |")
        o.append("")

        if !s.affectedSubsystems.isEmpty {
            o.append("## Affected subsystems")
            o.append("")
            o.append("| Subsystem | Failed tests | Anomalies |")
            o.append("|---|---|---|")
            for a in s.affectedSubsystems {
                o.append("| \(a.subsystem) | \(a.failedTests.isEmpty ? "-" : a.failedTests.joined(separator: ", ")) | \(a.anomalies) |")
            }
            o.append("")
        }

        if !r.findings.isEmpty {
            o.append("## Findings")
            o.append("")
            for f in r.findings {
                o.append("### \(f.testId) - \(f.title) (\(f.result.rawValue))")
                o.append("")
                o.append(f.sentence)
                o.append("")
                if !f.failedExpectations.isEmpty { o.append("Failed expectations:"); f.failedExpectations.forEach { o.append("- \($0)") }; o.append("") }
                if !f.failedChecks.isEmpty { o.append("Failed checks:"); f.failedChecks.forEach { o.append("- \($0)") }; o.append("") }
                if !f.userReported.isEmpty { o.append("User-reported:"); f.userReported.forEach { o.append("- \($0.question) -> **\($0.answer)**") }; o.append("") }
                if !f.logHighlights.isEmpty {
                    o.append("Log lines on this path:")
                    o.append("```")
                    f.logHighlights.forEach { o.append($0.text) }
                    o.append("```")
                    o.append("")
                }
                o.append("Path: \(f.path.isEmpty ? "(no probe markers)" : f.path.joined(separator: " > "))")
                o.append("")
                o.append("Reproduce: \(f.reproduce)")
                o.append("")
            }
        }

        o.append("## All tests")
        o.append("")
        o.append("| Test | Result | Reason | ms |")
        o.append("|---|---|---|---|")
        for t in r.tests {
            let reason = t.reason.replacingOccurrences(of: "|", with: "/").replacingOccurrences(of: "\n", with: " ")
            o.append("| \(t.id)\(t.iteration > 0 ? " #\(t.iteration + 1)" : "") | \(t.result.rawValue) | \(reason.prefix(160)) | \(Int(t.durationMs)) |")
        }
        o.append("")

        for t in r.tests {
            o.append("### \(t.id) - \(t.title)")
            o.append("")
            o.append("Result: **\(t.result.rawValue)** - \(t.reason)")
            o.append("")
            o.append("- Stimulus: \(t.stimulus)")
            o.append("- Expected: \(t.expected)")
            o.append("- Configuration: guest `\(t.configuration.guestTest)` params `\(t.configuration.guestParams)`, seed \(t.configuration.seed), \(t.configuration.renderer), CPU \(t.configuration.cpuMode)")
            o.append("- Window: \(t.startedAt) to \(t.endedAt) (\(Int(t.durationMs)) ms); log slice \(t.logSlice.lineCount) lines\(t.logSlice.droppedLines > 0 ? " (\(t.logSlice.droppedLines) dropped)" : ""), full slice in `\(t.logSlice.file)`")
            if let p = t.performance.frameIntervals {
                o.append(String(format: "- Frame pacing: %.1f fps, p50 %.1f ms, p95 %.1f ms, p99 %.1f ms, max %.1f ms over %d presents (%d long, %d very long)", p.fps, p.p50Ms, p.p95Ms, p.p99Ms, p.maxMs, p.count, p.long, p.veryLong))
            }
            o.append(String(format: "- Memory: footprint %.0f -> %.0f MB (peak %.0f), lowest headroom %.0f MB", t.performance.footprintStartMB, t.performance.footprintEndMB, t.performance.footprintPeakMB, t.performance.availableMinMB))
            if !t.path.isEmpty { o.append("- Path: " + t.path.map { "\($0.kind):\($0.name)" }.joined(separator: " > ")) }
            o.append("")
            for cp in t.checkpoints {
                o.append("Checkpoint `\(cp.name)` (\(cp.frames.count) frame(s) captured):")
                for e in cp.expectations { o.append("- \(e.pass ? "PASS" : (e.severity == "fail" ? "FAIL" : e.severity.uppercased())) \(e.name): \(e.measured)") }
                o.append("")
            }
            if !t.checks.isEmpty {
                o.append("Checks:")
                for c in t.checks { o.append("- \(c.pass ? "PASS" : (c.severity == "fail" ? "FAIL" : c.severity.uppercased())) \(c.name): \(c.summary)") }
                o.append("")
            }
            if !t.scriptSteps.isEmpty {
                o.append("Input script:")
                for s in t.scriptSteps { o.append("- \(s.pass ? "PASS" : "FAIL") \(s.label): wanted \(s.expected), saw \(s.measured)") }
                o.append("")
            }
            if !t.answers.isEmpty {
                o.append("Answers:")
                for a in t.answers { o.append("- \(a.question) -> **\(a.answer)**\(a.bad ? " (reported as a problem)" : "") at \(a.answeredAt)") }
                o.append("")
            }
            if !t.userFlags.isEmpty {
                o.append("Glitches flagged during the test:")
                for f in t.userFlags { o.append("- \(f.at)\(f.note.isEmpty ? "" : ": \(f.note)")") }
                o.append("")
            }
            for a in t.anomalies { o.append("- anomaly (\(a.severity)) \(a.subsystem): \(a.message)") }
            if !t.anomalies.isEmpty { o.append("") }
            o.append("Reproduce: \(t.reproduction.outsideTool)")
            o.append("")
        }

        if !r.anomalies.isEmpty {
            o.append("## Anomalies across the run")
            o.append("")
            for a in r.anomalies { o.append("- **\(a.severity)** \(a.subsystem)\(a.testId.map { " (\($0))" } ?? ""): \(a.message)") }
            o.append("")
        }
        if !r.notes.isEmpty {
            o.append("## Notes")
            o.append("")
            r.notes.forEach { o.append("- \($0)") }
            o.append("")
        }
        return o.joined(separator: "\n")
    }
}
