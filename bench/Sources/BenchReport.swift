//
//  BenchReport.swift
//  The persisted results model (what BenchRunner writes to
//  Documents/MuffinBenchResults.json after every engine) and the plain-text report
//  built from it. Kept separate from BenchRunner on purpose: the model is the contract
//  between a run that happened minutes ago and a "Last report" tap that happened after
//  the app was relaunched, and the text builder only ever reads that model - it never
//  reaches back into a live run.
//
import Foundation

// MARK: - Persisted model

struct BenchRunMeta: Codable {
    var appVersion: String        // CFBundleShortVersionString
    var appBuild: String          // CFBundleVersion
    var date: Date
    var deviceModel: String       // sysctl hw.machine, e.g. "iPad8,6"
    var iosVersion: String
    var physicalRAMBytes: UInt64
    /// Same answer for every engine in this process (mbench_jit_permitted() only
    /// depends on whether iOS granted this process CS_DEBUGGED), filled in once the
    /// first engine reports it rather than guessed up front.
    var jitPermitted: Bool
}

/// One boot's worth of a single sub-test, as read off the guest's own MUFFINBENCH
/// markers. `attempt` is 1...3; BenchRunner always does 3 fresh-boot attempts per test.
struct TestRunAttempt: Codable {
    var attempt: Int
    var succeeded: Bool
    var timedOut: Bool
    var beginTimeSeconds: Double?     // monotonic clock, informational
    var endTimeSeconds: Double?
    var durationSeconds: Double?      // endTime - beginTime; nil when there is no matching pair
    var checksum: String?
    var framesAtBegin: UInt64?        // gpu tests only
    var framesAtEnd: UInt64?          // gpu tests only
    var framesPerSecond: Double?      // gpu tests only
    var error: String?                // e.g. "timed out before END", "no END before DONE"
}

struct SubTestOutcome: Codable {
    var name: String                  // the <test> token from the marker, e.g. "int_mix"
    var attempts: [TestRunAttempt]
}

/// One of the three tests BenchRunner drives per engine: cpu_interpreter, cpu_recompiler
/// (skipped whole when JIT isn't permitted), gpu_renderer.
struct TestOutcome: Codable {
    var kind: String                  // "cpu_interpreter" | "cpu_recompiler" | "gpu_renderer"
    var cpuMode: String                // "interpreter" | "recompiler"
    var skipped: Bool
    var skipReason: String?
    var subTests: [SubTestOutcome]
}

struct EngineResult: Codable {
    var id: String
    var displayName: String
    var commit: String?
    /// Non-nil means this engine never ran at all - loading, initializing, or attaching
    /// the surface failed. The run keeps going to the next engine either way.
    var loadError: String?
    var thermalStateAtStart: String
    var thermalWaitSeconds: Double
    var idleCPUPercent: Double?
    var definedClassNames: [String]
    var tests: [TestOutcome]
    var cooldownSeconds: Double
}

struct BenchResultsFile: Codable {
    var meta: BenchRunMeta
    var engines: [EngineResult]
}

extension JSONEncoder {
    static var muffinBench: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var muffinBench: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Report text

/// The fixed test order the report walks - same order BenchRunner runs them in, so the
/// report reads top to bottom the same way the run happened.
private let reportTestOrder = ["cpu_interpreter", "cpu_recompiler", "gpu_renderer"]

private let reportTestTitles: [String: String] = [
    "cpu_interpreter": "CPU - interpreter",
    "cpu_recompiler": "CPU - recompiler",
    "gpu_renderer": "GPU renderer",
]

enum BenchReport {

    /// Builds the whole copy/paste report from one results file. Pure function of its
    /// input - the same BenchResultsFile always produces the same text, whether it came
    /// from a run that just finished or one reloaded from disk.
    static func build(from results: BenchResultsFile) -> String {
        var lines: [String] = []

        lines.append("MuffinEMU Bench Report")
        lines.append(String(repeating: "=", count: 23))
        lines.append("App:      \(results.meta.appVersion) (build \(results.meta.appBuild))")
        lines.append("Date:     \(isoFormatter.string(from: results.meta.date))")
        lines.append("Device:   \(results.meta.deviceModel) / iOS \(results.meta.iosVersion)")
        lines.append("RAM:      \(formatBytes(results.meta.physicalRAMBytes))")
        lines.append("JIT:      \(results.meta.jitPermitted ? "permitted" : "NOT permitted (recompiler tests skipped)")")
        lines.append("")

        lines.append("Engines")
        lines.append(String(repeating: "-", count: 7))
        for (index, engine) in results.engines.enumerated() {
            lines.append("[\(index + 1)] \(engine.id) - \(engine.displayName)")
            if let loadError = engine.loadError {
                lines.append("    framework load: FAILED - \(loadError)")
                continue
            }
            lines.append("    commit:         \(engine.commit ?? "unknown")")
            lines.append("    framework load: ok")
            lines.append("    thermal start:  \(engine.thermalStateAtStart) (waited \(formatSeconds(engine.thermalWaitSeconds)) for it to settle)")
            lines.append("    idle CPU (5s):  \(engine.idleCPUPercent.map { formatPercent($0) } ?? "n/a")")
            lines.append("    cooldown after: \(formatSeconds(engine.cooldownSeconds))")
        }
        lines.append("")

        for kind in reportTestOrder {
            let table = buildTable(for: kind, results: results)
            if let table {
                lines.append(reportTestTitles[kind] ?? kind)
                lines.append(String(repeating: "-", count: (reportTestTitles[kind] ?? kind).count))
                lines.append(contentsOf: table)
                lines.append("")
            }
        }

        lines.append(contentsOf: buildChecksumSection(results: results))
        lines.append("")
        lines.append(contentsOf: buildNotesSection(results: results))

        return lines.joined(separator: "\n")
    }

