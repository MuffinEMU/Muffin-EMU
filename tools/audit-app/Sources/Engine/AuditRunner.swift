//
//  AuditRunner.swift
//  Runs a plan of tests against the core and builds the report. One runner per run.
//
//  The shape of a guest test:
//    1. make sure the guest (audit.rpx) is up and its mailbox is attached
//    2. tag the log, reset the counters, take a "before" snapshot
//    3. send RUN, then watch: the mailbox (state, checkpoints), the log (probe lines and everything
//       else), periodic state snapshots, frame-pacing timestamps
//    4. at each CHECKPOINT: read the frame(s) back, judge them against the catalogue, answer CONTINUE
//    5. when the guest reports the test finished: take the "after" snapshot, judge the whole-test
//       checks, scan the log and counters for anomalies, ask the questionnaire
//    6. one TestRecord, written to the report straight away, so a run that dies half way still has a report
//
import Foundation

final class AuditRunner {
    let core = CoreDriver.shared
    let link = GuestLink()
    let logs = LogCapture()
    let catalogue: Catalogue
    let detector: AnomalyDetector
    let catalogueHash: String
    let request: RunRequest
    weak var host: RunnerHost?
    let rpxPath: String
    let reportDir: URL

    var records: [TestRecord] = []
    var runAnomalies: [Anomaly] = []
    var notes: [String] = []
    var orientation: Orientation = .normal
    var orientationKnown = false
    var captureAvailable = false
    var nextToken: UInt32 = 1
    var guestUp = false
    var helloAddress: UInt32?
    var helloBuild = ""
    var probeEvents: [(ProbeEvent, UInt64)] = []
    var caps: CoreCapabilities?
    var bootCount = 0
    var surfaceInfo: SurfaceInfo?

    init(catalogue: Catalogue, detector: AnomalyDetector, catalogueHash: String, request: RunRequest, host: RunnerHost,
         rpxPath: String, reportDir: URL) {
        self.catalogue = catalogue
        self.detector = detector
        self.catalogueHash = catalogueHash
        self.request = request
        self.host = host
        self.rpxPath = rpxPath
        self.reportDir = reportDir
        logs.onProbe = { [weak self] event, ns in self?.probeEvents.append((event, ns)) }
    }

    var cancelled: Bool { host?.isCancelled ?? true }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func nowIso() -> String { iso(Date()) }

    // MARK: Whole run

    /// Runs everything and returns the report folder. Never throws: whatever goes wrong is in the report.
    func run() async -> URL {
        let started = Date()
        let startNs = core.nowNs
        Platform.setIdleTimerDisabled(true)
        defer { Platform.setIdleTimerDisabled(false) }

        let capabilities = core.captureCapabilities()
        caps = capabilities
        var coreError: String?
        do { try core.initializeCore(logProfile: request.logProfile) } catch { coreError = "\(error)" }
        captureAvailable = coreError == nil && request.renderer == "metal"
        if coreError == nil { notes.append("The core's crash log (memory samples and, after an abrupt end, the last milestones) is at \(core.crashLogPath).") }
        if request.renderer != "metal" {
            notes.append("Frame readback is implemented for the Metal renderer only; with \(request.renderer) every frame-based expectation is reported as inconclusive and only logs, counters, audio, input and the questionnaire judge the run.")
        }
        if !core.jitPermitted && request.cpu == "recompiler" {
            notes.append("The recompiler was requested but this process is not allowed to run generated code (no JIT enabler attached); the interpreter ran instead.")
        }

        var planner = Planner(catalogue: catalogue, request: request, deviceTier: capabilities.tier)
        var index = 0
        while let item = planner.next(now: Date(), started: started) {
            if cancelled { notes.append("The run was cancelled after \(records.count) test(s)."); break }
            host?.progress(done: index, total: planner.estimatedTotal, current: item.test.title)
            host?.status("Running \(item.test.id)...")

            let rec: TestRecord
            if let ce = coreError {
                rec = skeleton(item, result: .error, reason: "the core did not start: \(ce)")
            } else if let why = skipReason(item.test) {
                rec = skeleton(item, result: .skip, reason: why)
            } else if item.test.kind == "host" {
                rec = await runHostAction(item)
            } else {
                rec = await runGuestTest(item)
            }
            records.append(rec)
            host?.record(ResultRow(id: rec.id + (rec.iteration > 0 ? " #\(rec.iteration + 1)" : ""), title: rec.title, result: rec.result, reason: rec.reason))
            writeReport(started: started, startNs: startNs, complete: false)
            index += 1
        }

        await stopGuest()
        let complete = !cancelled && coreError == nil
        let folder = writeReport(started: started, startNs: startNs, complete: complete)
        host?.status(complete ? "Finished. Report saved." : "Stopped. Partial report saved.")
        return folder
    }

    // MARK: Plan

    func skipReason(_ t: TestDef) -> String? {
        guard let caps = caps else { return nil }
        if let r = t.requires {
            if let tier = r.minTier, caps.tier < tier { return "needs a device of tier \(tier) or higher (this one is tier \(caps.tier))" }
            if let apis = r.apis, !apis.contains(request.renderer) { return "runs only with the \(apis.joined(separator: " or ")) renderer (this run uses \(request.renderer))" }
            if r.pad == true && !request.padSurface { return "needs the GamePad surface, which this run has off" }
            if r.attended == true && !request.attended { return "needs a person to watch or listen; this run is unattended" }
        }
        if t.kind == "guest" && t.guest == nil { return "the catalogue entry has no guest section" }
        return nil
    }

    // MARK: Skeleton record

