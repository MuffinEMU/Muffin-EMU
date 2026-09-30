//
//  Report.swift
//  The report, as data. These types are the JSON the app writes (report.json); the JSON Schema in
//  tools/audit-app/schema/report.schema.json describes the same shape and CI validates a report
//  written by these types against it, so the two cannot drift apart silently.
//
//  Times: every `tNs` is nanoseconds on the core's monotonic clock (cemu_audit_now_ns), the one clock
//  the log, frames, snapshots and answers all share. Wall-clock times are ISO 8601 strings.
//
import Foundation

enum TestResult: String, Codable {
    case pass
    case fail
    case skip
    case error
}

struct AuditReport: Codable {
    var schema: String = "muffinaudit.report/1"
    var reportId: String
    var createdAt: String
    var finishedAt: String?
    var tool: ToolInfo
    var build: BuildIdentity
    var device: DeviceInfo
    var config: RunConfig
    var summary: ReportSummary
    /// One entry per test that did not pass cleanly, written so a reader can say "test X failed, the user
    /// reported Y, and these logs occurred on this path".
    var findings: [Finding]
    var tests: [TestRecord]
    var anomalies: [Anomaly]
    var notes: [String]
}

struct ToolInfo: Codable {
    var name: String
    var version: String
    var probeProtocol: Int
    var hooksApi: Int
    var catalogueHash: String
    var catalogueSuites: [String]
}

struct BuildIdentity: Codable {
    /// The MuffinEMU ref the workflow was asked to test (branch, tag or sha) and the commit it resolved to.
    var muffinRef: String
    var muffinSha: String
    var muffinVersion: String
    var coreFingerprint: String
    /// JSON the core reports about how its audit hooks were compiled.
    var hooksBuildInfo: String
    var auditAppVersion: String
    var auditAppBuild: String
    var auditToolsSha: String
    var guestBuild: String
    var workflowRun: String
    var builtAt: String
}

struct DeviceInfo: Codable {
    var machine: String
    var systemName: String
    var systemVersion: String
    /// The core's one-line device report and its capabilities line, verbatim.
    var deviceReport: String
    var capsLine: String
    var chip: String
    var tier: Int
    var appleGpuFamily: Int
    var bcTextures: Bool
    var metal3: Bool
    var physicalMemoryMB: Int
    var logicalCores: Int
    var isPad: Bool
    var screenPoints: [Double]
    var screenScale: Double
    var thermalStateAtStart: String
    var lowPowerMode: Bool
    var jitPermitted: Bool
}

struct RunConfig: Codable {
    var mode: String
    var suites: [String]
    var testIds: [String]
    var seed: UInt32
    var renderer: String
    var padSurface: Bool
    var cpu: String
    var cpuModeReported: String
    var coresRunning: Int
    var attended: Bool
    var repeatCount: Int
    var soakMinutes: Int
    var logProfile: Int
    var captureAvailable: Bool
    var graphicsApiReported: String
}

struct ReportSummary: Codable {
    var verdict: String
    var counts: [String: Int]
    var totalTests: Int
    var durationSec: Double
    var affectedSubsystems: [SubsystemSummary]
    var anomalyCounts: [String: Int]
}

struct SubsystemSummary: Codable {
    var subsystem: String
    var failedTests: [String]
    var anomalies: Int
}

struct Finding: Codable {
    var testId: String
    var title: String
    var result: TestResult
    var reason: String
    /// The finding in one sentence, for a reader who is not going to open the rest.
    var sentence: String
    var subsystems: [String]
    var failedExpectations: [String]
    var failedChecks: [String]
    var userReported: [UserReport]
    var logHighlights: [LogLine]
    var path: [String]
    var reproduce: String
}

struct UserReport: Codable {
    var question: String
    var answer: String
    var tNs: UInt64
}

struct LogLine: Codable {
    var tNs: UInt64
    /// The core's own "+seconds since launch" stamp, when the line carried one.
    var coreElapsed: Double?
    var text: String
    /// "guest" for MUFFINAUDIT probe lines, "host" for lines the app wrote, nil for the core's own output.
    var tag: String?
}

