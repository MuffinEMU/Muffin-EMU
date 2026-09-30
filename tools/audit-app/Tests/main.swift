//
//  main.swift (Tests)
//  Unit tests for the audit app's pure logic: catalogue parsing, frame analysis, orientation, frame
//  counters, pacing, anomaly detection, verdicts, probe-line parsing and the report writer. Built and
//  run on a Mac by the workflow's "checks" job (tools/audit-app/run-logic-tests.sh) with no iOS SDK
//  and no core.
//
import Foundation

var failures = 0
var checks = 0

func check(_ cond: @autoclosure () -> Bool, _ what: String, line: Int = #line) {
    checks += 1
    if !cond() {
        failures += 1
        print("FAIL (line \(line)): \(what)")
    }
}

// MARK: helpers

func solidFrame(_ r: UInt8, _ g: UInt8, _ b: UInt8, w: Int = 128, h: Int = 72, seq: UInt32 = 1) -> CapturedFrame {
    var f = CapturedFrame()
    f.seq = seq; f.thumbWidth = w; f.thumbHeight = h; f.srcWidth = 1280; f.srcHeight = 720
    f.thumb = [UInt8](repeating: 0, count: w * h * 3)
    for i in 0..<(w * h) { f.thumb[i * 3] = r; f.thumb[i * 3 + 1] = g; f.thumb[i * 3 + 2] = b }
    f.meanR = Double(r); f.meanG = Double(g); f.meanB = Double(b)
    f.hash = UInt64(r) << 16 | UInt64(g) << 8 | UInt64(b)
    return f
}

func fill(_ f: inout CapturedFrame, rect: [Double], _ rgb: (UInt8, UInt8, UInt8)) {
    let x0 = Int(rect[0] * Double(f.thumbWidth)), x1 = Int((rect[0] + rect[2]) * Double(f.thumbWidth))
    let y0 = Int(rect[1] * Double(f.thumbHeight)), y1 = Int((rect[1] + rect[3]) * Double(f.thumbHeight))
    for y in y0..<min(y1, f.thumbHeight) {
        for x in x0..<min(x1, f.thumbWidth) {
            let i = (y * f.thumbWidth + x) * 3
            f.thumb[i] = rgb.0; f.thumb[i + 1] = rgb.1; f.thumb[i + 2] = rgb.2
        }
    }
}

func orientationFrame(flipY: Bool) -> CapturedFrame {
    var f = solidFrame(20, 20, 20)
    func y(_ v: Double) -> Double { flipY ? 1 - v - 0.10 : v }
    fill(&f, rect: [0.85, y(0.05), 0.10, 0.10], (255, 0, 0))
    fill(&f, rect: [0.05, y(0.85), 0.10, 0.10], (0, 255, 0))
    fill(&f, rect: [0.05, y(0.05), 0.10, 0.10], (0, 0, 255))
    fill(&f, rect: [0.85, y(0.85), 0.10, 0.10], (255, 255, 255))
    return f
}

func counterFrame(top: Int, bottom: Int, seq: UInt32, latte: UInt32) -> CapturedFrame {
    var f = solidFrame(15, 15, 15, seq: seq)
    f.latteFrame = latte
    for bit in 0..<16 {
        let x = Double(bit) / 16.0
        let t: UInt8 = (top >> bit) & 1 == 1 ? 255 : 0
        let b: UInt8 = (bottom >> bit) & 1 == 1 ? 255 : 0
        fill(&f, rect: [x, 0, 1.0 / 16.0, 0.07], (t, t, t))
        fill(&f, rect: [x, 0.93, 1.0 / 16.0, 0.07], (b, b, b))
    }
    return f
}

// MARK: JSONValue

