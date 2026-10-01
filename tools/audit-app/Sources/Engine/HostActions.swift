//
//  HostActions.swift
//  Tests the app itself runs instead of the guest: the failures that show up only after repeated use of
//  the core (boot and stop, over and over).
//
import Foundation

extension AuditRunner {
    func runHostAction(_ item: PlannedTest) async -> TestRecord {
        let test = item.test
        guard let spec = test.host else { return skeleton(item, result: .error, reason: "no host section") }
        switch spec.action {
        case "reboot_cycle":
            return await runRebootCycle(item, cycles: Int(spec.params?["cycles"] ?? "") ?? 5)
        default:
            return skeleton(item, result: .error, reason: "unknown host action \(spec.action)")
        }
    }

    /// Boots the guest, waits for its first frames, stops it, and repeats. Every boot must reach a running guest,
    /// and memory after each stop must not keep climbing.
    func runRebootCycle(_ item: PlannedTest, cycles: Int) async -> TestRecord {
        let test = item.test
        let startDate = Date()
        let startNs = core.nowNs
        let startIdx = logs.count
        let startDropped = logs.droppedTotal
        let token = nextToken
        nextToken &+= 1

        var m = Measurements()
        let before = core.snapshot()
        var bootMs: [Double] = []
        var failure: String?
        var path: [PathStep] = []

        await stopGuest()
        for i in 0..<max(1, cycles) {
            if host?.isCancelled == true { failure = "cancelled by the user"; break }
            let t0 = core.nowNs
            do {
                try await ensureGuest()
                // Let it draw for a moment, like a title that reached its first frames.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                logs.drain()
                let frames = link.readState()?.frames ?? 0
                if frames < 10 { throw CoreError.message("the guest presented only \(frames) frame(s) in 1.5 s after boot \(i + 1)") }
            } catch {
                failure = "boot \(i + 1) of \(cycles): \(error)"
                break
            }
            bootMs.append(Double(core.nowNs &- t0) / 1_000_000.0)
            path.append(PathStep(tNs: core.nowNs, kind: "boot", name: "cycle \(i + 1)"))
            await stopGuest()
            try? await Task.sleep(nanoseconds: 1_200_000_000) // let the core release what a title holds
            logs.drain()
            if let snap = core.snapshot() {
                m.samples.append(snap)
                if let f = snap.path("memory.footprintBytes")?.double, f > 0 { m.footprintsMB.append(f / 1_048_576.0) }
                if let a = snap.path("memory.availableBytes")?.double, a > 0 { m.availableMB.append(a / 1_048_576.0) }
            }
            host?.status("\(test.title): cycle \(i + 1) of \(cycles)")
        }
        let after = core.snapshot()
        let endNs = core.nowNs
        let endDate = Date()
        let endIdx = logs.count

        var inputs = CheckInputs()
        inputs.footprintSamples = m.footprintsMB.count
        if m.footprintsMB.count >= 2 { inputs.footprintGrowthMB = (m.footprintsMB.last ?? 0) - (m.footprintsMB.first ?? 0) }
        var checks: [CheckResult] = []
        for c in test.checks ?? [] { checks.append(CheckEvaluator.evaluate(c, inputs)) }
        if !bootMs.isEmpty {
            let mean = bootMs.reduce(0, +) / Double(bootMs.count)
            checks.append(CheckResult(type: "boot_time", name: "boot_time", pass: true, severity: "info",
                                      summary: String(format: "%d boots, mean %.0f ms, slowest %.0f ms", bootMs.count, mean, bootMs.max() ?? 0),
                                      values: ["boots": Double(bootMs.count), "meanMs": mean, "maxMs": bootMs.max() ?? 0]))
        }

        let slice = logs.slice(from: startIdx, to: endIdx)
        var anomalies = detector.scan(log: slice, testId: test.id)
        anomalies += AnomalyDetector.scan(before: before, after: after, samples: m.samples, testId: test.id)
        let (result, reason) = Judge.verdict(test: test, expectations: [], checks: checks, script: [], answers: [],
                                             anomalies: anomalies.filter { $0.severity == "fail" }, guestResult: "ok", guestErrors: 0,
                                             guestMessage: "", errorReason: failure)
        let fileRel = "logs/\(test.id)-\(item.iteration)-\(token).txt"
        try? ReportWriter.writeLogSlice(slice, to: reportDir.appendingPathComponent(fileRel))
        let foot = m.footprintsMB
        let params = test.host?.params?.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ";") ?? ""
        let perf = PerformanceRecord(frameIntervals: nil, reportedFps: 0, guestFrames: 0, footprintStartMB: foot.first ?? 0, footprintEndMB: foot.last ?? 0,
                                     footprintPeakMB: foot.max() ?? 0, availableMinMB: m.availableMB.min() ?? 0, snapshotSamples: m.samples.count,
                                     videoStallSeen: false, thermalStateEnd: Platform.thermalStateName(), perfLine: core.perfLine)
        var delta: JSONValue?
        if let a = after, let b = before { delta = a.delta(from: b) }
        return TestRecord(
            id: test.id, title: test.title, suite: item.suite.suite, subsystems: test.subsystems, runIndex: records.count, iteration: item.iteration,
            token: token, result: result, reason: reason, configuration: configuration(item, params: params),
            stimulus: test.stimulus, expected: test.expected, startedAt: Self.iso(startDate), endedAt: Self.iso(endDate),
            startNs: startNs, endNs: endNs, durationMs: endDate.timeIntervalSince(startDate) * 1000.0,
            path: path, checkpoints: [], checks: checks, scriptSteps: [], answers: [], userFlags: [],
            performance: perf, snapshotBefore: before, snapshotAfter: after, snapshotDelta: delta,
            logSlice: LogSlice(startNs: startNs, endNs: endNs, lineCount: slice.count, droppedLines: logs.droppedTotal - startDropped,
                               truncated: slice.count > 400, file: fileRel, lines: Array(slice.suffix(400))),
            anomalies: anomalies, guestResult: failure == nil ? "ok" : "error", guestChecksum: "", reproduction: reproduction(item, params: params))
    }
}