    // MARK: Per-test table

    /// One row per sub-test name seen in this test across any engine, one column per
    /// engine (median seconds, min-max, and for gpu also fps), plus a column showing
    /// each non-baseline engine's speed relative to muffin-v38 - baselineMedian /
    /// thisMedian, so 2.31x means this engine finished in less than half the time.
    private static func buildTable(for kind: String, results: BenchResultsFile) -> [String]? {
        let loadedEngines = results.engines.filter { $0.loadError == nil }
        guard !loadedEngines.isEmpty else { return nil }

        var subTestNames: [String] = []
        for engine in loadedEngines {
            guard let test = engine.tests.first(where: { $0.kind == kind }), !test.skipped else { continue }
            for sub in test.subTests where !subTestNames.contains(sub.name) {
                subTestNames.append(sub.name)
            }
        }
        guard !subTestNames.isEmpty else { return nil }

        let isGPU = (kind == "gpu_renderer")
        let baselineID = benchEngines.first?.id ?? "muffin-v38"

        var headers = ["sub-test"]
        for engine in results.engines { headers.append(engine.id) }
        for engine in results.engines where engine.id != baselineID {
            headers.append("\(engine.id) vs base")
        }

        var rows: [[String]] = []
        for name in subTestNames {
            var row = [name]
            var baselineMedian: Double?

            for engine in results.engines {
                let cell = cellText(engine: engine, kind: kind, subTest: name, isGPU: isGPU)
                row.append(cell.text)
                if engine.id == baselineID { baselineMedian = cell.medianSeconds }
            }
            for engine in results.engines where engine.id != baselineID {
                let cell = cellText(engine: engine, kind: kind, subTest: name, isGPU: isGPU)
                if let base = baselineMedian, let this = cell.medianSeconds, this > 0 {
                    row.append(String(format: "%.2fx", base / this))
                } else {
                    row.append("-")
                }
            }
            rows.append(row)
        }

        return renderTable(headers: headers, rows: rows)
    }

    private static func cellText(engine: EngineResult, kind: String, subTest: String, isGPU: Bool) -> (text: String, medianSeconds: Double?) {
        guard let test = engine.tests.first(where: { $0.kind == kind }) else {
            return ("skipped", nil)
        }
        if test.skipped {
            return ("skipped", nil)
        }
        guard let sub = test.subTests.first(where: { $0.name == subTest }) else {
            return ("-", nil)
        }
        let durations = sub.attempts.compactMap { $0.succeeded ? $0.durationSeconds : nil }
        guard !durations.isEmpty else {
            return ("FAIL", nil)
        }
        let med = median(durations)
        let lo = durations.min() ?? med
        let hi = durations.max() ?? med
        var text = String(format: "%.3fs (%.3f-%.3f)", med, lo, hi)

        if isGPU {
            let fpsValues = sub.attempts.compactMap { $0.succeeded ? $0.framesPerSecond : nil }
            if !fpsValues.isEmpty {
                text += String(format: " @ %.1f fps", median(fpsValues))
            }
        }
        return (text, med)
    }

    // MARK: Checksums