do {
    let a = JSONValue.parse(#"{"a":{"n":10,"s":"x","b":true},"m":5}"#)!
    let b = JSONValue.parse(#"{"a":{"n":4,"s":"x","b":false},"m":1}"#)!
    let d = a.delta(from: b)
    check(d.path("a.n")?.double == 6, "delta subtracts numbers")
    check(d.path("m")?.int == 4, "delta subtracts top-level numbers")
    check(d.path("a.b")?.bool == true, "delta keeps booleans from the newer side")
    check(a.path("a.s")?.string == "x", "path lookup")
    check(a.path("a.zzz") == nil, "missing path is nil")
}

// MARK: Catalogue

do {
    let suite = """
    {"schema":"muffinaudit.suite/1","suite":"t","title":"T","order":5,"tests":[
      {"id":"t.one","title":"One","subsystems":["render.clear"],"kind":"guest",
       "guest":{"test":"clear_colours","params":{"b":"2","a":"1"}},"stimulus":"s","expected":"e",
       "checkpoints":[{"name":"clear_*","expect":[{"type":"region_color","rect":[0,0,1,1],"rgb":[255,0,0],"tol":6}]}],
       "questionnaire":[{"id":"q","text":"ok?","type":"yesno","bad":"no"}]}]}
    """
    let cat = try Catalogue.load(files: [("t.json", suite.data(using: .utf8)!)])
    check(cat.suites.count == 1 && cat.allTests.count == 1, "one suite, one test")
    let t = cat.test(id: "t.one")!.test
    check(t.guest?.paramString() == "a=1;b=2", "params are sorted and joined")
    check(t.guest?.paramString(overrides: ["a": "9"]) == "a=9;b=2", "overrides win")
    check(t.checkpoints?[0].matches("clear_3") == true, "wildcard checkpoint matches")
    check(t.checkpoints?[0].matches("other") == false, "wildcard checkpoint rejects")
    check(cat.contentHash(rawFiles: [suite.data(using: .utf8)!]).count == 16, "content hash is 16 hex digits")

    let bad = suite.replacingOccurrences(of: "muffinaudit.suite/1", with: "nope")
    do { _ = try Catalogue.load(files: [("b.json", bad.data(using: .utf8)!)]); check(false, "wrong schema must throw") } catch { check(true, "wrong schema throws") }
    do { _ = try Catalogue.load(files: [("a.json", suite.data(using: .utf8)!), ("b.json", suite.data(using: .utf8)!)]); check(false, "duplicate id must throw") } catch { check(true, "duplicate id throws") }
}

// MARK: Frame analysis

do {
    var exp = Expectation(type: "region_color")
    exp.rect = [0.25, 0.25, 0.5, 0.5]; exp.rgb = [255, 0, 0]; exp.tol = 6
    let red = solidFrame(255, 0, 0)
    check(FrameAnalysis.evaluate(exp, frames: [red], orientation: .normal).pass, "red frame passes a red region")
    check(!FrameAnalysis.evaluate(exp, frames: [solidFrame(0, 0, 0)], orientation: .normal).pass, "black frame fails a red region")
    check(!FrameAnalysis.evaluate(exp, frames: [solidFrame(240, 0, 0)], orientation: .normal).pass, "off by 15 fails tolerance 6")

    // Inconclusive when nothing usable was captured: a warning, never a pass and never a rendering fail.
    var unsupported = CapturedFrame(); unsupported.status = 1; unsupported.pixelFormat = 115
    let inc = FrameAnalysis.evaluate(exp, frames: [unsupported], orientation: .normal)
    check(!inc.pass && inc.severity == "warn" && inc.values["inconclusive"] == 1, "unreadable frame is inconclusive")
    let none = FrameAnalysis.evaluate(exp, frames: [], orientation: .normal)
    check(!none.pass && none.severity == "warn", "no frame is inconclusive")

    // Quadrants, with one not asserted.
    var f = solidFrame(0, 0, 0)
    fill(&f, rect: [0, 0, 0.5, 0.5], (255, 0, 0)); fill(&f, rect: [0.5, 0, 0.5, 0.5], (0, 255, 0))
    fill(&f, rect: [0, 0.5, 0.5, 0.5], (0, 0, 255)); fill(&f, rect: [0.5, 0.5, 0.5, 0.5], (255, 255, 0))
    var q = Expectation(type: "quadrants")
    q.rect = [0, 0, 1, 1]; q.tl = [255, 0, 0]; q.tr = [0, 255, 0]; q.bl = [0, 0, 255]; q.br = [255, 255, 0]; q.tol = 8
    check(FrameAnalysis.evaluate(q, frames: [f], orientation: .normal).pass, "quadrants match")
    var swapped = q; swapped.tl = [0, 255, 0]
    let sr = FrameAnalysis.evaluate(swapped, frames: [f], orientation: .normal)
    check(!sr.pass && sr.measured.contains("tl"), "a wrong quadrant names itself")
    var dontCare = q; dontCare.br = nil; dontCare.bl = nil
    check(FrameAnalysis.evaluate(dontCare, frames: [f], orientation: .normal).pass, "null quadrants are not asserted")

    // Not black.
    var nb = Expectation(type: "not_black"); nb.maxBlackFraction = 0.3
    check(!FrameAnalysis.evaluate(nb, frames: [solidFrame(0, 0, 0)], orientation: .normal).pass, "black frame is black")
    check(FrameAnalysis.evaluate(nb, frames: [f], orientation: .normal).pass, "coloured frame is not black")

    // Orientation detection and mapping.
    let (o1, c1) = FrameAnalysis.detectOrientation(orientationFrame(flipY: false))!
    check(o1 == .normal && c1 > 120, "normal orientation detected")
    let (o2, c2) = FrameAnalysis.detectOrientation(orientationFrame(flipY: true))!
    check(o2 == .flippedVertically && c2 > 120, "vertical flip detected")
    let (_, cBlank) = FrameAnalysis.detectOrientation(solidFrame(40, 40, 40))!
    check(cBlank < 120, "a blank frame gives no clear orientation")
    let m = Orientation.flippedVertically.map(rect: [0.1, 0.2, 0.3, 0.1])
    check(abs(m[1] - 0.7) < 1e-9 && abs(m[3] - 0.1) < 1e-9, "rect maps through a vertical flip")
    // With a flipped screen, expectations written for the guest's space still pass once mapped.
    var flipped = solidFrame(0, 0, 0)
    fill(&flipped, rect: [0, 0.5, 1, 0.5], (255, 0, 0)) // guest drew red in its top half; it landed at the bottom
    var top = Expectation(type: "region_color"); top.rect = [0, 0, 1, 0.5]; top.rgb = [255, 0, 0]
    check(FrameAnalysis.evaluate(top, frames: [flipped], orientation: .flippedVertically).pass, "flip-aware region passes")
    check(!FrameAnalysis.evaluate(top, frames: [flipped], orientation: .normal).pass, "without the flip it fails")

    // Burst: identical frames.
    var ident = Expectation(type: "frames_identical"); ident.maxDistinct = 1
    check(FrameAnalysis.evaluate(ident, frames: [solidFrame(9, 9, 9, seq: 1), solidFrame(9, 9, 9, seq: 2)], orientation: .normal).pass, "identical frames pass")
    var flick = solidFrame(9, 9, 9, seq: 2); flick.hash = 77; flick.thumb[3] = 200
    let fr = FrameAnalysis.evaluate(ident, frames: [solidFrame(9, 9, 9, seq: 1), flick], orientation: .normal)
    check(!fr.pass && fr.values["distinct"] == 2, "a changed frame is flicker")
    check(FrameAnalysis.evaluate(ident, frames: [solidFrame(9, 9, 9)], orientation: .normal).severity == "warn", "one frame cannot prove stability")

    // Frame counters: decode, tear, ordering.
    check(FrameAnalysis.decodeCounter(counterFrame(top: 0x1234, bottom: 0x1234, seq: 1, latte: 1), bottom: false, orientation: .normal) == 0x1234, "counter decodes (top)")
    check(FrameAnalysis.decodeCounter(counterFrame(top: 0x1234, bottom: 0xABCD, seq: 1, latte: 1), bottom: true, orientation: .normal) == 0xABCD, "counter decodes (bottom)")
    var fc = Expectation(type: "frame_counter")
    var clean: [CapturedFrame] = []
    for i in 0..<6 {
        let counter: Int = 100 + i * 2
        clean.append(counterFrame(top: counter, bottom: counter, seq: UInt32(i + 1), latte: UInt32(50 + i * 2)))
    }
    check(FrameAnalysis.evaluate(fc, frames: clean, orientation: .normal).pass, "a clean, increasing burst passes")
    var torn = clean; torn[3] = counterFrame(top: 106, bottom: 104, seq: 4, latte: 56)
    let tr = FrameAnalysis.evaluate(fc, frames: torn, orientation: .normal)
    check(!tr.pass && tr.values["torn"] == 1, "a torn frame is reported")
    var back = clean; back[4] = counterFrame(top: 100, bottom: 100, seq: 5, latte: 58)
    check(FrameAnalysis.evaluate(fc, frames: back, orientation: .normal).values["backwards"] ?? 0 >= 1, "a backwards frame is reported")
    fc.maxTornFraction = 0.5
    check(FrameAnalysis.evaluate(fc, frames: torn, orientation: .normal).pass, "tear tolerance is honoured")
    check(FrameAnalysis.decodeCounter(solidFrame(128, 128, 128), bottom: false, orientation: .normal) == nil, "grey is not a readable counter")
}

// MARK: Pacing

do {
    var steady: [UInt64] = []
    for i in 0..<200 { steady.append(UInt64(i) * 16_666_667) }
    let s = Pacing.stats(intervalsMs: Pacing.intervalsMs(steady), dropped: 0)!
    check(abs(s.fps - 60.0) < 0.1 && s.long == 0, "steady 60 fps")
    var stutter = steady
    stutter[100] += 40_000_000 // one 57 ms frame
    for i in 101..<stutter.count { stutter[i] += 40_000_000 }
    let st = Pacing.stats(intervalsMs: Pacing.intervalsMs(stutter), dropped: 3)!
    check(st.veryLong == 1 && st.maxMs > 50 && st.dropped == 3, "a hitch is counted")
    check(Pacing.stats(intervalsMs: [], dropped: 0) == nil, "no intervals, no stats")
    check(Pacing.percentile([1, 2, 3, 4, 5], 0.5) == 3, "median")
}

// MARK: Checks

do {
    let start = JSONValue.parse(#"{"frames":0,"validFrames":0,"underrunFrames":0,"discontinuities":0,"rms":0,"peak":0}"#)!
    let good = JSONValue.parse(#"{"frames":96000,"validFrames":96000,"underrunFrames":0,"discontinuities":0,"rms":0.25,"peak":12000}"#)!
    let bad = JSONValue.parse(#"{"frames":96000,"validFrames":90000,"underrunFrames":6000,"discontinuities":9,"rms":0.25,"peak":12000}"#)!
    var c = CheckDef(type: "audio_window"); c.step = 1; c.minRms = 0.05; c.maxUnderrunFrames = 0; c.maxDiscontinuities = 0
    var inp = CheckInputs(); inp.audioWindows[1] = (start, good)
    check(CheckEvaluator.evaluate(c, inp).pass, "clean audio passes")
    inp.audioWindows[1] = (start, bad)
    let br = CheckEvaluator.evaluate(c, inp)
    check(!br.pass && br.summary.contains("underrun") == false && br.summary.contains("silence padded"), "underruns are named")
    check(br.summary.contains("clicks"), "clicks are named")
    inp.audioWindows = [:]
    check(CheckEvaluator.evaluate(c, inp).severity == "warn", "a missing window is inconclusive")
    var mg = CheckDef(type: "memory_growth"); mg.maxGrowthMB = 50
    var mi = CheckInputs(); mi.footprintGrowthMB = 120; mi.footprintSamples = 40
    check(!CheckEvaluator.evaluate(mg, mi).pass, "growth above the limit fails")
    mi.footprintGrowthMB = 10
    check(CheckEvaluator.evaluate(mg, mi).pass, "growth below the limit passes")
}

// MARK: Anomalies

do {
    let det = AnomalyDetector(patterns: [
        AnomalyPattern(id: "drawable", contains: "failed to acquire next drawable", severity: "fail", subsystem: "render.present", message: "Drawable acquisition failed.", ignoreProbeLines: nil),
    ])
    let lines = [
        LogLine(tNs: 10, coreElapsed: nil, text: "layer 0x1 failed to acquire next drawable", tag: nil),
        LogLine(tNs: 11, coreElapsed: nil, text: "MUFFINAUDIT NOTE x 1 failed to acquire next drawable", tag: "guest"),
        LogLine(tNs: 12, coreElapsed: nil, text: "all fine", tag: nil),
    ]
    let found = det.scan(log: lines, testId: "t")
    check(found.count == 1 && found[0].evidence.count == 1, "probe lines are ignored by log patterns")

    let before = JSONValue.parse(#"{"tNs":1,"gpuThread":{"drawableFailures":1,"erroredCommandBuffers":0,"gpuError":false},"gpuMemory":{"texturesEvicted":0},"perf":{"pipelineSyncCompiles":0},"audio":{"underrunCallbacks":0,"underrunFrames":0,"feedRejects":0},"memory":{"availableBytes":1000000000,"footprintBytes":500000000}}"#)!
    let after = JSONValue.parse(#"{"tNs":2,"gpuThread":{"drawableFailures":4,"erroredCommandBuffers":2,"gpuError":true,"gpuErrorCode":14,"cbLastErrorCode":14},"gpuMemory":{"texturesEvicted":30},"perf":{"pipelineSyncCompiles":9},"audio":{"underrunCallbacks":3,"underrunFrames":1200,"feedRejects":0},"memory":{"availableBytes":150000000,"footprintBytes":900000000}}"#)!
    let an = AnomalyDetector.scan(before: before, after: after, samples: [after], testId: "t")
    let ids = Set(an.map { $0.id })
    check(ids.contains("counter.gpu_error") && ids.contains("counter.drawable_failures") && ids.contains("counter.errored_command_buffers"), "counter anomalies found")
    check(ids.contains("counter.textures_evicted") && ids.contains("counter.audio_underruns") && ids.contains("counter.low_memory"), "eviction, audio and memory anomalies found")
    check(an.first { $0.id == "counter.textures_evicted" }?.severity == "info", "eviction alone is informational")

    var rising: [JSONValue] = []
    for i in 0..<40 {
        let bytes: Int = 500_000_000 + i * 10_000_000
        rising.append(JSONValue.parse("{\"memory\":{\"footprintBytes\":\(bytes)}}")!)
    }
    let g = AnomalyDetector.memoryGrowth(samples: rising, thresholdMB: 64, testId: "t")
    check(g.anomaly != nil && g.growthMB > 200, "steady growth is flagged")
    var flat: [JSONValue] = []
    for i in 0..<40 {
        let bytes: Int = 500_000_000 + (i % 2) * 5_000_000
        flat.append(JSONValue.parse("{\"memory\":{\"footprintBytes\":\(bytes)}}")!)
    }
    check(AnomalyDetector.memoryGrowth(samples: flat, thresholdMB: 64, testId: "t").anomaly == nil, "noise is not growth")
}

// MARK: Probe lines

do {
    let hello = Probe.parse(line: "12:00:00.000 +  3.000s MUFFINAUDIT HELLO 1 phase1 mailbox=0x10a4b000 tv=1280x720")
    check(hello == .hello(protocolVersion: 1, build: "phase1", mailbox: 0x10a4b000, tv: "1280x720"), "HELLO parses")
    let begin = Probe.parse(line: "MUFFINAUDIT TEST_BEGIN rt_copy 7 seed=42 a=1;b=2")
    check(begin == .testBegin(id: "rt_copy", token: 7, seed: 42, params: "a=1;b=2"), "TEST_BEGIN parses")
    check(Probe.parse(line: "MUFFINAUDIT CHECKPOINT rt_copy 7 copy_cells frame=312") == .checkpoint(id: "rt_copy", token: 7, name: "copy_cells", frame: 312), "CHECKPOINT parses")
    check(Probe.parse(line: "MUFFINAUDIT PHASE rt_copy 7 copies") == .phase(id: "rt_copy", token: 7, name: "copies"), "PHASE parses")
    check(Probe.parse(line: "MUFFINAUDIT SELF rt_copy 7 fail host did not answer") == .selfCheck(id: "rt_copy", token: 7, verdict: "fail", text: "host did not answer"), "SELF parses")
    check(Probe.parse(line: "MUFFINAUDIT TEST_END rt_copy 7 ok checksum=0badf00d frames=400 errors=0") == .testEnd(id: "rt_copy", token: 7, status: "ok", checksum: "0badf00d", frames: 400, errors: 0), "TEST_END parses")
    check(Probe.parse(line: "MUFFINAUDIT BYE") == .bye, "BYE parses")
    check(Probe.parse(line: "an ordinary engine line") == nil, "ordinary lines are not probe lines")
    check(Probe.parse(line: "MUFFINAUDIT TEST_END x notanumber ok") == nil, "malformed lines are rejected")
    let stamped = Probe.splitCoreStamp("09:41:22.517 +  12.345s Metal: hello there")
    check(stamped.elapsed == 12.345 && stamped.text == "Metal: hello there", "core stamp splits")
    check(Probe.splitCoreStamp("no stamp here").elapsed == nil, "no stamp, no elapsed")
}

// MARK: Verdicts, findings, report round trip

do {
    let cp = CheckpointRecord(name: "clear_0", tNs: 100, guestFrame: 10, frames: [], expectations: [
        ExpectationResult(type: "region_color", name: "red", pass: false, severity: "fail", expected: "red", measured: "black", values: [:]),
        ExpectationResult(type: "orientation", name: "o", pass: true, severity: "info", expected: "", measured: "", values: [:]),
    ], thumbnailFiles: [])
    let answers = [AnswerRecord(questionId: "q", question: "Did you see flicker?", type: "yesno", answer: "yes", bad: true, severity: "fail", subsystem: "render", answeredAt: "x", tNs: 200, testId: "t.one", runToken: 1, logContext: [])]
    let (res, why) = Judge.verdict(test: try! Catalogue.load(files: [("t.json", #"{"schema":"muffinaudit.suite/1","suite":"t","title":"T","tests":[{"id":"t.one","title":"One","subsystems":["render.clear"],"kind":"guest","stimulus":"s","expected":"e"}]}"#.data(using: .utf8)!)]).allTests[0].test,
                                   expectations: cp.expectations, checks: [], script: [], answers: answers, anomalies: [], guestResult: "ok", guestErrors: 0, guestMessage: "", errorReason: nil)
    check(res == .fail && why.contains("red: black") && why.contains("user reported"), "failed expectation and bad answer make a fail with both in the reason")

    let (res2, why2) = Judge.verdict(test: try! Catalogue.load(files: [("t.json", #"{"schema":"muffinaudit.suite/1","suite":"t","title":"T","tests":[{"id":"t.one","title":"One","subsystems":["render.clear"],"kind":"guest","stimulus":"s","expected":"e"}]}"#.data(using: .utf8)!)]).allTests[0].test,
                                     expectations: [], checks: [], script: [], answers: [], anomalies: [], guestResult: "ok", guestErrors: 0, guestMessage: "", errorReason: "the guest never answered")
    check(res2 == .error && why2 == "the guest never answered", "an error reason makes an error")

    func record(_ result: TestResult) -> TestRecord {
        TestRecord(id: "t.one", title: "One", suite: "t", subsystems: ["render.clear"], runIndex: 0, iteration: 0, token: 1, result: result, reason: "red: black",
                   configuration: TestConfiguration(kind: "guest", guestTest: "clear_colours", guestParams: "hold=20", seed: 1, durationMs: 0, renderer: "metal", padSurface: false, cpuMode: "interpreter"),
                   stimulus: "s", expected: "e", startedAt: "2026-01-01T00:00:00Z", endedAt: "2026-01-01T00:00:10Z", startNs: 1, endNs: 2, durationMs: 10000,
                   path: [PathStep(tNs: 5, kind: "phase", name: "clear_0")], checkpoints: [cp], checks: [], scriptSteps: [], answers: answers, userFlags: [],
                   performance: PerformanceRecord(frameIntervals: nil, reportedFps: 60, guestFrames: 600, footprintStartMB: 400, footprintEndMB: 410, footprintPeakMB: 420, availableMinMB: 900, snapshotSamples: 20, videoStallSeen: false, thermalStateEnd: "nominal", perfLine: ""),
                   snapshotBefore: nil, snapshotAfter: nil, snapshotDelta: nil,
                   logSlice: LogSlice(startNs: 1, endNs: 2, lineCount: 1, droppedLines: 0, truncated: false, file: "logs/t.one.txt",
                                      lines: [LogLine(tNs: 6, coreElapsed: 1.5, text: "MUFFINAUDIT SELF t.one 1 fail boom", tag: "guest")]),
                   anomalies: [], guestResult: "ok", guestChecksum: "00000000",
                   reproduction: Reproduction(seed: 1, params: "hold=20", guestTest: "clear_colours", outsideTool: "run audit.rpx", command: "RUN"))
    }
    let tests = [record(.fail), record(.pass)]
    let findings = Judge.findings(from: tests) { _ in "run audit.rpx" }
    check(findings.count == 1 && findings[0].sentence.contains("Test t.one failed") && findings[0].sentence.contains("user reported") && findings[0].sentence.contains("log shows"), "finding reads as a sentence with the test, the user and the log")
    let sum = Judge.summary(tests: tests, anomalies: [], durationSec: 12, complete: true)
    check(sum.verdict == "fail" && sum.counts["fail"] == 1 && sum.counts["pass"] == 1 && sum.affectedSubsystems.first?.subsystem == "render.clear", "summary counts and affected subsystems")
    check(Judge.summary(tests: [record(.pass)], anomalies: [], durationSec: 1, complete: true).verdict == "pass", "all pass is a pass")
    check(Judge.summary(tests: [record(.pass)], anomalies: [], durationSec: 1, complete: false).verdict == "incomplete", "an unfinished run is incomplete")

    let report = AuditReport(reportId: "r1", createdAt: "2026-01-01T00:00:00Z", finishedAt: nil,
        tool: ToolInfo(name: "MuffinEMU Audit", version: "1", probeProtocol: 1, hooksApi: 1, catalogueHash: "abc", catalogueSuites: ["t"]),
        build: BuildIdentity(muffinRef: "main", muffinSha: "0123456789abcdef", muffinVersion: "v6.0", coreFingerprint: "fp", hooksBuildInfo: "{}", auditAppVersion: "1.0", auditAppBuild: "9", auditToolsSha: "deadbeef", guestBuild: "phase1", workflowRun: "1", builtAt: "now"),
        device: DeviceInfo(machine: "iPad8,11", systemName: "iOS", systemVersion: "18.0", deviceReport: "r", capsLine: "c", chip: "A12Z", tier: 1, appleGpuFamily: 6, bcTextures: false, metal3: true, physicalMemoryMB: 5664, logicalCores: 8, isPad: true, screenPoints: [1194, 834], screenScale: 2, thermalStateAtStart: "nominal", lowPowerMode: false, jitPermitted: false),
        config: RunConfig(mode: "quick", suites: ["t"], testIds: ["t.one"], seed: 1, renderer: "metal", padSurface: false, cpu: "auto", cpuModeReported: "interpreter", coresRunning: 1, attended: true, repeatCount: 1, soakMinutes: 0, logProfile: 1, captureAvailable: true, graphicsApiReported: "metal"),
        summary: sum, findings: findings, tests: tests, anomalies: [], notes: ["note"])
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("audit-logic-test-\(getpid())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let urls = try! ReportWriter.write(report, to: dir)
    let back = try! JSONDecoder().decode(AuditReport.self, from: Data(contentsOf: urls.json))
    check(back.tests.count == 2 && back.build.muffinSha == "0123456789abcdef" && back.findings.count == 1, "report JSON round-trips")
    let md = try! String(contentsOf: urls.markdown, encoding: .utf8)
    check(md.contains("Verdict: FAIL") && md.contains("### t.one") && md.contains("Reproduce:") && md.contains("Affected subsystems"), "markdown has verdict, findings and subsystems")
    check(!md.contains("Generated with") && !md.lowercased().contains("claude"), "no attribution text in a report")
    try! ReportWriter.writeLogSlice(tests[0].logSlice.lines, to: dir.appendingPathComponent("logs/t.one.txt"))
    check((try? String(contentsOf: dir.appendingPathComponent("logs/t.one.txt"), encoding: .utf8))?.contains("[guest] MUFFINAUDIT SELF") == true, "log slice file is written")
    // A report file's keys are the contract tools/audit_diff.py reads.
    let raw = try! JSONSerialization.jsonObject(with: Data(contentsOf: urls.json)) as! [String: Any]
    check(raw["schema"] as? String == "muffinaudit.report/1" && raw["tests"] != nil && raw["anomalies"] != nil && raw["build"] != nil, "top-level keys present")
}

// MARK: Real catalogue (when CI points at it) and a sample report for the schema and diff checks

if let dirPath = ProcessInfo.processInfo.environment["AUDIT_CATALOGUE_DIR"] {
    let dir = URL(fileURLWithPath: dirPath)
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: dirPath)) ?? []).filter { $0.hasSuffix(".json") && $0 != "anomaly-patterns.json" }.sorted()
    check(!names.isEmpty, "catalogue directory has suite files")
    let files = names.map { (name: $0, data: try! Data(contentsOf: dir.appendingPathComponent($0))) }
    do {
        let cat = try Catalogue.load(files: files)
        check(cat.allTests.count >= 15, "the first suite has its tests (\(cat.allTests.count))")
        for (suite, t) in cat.allTests {
            check(!t.subsystems.isEmpty && !t.stimulus.isEmpty && !t.expected.isEmpty, "\(t.id) names its subsystems, stimulus and expected behaviour")
            check((t.kind == "guest" && t.guest != nil) || (t.kind == "host" && t.host != nil), "\(t.id) has the section its kind needs")
            for cp in t.checkpoints ?? [] {
                for e in cp.expect ?? [] {
                    if let r = e.rect { check(r.count == 4 && r[0] >= 0 && r[1] >= 0 && r[0] + r[2] <= 1.0001 && r[1] + r[3] <= 1.0001, "\(t.id)/\(cp.name)/\(e.name ?? e.type) rect is inside the frame") }
                    if let c = e.rgb { check(c.count == 3 && c.allSatisfy { $0 >= 0 && $0 <= 255 }, "\(t.id) rgb in range") }
                }
            }
            _ = suite
        }
        let orientation = cat.test(id: "bs.orientation")!.test
        check((orientation.tags ?? []).contains("calibration"), "the orientation test is the calibration test")
        let pl = Planner(catalogue: cat, request: RunRequest(mode: "standard", suiteIds: [], testIds: ["bs.clear_colours"], renderer: "metal", cpu: "auto", padSurface: false, attended: true, soakMinutes: 0, repeatCount: 1, seed: 7, logProfile: 1), deviceTier: 1)
        var p2 = pl
        let first = p2.next(now: Date(), started: Date())
        check(first?.test.id == "bs.orientation" && first?.calibration == true, "a frame-judged selection starts with the calibration test")
        check(p2.next(now: Date(), started: Date())?.test.id == "bs.clear_colours", "then the selected test")
        check(p2.next(now: Date(), started: Date()) == nil, "then nothing")
        var soak = Planner(catalogue: cat, request: RunRequest(mode: "soak", suiteIds: [], testIds: [], renderer: "metal", cpu: "auto", padSurface: false, attended: false, soakMinutes: 5, repeatCount: 1, seed: 3, logProfile: 1), deviceTier: 1)
        var seen = Set<String>()
        for _ in 0..<60 { if let n = soak.next(now: Date(), started: Date()) { seen.insert(n.test.id) } }
        check(seen.count >= 8 && !seen.contains("bs.audio_sweep_lpcm16") == false, "a soak plan keeps producing tests (\(seen.count) distinct)")
        check(seen.contains("bs.rt_copy_fuzz"), "soak includes the fuzz test")
    } catch {
        check(false, "the real catalogue loads: \(error)")
    }
}

if let out = ProcessInfo.processInfo.environment["AUDIT_SAMPLE_OUT"] {
    // A small but complete report, written by the real writer, for tools/audit-app/validate_report.py and audit_diff.py.
    func rec(_ id: String, _ result: TestResult, fps: Double, reason: String) -> TestRecord {
        let cp = CheckpointRecord(name: "cp", tNs: 10, guestFrame: 3, frames: [FrameRecord(seq: 1, view: "tv", status: "ok", latteFrame: 5, tNs: 11, width: 1280, height: 720, pixelFormat: 70, meanRGB: [255, 0, 0], blackFraction: 0, whiteFraction: 0, minLuma: 50, maxLuma: 50, hash: "00000000000000ff")],
                                   expectations: [ExpectationResult(type: "region_color", name: "red", pass: result == .pass, severity: "fail", expected: "red", measured: result == .pass ? "red" : "black", values: ["maxDiff": result == .pass ? 0 : 255])], thumbnailFiles: [])
        return TestRecord(id: id, title: id, suite: "s", subsystems: ["render.clear"], runIndex: 0, iteration: 0, token: 1, result: result, reason: reason,
            configuration: TestConfiguration(kind: "guest", guestTest: "x", guestParams: "", seed: 1, durationMs: 0, renderer: "metal", padSurface: false, cpuMode: "interpreter"),
            stimulus: "s", expected: "e", startedAt: "2026-01-01T00:00:00Z", endedAt: "2026-01-01T00:00:01Z", startNs: 1, endNs: 2, durationMs: 1000,
            path: [], checkpoints: [cp], checks: [CheckResult(type: "frame_pacing", name: "pacing", pass: true, severity: "warn", summary: "ok", values: ["fps": fps, "p99Ms": 17])], scriptSteps: [], answers: [], userFlags: [],
            performance: PerformanceRecord(frameIntervals: FramePacingStats(count: 100, meanMs: 1000 / fps, p50Ms: 1000 / fps, p95Ms: 18, p99Ms: 20, maxMs: 25, stdDevMs: 1, fps: fps, long: 0, veryLong: 0, dropped: 0),
                reportedFps: fps, guestFrames: 100, footprintStartMB: 400, footprintEndMB: 410, footprintPeakMB: 412, availableMinMB: 900, snapshotSamples: 5, videoStallSeen: false, thermalStateEnd: "nominal", perfLine: ""),
            snapshotBefore: JSONValue.parse(#"{"tNs":1,"gpuThread":{"drawableFailures":0}}"#), snapshotAfter: JSONValue.parse(#"{"tNs":2,"gpuThread":{"drawableFailures":0}}"#), snapshotDelta: nil,
            logSlice: LogSlice(startNs: 1, endNs: 2, lineCount: 0, droppedLines: 0, truncated: false, file: "logs/x.txt", lines: []),
            anomalies: [], guestResult: "ok", guestChecksum: "00000000", reproduction: Reproduction(seed: 1, params: "", guestTest: "x", outsideTool: "run audit.rpx", command: "RUN"))
    }
    let tests = [rec("bs.a", .pass, fps: 60, reason: "ok"), rec("bs.b", .fail, fps: 59, reason: "red: black")]
    let sum = Judge.summary(tests: tests, anomalies: [], durationSec: 3, complete: true)
    let report = AuditReport(reportId: "sample", createdAt: "2026-01-01T00:00:00Z", finishedAt: "2026-01-01T00:00:03Z",
        tool: ToolInfo(name: "MuffinEMU Audit", version: "1", probeProtocol: 1, hooksApi: 1, catalogueHash: "abc", catalogueSuites: ["s"]),
        build: BuildIdentity(muffinRef: "main", muffinSha: "0123456789abcdef", muffinVersion: "v6.0", coreFingerprint: "fp", hooksBuildInfo: "{}", auditAppVersion: "1.0", auditAppBuild: "1", auditToolsSha: "abc", guestBuild: "phase1", workflowRun: "1", builtAt: "now"),
        device: DeviceInfo(machine: "iPad8,11", systemName: "iOS", systemVersion: "18.0", deviceReport: "r", capsLine: "c", chip: "A12Z", tier: 1, appleGpuFamily: 6, bcTextures: false, metal3: true, physicalMemoryMB: 5664, logicalCores: 8, isPad: true, screenPoints: [834, 1194], screenScale: 2, thermalStateAtStart: "nominal", lowPowerMode: false, jitPermitted: false),
        config: RunConfig(mode: "quick", suites: ["s"], testIds: [], seed: 1, renderer: "metal", padSurface: false, cpu: "auto", cpuModeReported: "interpreter", coresRunning: 1, attended: true, repeatCount: 1, soakMinutes: 0, logProfile: 1, captureAvailable: true, graphicsApiReported: "metal"),
        summary: sum, findings: Judge.findings(from: tests) { _ in "run audit.rpx" }, tests: tests, anomalies: [], notes: [])
    try! ReportWriter.json(report).write(to: URL(fileURLWithPath: out))
}

print("\(checks) checks, \(failures) failure(s)")
exit(failures == 0 ? 0 : 1)