    func skeleton(_ item: PlannedTest, result: TestResult, reason: String) -> TestRecord {
        let t = item.test
        let now = core.nowNs
        let date = Self.nowIso()
        let params = t.guest?.paramString(overrides: item.paramOverrides) ?? ""
        return TestRecord(
            id: t.id, title: t.title, suite: item.suite.suite, subsystems: t.subsystems, runIndex: records.count, iteration: item.iteration,
            token: 0, result: result, reason: reason,
            configuration: configuration(item, params: params),
            stimulus: t.stimulus, expected: t.expected, startedAt: date, endedAt: date, startNs: now, endNs: now, durationMs: 0,
            path: [], checkpoints: [], checks: [], scriptSteps: [], answers: [], userFlags: [],
            performance: PerformanceRecord(frameIntervals: nil, reportedFps: 0, guestFrames: 0, footprintStartMB: 0, footprintEndMB: 0, footprintPeakMB: 0,
                                           availableMinMB: 0, snapshotSamples: 0, videoStallSeen: false, thermalStateEnd: Platform.thermalStateName(), perfLine: ""),
            snapshotBefore: nil, snapshotAfter: nil, snapshotDelta: nil,
            logSlice: LogSlice(startNs: now, endNs: now, lineCount: 0, droppedLines: 0, truncated: false, file: "", lines: []),
            anomalies: [], guestResult: "none", guestChecksum: "",
            reproduction: reproduction(item, params: params))
    }

    func configuration(_ item: PlannedTest, params: String) -> TestConfiguration {
        TestConfiguration(kind: item.test.kind, guestTest: item.test.guest?.test ?? item.test.host?.action ?? "",
                          guestParams: params, seed: item.seed, durationMs: item.test.guest?.durationMs ?? 0,
                          renderer: request.renderer, padSurface: request.padSurface, cpuMode: core.cpuModeName)
    }

    func reproduction(_ item: PlannedTest, params: String) -> Reproduction {
        let t = item.test
        let guest = t.guest?.test ?? ""
        let outside = (t.reproduce.map { $0 + " " } ?? "")
            + "Load audit.rpx (the `audit-rpx` artifact of the audit workflow run) in MuffinEMU or any other Wii U emulator. With no Audit app attached it plays its built-in sequence after 8 seconds and logs every step as `MUFFINAUDIT` lines; \(guest.isEmpty ? "this test is driven by the app itself" : "the `\(guest)` test is part of that sequence")."
        let command = guest.isEmpty ? "host action \(t.host?.action ?? "")" : "mailbox RUN test=\(guest) params=\"\(params)\" seed=\(item.seed)"
        return Reproduction(seed: item.seed, params: params, guestTest: guest, outsideTool: outside, command: command)
    }

    // MARK: Report

    @discardableResult
    func writeReport(started: Date, startNs: UInt64, complete: Bool) -> URL {
        let caps = self.caps
        let s = Platform.screen
        let device = DeviceInfo(machine: caps?.machine.isEmpty == false ? caps!.machine : Platform.machine,
                                systemName: Platform.systemName, systemVersion: Platform.systemVersion,
                                deviceReport: core.initialized ? core.deviceReport : "", capsLine: caps?.line ?? "",
                                chip: caps?.chip ?? "", tier: caps?.tier ?? 0, appleGpuFamily: caps?.appleGpuFamily ?? 0,
                                bcTextures: caps?.bcTextures ?? false, metal3: caps?.metal3 ?? false,
                                physicalMemoryMB: caps?.physicalMemoryMB ?? 0, logicalCores: caps?.logicalCores ?? 0,
                                isPad: s.isPad, screenPoints: [s.shortPoints, s.longPoints], screenScale: s.scale,
                                thermalStateAtStart: thermalAtStart, lowPowerMode: Platform.lowPowerMode, jitPermitted: core.jitPermitted)
        let config = RunConfig(mode: request.mode, suites: request.suiteIds, testIds: request.testIds, seed: request.seed,
                               renderer: request.renderer, padSurface: request.padSurface, cpu: request.cpu,
                               cpuModeReported: core.initialized ? core.cpuModeName : "unknown", coresRunning: core.initialized ? core.coresRunning : 0,
                               attended: request.attended, repeatCount: request.repeatCount, soakMinutes: request.soakMinutes,
                               logProfile: request.logProfile, captureAvailable: captureAvailable,
                               graphicsApiReported: core.initialized ? core.graphicsApiName : "unknown")
        let allAnomalies = runAnomalies + records.flatMap { $0.anomalies }
        let duration = Double(core.nowNs &- startNs) / 1_000_000_000.0
        let summary = Judge.summary(tests: records, anomalies: allAnomalies, durationSec: duration, complete: complete)
        let findings = Judge.findings(from: records) { $0.reproduction.outsideTool }
        let report = AuditReport(
            reportId: reportDir.lastPathComponent, createdAt: Self.iso(started), finishedAt: complete ? Self.nowIso() : nil,
            tool: ToolInfo(name: "MuffinEMU Audit", version: BuildInfo.appVersion, probeProtocol: Int(Mailbox.protocolVersion),
                           hooksApi: core.initialized ? core.hooksVersion : 0, catalogueHash: catalogueHash,
                           catalogueSuites: catalogue.suites.map { $0.suite }),
            build: BuildInfo.identity(hooksInfo: core.initialized ? core.hooksBuildInfo : ""),
            device: device, config: config, summary: summary, findings: findings, tests: records,
            anomalies: allAnomalies, notes: notes)
        do { try ReportWriter.write(report, to: reportDir) } catch { host?.status("Could not write the report: \(error)") }
        return reportDir
    }

    lazy var thermalAtStart: String = Platform.thermalStateName()
}