    /// For every sub-test, whether every engine that completed it agrees on the
    /// checksum. A disagreement means two engines produced different emulated output
    /// for the identical workload - a real emulation-correctness bug, not noise, so it
    /// is called out by name rather than folded into the timing table.
    private static func buildChecksumSection(results: BenchResultsFile) -> [String] {
        var lines: [String] = ["Checksums", String(repeating: "-", count: 9)]
        var anyRow = false

        for kind in reportTestOrder {
            var subTestNames: [String] = []
            for engine in results.engines {
                guard let test = engine.tests.first(where: { $0.kind == kind }), !test.skipped else { continue }
                for sub in test.subTests where !subTestNames.contains(sub.name) {
                    subTestNames.append(sub.name)
                }
            }
            for name in subTestNames {
                var perEngineChecksums: [(id: String, checksums: [String])] = []
                for engine in results.engines {
                    guard engine.loadError == nil,
                          let test = engine.tests.first(where: { $0.kind == kind }), !test.skipped,
                          let sub = test.subTests.first(where: { $0.name == name }) else { continue }
                    let checksums = Array(Set(sub.attempts.compactMap { $0.checksum })).sorted()
                    guard !checksums.isEmpty else { continue }
                    perEngineChecksums.append((engine.id, checksums))
                }
                guard !perEngineChecksums.isEmpty else { continue }
                anyRow = true

                let nonDeterministic = perEngineChecksums.filter { $0.checksums.count > 1 }
                let distinctPrimary = Set(perEngineChecksums.map { $0.checksums[0] })

                if distinctPrimary.count <= 1 && nonDeterministic.isEmpty {
                    lines.append("  [\(kind)] \(name): OK - all engines agree")
                } else {
                    lines.append("  [\(kind)] \(name): MISMATCH")
                    for entry in perEngineChecksums {
                        lines.append("      \(entry.id): \(entry.checksums.joined(separator: ", "))")
                    }
                }
            }
        }

        if !anyRow {
            lines.append("  (no sub-test completed on more than zero engines)")
        }
        return lines
    }

    // MARK: Notes

    private static func buildNotesSection(results: BenchResultsFile) -> [String] {
        var lines = ["Notes", String(repeating: "-", count: 5)]
        var wroteAny = false

        for engine in results.engines {
            if let loadError = engine.loadError {
                lines.append("- \(engine.id): did not run - \(loadError)")
                wroteAny = true
            }
            for test in engine.tests where test.skipped {
                lines.append("- \(engine.id) / \(test.kind): skipped - \(test.skipReason ?? "no reason recorded")")
                wroteAny = true
            }
            for test in engine.tests {
                for sub in test.subTests {
                    for attempt in sub.attempts where attempt.timedOut {
                        lines.append("- \(engine.id) / \(test.kind) / \(sub.name): attempt \(attempt.attempt) timed out")
                        wroteAny = true
                    }
                    for attempt in sub.attempts where !attempt.succeeded && !attempt.timedOut {
                        lines.append("- \(engine.id) / \(test.kind) / \(sub.name): attempt \(attempt.attempt) failed - \(attempt.error ?? "no END marker observed")")
                        wroteAny = true
                    }
                }
            }
        }

        // Cross-engine Objective-C class collisions: a class name defined by more than
        // one loaded engine's image is a real isolation risk (see LoadedEngine's own
        // comment on why -fvisibility/exported-symbols-list alone doesn't prevent it).
        var classOwners: [String: [String]] = [:]
        for engine in results.engines where engine.loadError == nil {
            for className in engine.definedClassNames {
                classOwners[className, default: []].append(engine.id)
            }
        }
        let collisions = classOwners.filter { $0.value.count > 1 }.sorted { $0.key < $1.key }
        if !collisions.isEmpty {
            wroteAny = true
            lines.append("- ISOLATION RISK: Objective-C class names defined by more than one engine:")
            for (className, owners) in collisions {
                lines.append("    \(className): \(owners.joined(separator: ", "))")
            }
        }

        if !wroteAny {
            lines.append("- nothing to flag: every engine loaded, every test ran, no timeouts")
        }

        lines.append("")
        lines.append("Method: identical cpubench.rpx / gpubench.rpx per test, identical MUFFINBENCH")
        lines.append("BEGIN/END/DONE markers, wall clock measured host-side from log timestamps at the")
        lines.append("moment each marker line is read, 3 fresh-boot runs per test, reported values are")
        lines.append("median (min-max) across the runs that completed.")

        return lines
    }

    // MARK: Formatting helpers

    private static func renderTable(headers: [String], rows: [[String]]) -> [String] {
        let columnCount = headers.count
        var widths = headers.map { $0.count }
        for row in rows {
            for (i, cell) in row.enumerated() where i < columnCount {
                widths[i] = max(widths[i], cell.count)
            }
        }

        func renderRow(_ cells: [String]) -> String {
            var parts: [String] = []
            for i in 0..<columnCount {
                let cell = i < cells.count ? cells[i] : ""
                parts.append(cell.padding(toLength: widths[i], withPad: " ", startingAt: 0))
            }
            return parts.joined(separator: "  ")
        }

        var out = [renderRow(headers)]
        out.append(widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "))
        for row in rows { out.append(renderRow(row)) }
        return out
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let count = sorted.count
        guard count > 0 else { return 0 }
        if count % 2 == 1 {
            return sorted[count / 2]
        }
        return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
    }

    private static func formatSeconds(_ value: Double) -> String {
        String(format: "%.0fs", value)
    }

    private static func formatPercent(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private static func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        return String(format: "%.2f GB", gb)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