struct TestRecord: Codable {
    var id: String
    var title: String
    var suite: String
    var subsystems: [String]
    var runIndex: Int
    var iteration: Int
    var token: UInt32
    var result: TestResult
    var reason: String
    var configuration: TestConfiguration
    var stimulus: String
    var expected: String
    var startedAt: String
    var endedAt: String
    var startNs: UInt64
    var endNs: UInt64
    var durationMs: Double
    /// Probe markers in the order they happened: what the guest was doing when.
    var path: [PathStep]
    var checkpoints: [CheckpointRecord]
    var checks: [CheckResult]
    var scriptSteps: [ScriptResult]
    var answers: [AnswerRecord]
    var userFlags: [UserFlag]
    var performance: PerformanceRecord
    var snapshotBefore: JSONValue?
    var snapshotAfter: JSONValue?
    var snapshotDelta: JSONValue?
    var logSlice: LogSlice
    var anomalies: [Anomaly]
    var guestResult: String
    var guestChecksum: String
    var reproduction: Reproduction
}

struct TestConfiguration: Codable {
    var kind: String
    var guestTest: String
    var guestParams: String
    var seed: UInt32
    var durationMs: Int
    var renderer: String
    var padSurface: Bool
    var cpuMode: String
}

struct PathStep: Codable {
    var tNs: UInt64
    var kind: String
    var name: String
}

struct CheckpointRecord: Codable {
    var name: String
    var tNs: UInt64
    var guestFrame: UInt32
    var frames: [FrameRecord]
    var expectations: [ExpectationResult]
    /// Files under the report folder (thumbnails of the captured frames, kept when something failed).
    var thumbnailFiles: [String]
}

struct FrameRecord: Codable {
    var seq: UInt32
    var view: String
    var status: String
    var latteFrame: UInt32
    var tNs: UInt64
    var width: Int
    var height: Int
    var pixelFormat: Int
    var meanRGB: [Double]
    var blackFraction: Double
    var whiteFraction: Double
    var minLuma: Int
    var maxLuma: Int
    var hash: String
}

struct ExpectationResult: Codable {
    var type: String
    var name: String
    var pass: Bool
    var severity: String
    var expected: String
    var measured: String
    var values: [String: Double]
}

struct CheckResult: Codable {
    var type: String
    var name: String
    var pass: Bool
    var severity: String
    var summary: String
    var values: [String: Double]
}

struct ScriptResult: Codable {
    var label: String
    var action: String
    var pass: Bool
    var severity: String
    var expected: String
    var measured: String
    var tNs: UInt64
}

struct AnswerRecord: Codable {
    var questionId: String
    var question: String
    var type: String
    var answer: String
    var bad: Bool
    var severity: String
    var subsystem: String
    var answeredAt: String
    var tNs: UInt64
    var testId: String
    var runToken: UInt32
    /// The log lines either side of the moment the question was answered.
    var logContext: [LogLine]
}

struct UserFlag: Codable {
    var tNs: UInt64
    var at: String
    var note: String
    var logContext: [LogLine]
}

struct PerformanceRecord: Codable {
    var frameIntervals: FramePacingStats?
    var reportedFps: Double
    var guestFrames: Int
    var footprintStartMB: Double
    var footprintEndMB: Double
    var footprintPeakMB: Double
    var availableMinMB: Double
    var snapshotSamples: Int
    var videoStallSeen: Bool
    var thermalStateEnd: String
    var perfLine: String
}

struct FramePacingStats: Codable {
    var count: Int
    var meanMs: Double
    var p50Ms: Double
    var p95Ms: Double
    var p99Ms: Double
    var maxMs: Double
    var stdDevMs: Double
    var fps: Double
    /// Intervals longer than 1.5x and 2.5x the median.
    var long: Int
    var veryLong: Int
    var dropped: Int
}

struct LogSlice: Codable {
    var startNs: UInt64
    var endNs: UInt64
    var lineCount: Int
    var droppedLines: Int
    /// True when `lines` holds only part of the slice; the whole slice is in `file`.
    var truncated: Bool
    var file: String
    var lines: [LogLine]
}

struct Anomaly: Codable {
    var id: String
    var kind: String
    var severity: String
    var subsystem: String
    var testId: String?
    var tNs: UInt64?
    var message: String
    var evidence: [String]
}

struct Reproduction: Codable {
    var seed: UInt32
    var params: String
    var guestTest: String
    /// How to get the same frames outside this tool.
    var outsideTool: String
    /// The probe commands that start exactly this test.
    var command: String
}
