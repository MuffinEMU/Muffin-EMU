//
//  TestExecution.swift
//  Running one guest test from RUN to record. See AuditRunner.swift for the outline.
//
import Foundation

/// Everything measured while one test runs.
struct Measurements {
    var samples: [JSONValue] = []
    var footprintsMB: [Double] = []
    var availableMB: [Double] = []
    var presentNs: [UInt64] = []
    var presentDropped = 0
    var checkpoints: [CheckpointRecord] = []
    var audioMarks: [(step: Int, audio: JSONValue)] = []
    var videoStallSeen = false
    var scriptResults: [ScriptResult] = []
    var lastGuest = GuestState()
    var errorReason: String?
}

extension AuditRunner {
    // MARK: Guest test

    func runGuestTest(_ item: PlannedTest) async -> TestRecord {
        let test = item.test
        guard let guest = test.guest else { return skeleton(item, result: .error, reason: "no guest section") }

        do { try await ensureGuest() } catch {
            guestUp = false
            var rec = skeleton(item, result: .error, reason: "the guest could not be started: \(error)")
            rec.logSlice.lines = Array(logs.lines.suffix(80))
            rec.logSlice.lineCount = rec.logSlice.lines.count
            return rec
        }

        let token = nextToken
        nextToken &+= 1
        let params = guest.paramString(overrides: item.paramOverrides)
        let startDate = Date()
        let startNs = core.nowNs
        let startIdx = logs.count
        let startDropped = logs.droppedTotal
        probeEvents.removeAll()
        logs.hostLine("BEGIN \(test.id) token=\(token) seed=\(item.seed) params=\(params)")
        core.resetAudioStats()
        core.setFrameTiming(true)
        _ = core.drainFrameTimes()

        var m = Measurements()
        let before = core.snapshot()
        if let b = before { m.samples.append(b) }
        let initialState = link.readState() ?? GuestState()
        var lastCheckpointSeq = initialState.checkpointSeq
        var scriptStarted = false
        var currentAudioStep = -1

        let durationMs = UInt32(max(0, guest.durationMs ?? 0))
        link.send(command: Mailbox.cmdRun, testId: guest.test, params: params, runToken: token, durationMs: durationMs, seed: item.seed)

        let timeoutSec = Double(test.timeoutSec ?? ((test.estimatedSec ?? 30) * 3 + 45))
        let loopStart = Date()
        var lastSnapshot = Date.distantPast
        var lastTiming = Date.distantPast
        var stallSince: Date?
        var finished = false
        var abortSent: Date?

        while !finished {
            try? await Task.sleep(nanoseconds: 20_000_000)
            logs.drain()

            if host?.isCancelled == true && abortSent == nil {
                link.send(command: Mailbox.cmdAbort)
                abortSent = Date()
                m.errorReason = "cancelled by the user"
            }
            guard core.titleRunning else {
                m.errorReason = "the title stopped running during the test (the core ended it or it crashed)"
                guestUp = false
                break
            }
            guard let st = link.readState() else {
                m.errorReason = "the guest's mailbox could not be read"
                guestUp = false
                break
            }
            m.lastGuest = st

            if Date().timeIntervalSince(lastSnapshot) >= 0.5 {
                lastSnapshot = Date()
                if let snap = core.snapshot() {
                    m.samples.append(snap)
                    if let f = snap.path("memory.footprintBytes")?.double, f > 0 { m.footprintsMB.append(f / 1_048_576.0) }
                    if let a = snap.path("memory.availableBytes")?.double, a > 0 { m.availableMB.append(a / 1_048_576.0) }
                }
            }
            if Date().timeIntervalSince(lastTiming) >= 0.25 {
                lastTiming = Date()
                let t = core.drainFrameTimes()
                m.presentNs.append(contentsOf: t.times)
                m.presentDropped += t.dropped
            }

            // A frozen picture while the emulator is alive.
            if core.videoStallKind != 0 {
                if stallSince == nil { stallSince = Date() }
                if Date().timeIntervalSince(stallSince!) > 3 { m.videoStallSeen = true }
            } else {
                stallSince = nil
            }

            // Audio windows: snapshot the audio counters whenever the guest's sweep moves to a new step.
            if st.audioStep != UInt32(bitPattern: Int32(currentAudioStep)), st.state != Mailbox.stateIdle || st.audioStep > 0 {
                currentAudioStep = Int(st.audioStep)
                if let snap = core.snapshot(), let audio = snap["audio"] { m.audioMarks.append((currentAudioStep, audio)) }
            }

            if st.checkpointSeq != lastCheckpointSeq && st.state == Mailbox.stateCheckpoint && st.runToken == token {
                lastCheckpointSeq = st.checkpointSeq
                await handleCheckpoint(test: test, name: st.checkpointName, guestFrame: st.frames, m: &m)
            }

            if let steps = test.script, !steps.isEmpty, !scriptStarted, st.runToken == token, st.state == Mailbox.stateRunning, st.inputReads > 0 {
                scriptStarted = true
                await runScript(steps, m: &m)
                link.send(command: Mailbox.cmdContinue) // the guest's input loop ends on CONTINUE
            }

            if st.state == Mailbox.stateIdle && st.runToken == token && st.testResult != Mailbox.resultNone {
                finished = true
                break
            }

            let elapsed = Date().timeIntervalSince(loopStart)
            if let sent = abortSent {
                if Date().timeIntervalSince(sent) > 6 {
                    m.errorReason = (m.errorReason ?? "aborted") + "; the guest did not answer ABORT"
                    guestUp = false
                    break
                }
            } else if elapsed > timeoutSec {
                link.send(command: Mailbox.cmdAbort)
                abortSent = Date()
                m.errorReason = "the test did not finish within \(Int(timeoutSec)) s; aborted"
            }
        }

        // Settle: pull the last log lines and counters.
        try? await Task.sleep(nanoseconds: 60_000_000)
        logs.drain()
        let after = core.snapshot()
        if let a = after { m.samples.append(a) }
        let t = core.drainFrameTimes()
        m.presentNs.append(contentsOf: t.times)
        m.presentDropped += t.dropped
        core.setFrameTiming(false)
        if let audio = after?["audio"] { m.audioMarks.append((9999, audio)) }
        if core.videoStallKind != 0 && stallSince != nil { m.videoStallSeen = true }

        let endNs = core.nowNs
        let endDate = Date()
        let endIdx = logs.count
        logs.hostLine("END \(test.id) token=\(token) guest=\(m.lastGuest.resultName)")
        if core.titleRunning == false { guestUp = false }

        // A latched GPU error stays until the title stops; stop it so the next test starts clean.
        if after?.path("gpuThread.gpuError")?.bool == true {
            guestUp = false
            notes.append("\(test.id): the GPU reported an error; the guest was restarted for the next test.")
        }

        return await finishRecord(item: item, token: token, params: params, startDate: startDate, endDate: endDate,
                                  startNs: startNs, endNs: endNs, startIdx: startIdx, endIdx: endIdx, startDropped: startDropped, before: before, after: after, m: &m)
    }

    // MARK: Checkpoint

    func handleCheckpoint(test: TestDef, name: String, guestFrame: UInt32, m: inout Measurements) async {
        let cpNs = core.nowNs
        let def = test.checkpoints?.first { $0.matches(name) }
        var frames: [CapturedFrame] = []

        // A checkpoint with no capture section is only held and released (frame pacing, for one, must not be disturbed by readback).
        if let def = def, let spec = def.capture, captureAvailable {
            let views = spec.views ?? ["tv"]
            let want = max(1, spec.count ?? 1)
            core.armCapture(tv: views.contains("tv"), pad: views.contains("pad") && request.padSurface, count: want)
            let deadline = Date().addingTimeInterval(3.0 + Double(want) * 0.5)
            while Date() < deadline && core.capturePending < want * ((views.contains("pad") && request.padSurface) ? 2 : 1) {
                try? await Task.sleep(nanoseconds: 20_000_000)
                logs.drain()
            }
            core.cancelCapture()
            while let f = core.popFrame() { frames.append(f) }
        }

        var results: [ExpectationResult] = []
        for e in def?.expect ?? [] {
            results.append(FrameAnalysis.evaluate(e, frames: frames, orientation: orientation))
        }
        // The orientation test teaches the runner how to read every later frame.
        if (def?.expect ?? []).contains(where: { $0.type == "orientation" }),
           let last = frames.last(where: { $0.viewName == "tv" && $0.isUsable }),
           let (o, confidence) = FrameAnalysis.detectOrientation(last), confidence > 120 {
            orientation = o
            orientationKnown = true
            logs.hostLine("ORIENTATION \(o.rawValue) confidence=\(Int(confidence))")
        }

        var files: [String] = []
        if results.contains(where: { !$0.pass && $0.severity == "fail" }) {
            for f in frames.suffix(2) where f.isUsable {
                let rel = "frames/\(test.id)-\(name)-\(f.viewName)-\(f.seq).png"
                if ThumbnailPNG.write(f, to: reportDir.appendingPathComponent(rel)) { files.append(rel) }
            }
        }

        let records = frames.map { f in
            FrameRecord(seq: f.seq, view: f.viewName, status: f.status == 0 ? "ok" : (f.status == 1 ? "unsupported_format" : "readback_failed"),
                        latteFrame: f.latteFrame, tNs: f.tNs, width: f.srcWidth, height: f.srcHeight, pixelFormat: f.pixelFormat,
                        meanRGB: [f.meanR, f.meanG, f.meanB], blackFraction: f.blackFraction, whiteFraction: f.whiteFraction,
                        minLuma: f.minLuma, maxLuma: f.maxLuma, hash: String(format: "%016llx", f.hash))
        }
        m.checkpoints.append(CheckpointRecord(name: name, tNs: cpNs, guestFrame: guestFrame, frames: records, expectations: results, thumbnailFiles: files))
        link.send(command: Mailbox.cmdContinue)
    }

    // MARK: Record

    func finishRecord(item: PlannedTest, token: UInt32, params: String, startDate: Date, endDate: Date, startNs: UInt64, endNs: UInt64,
                      startIdx: Int, endIdx: Int, startDropped: Int, before: JSONValue?, after: JSONValue?, m: inout Measurements) async -> TestRecord {
        let test = item.test
        let events = probeEvents
        var path: [PathStep] = []
        var guestMessage = m.lastGuest.message
        for (event, ns) in events {
            switch event {
            case .phase(let id, let tok, let name) where id == test.guest?.test && tok == token: path.append(PathStep(tNs: ns, kind: "phase", name: name))
            case .checkpoint(let id, let tok, let name, _) where id == test.guest?.test && tok == token: path.append(PathStep(tNs: ns, kind: "checkpoint", name: name))
            case .selfCheck(let id, let tok, let verdict, let text) where id == test.guest?.test && tok == token:
                path.append(PathStep(tNs: ns, kind: "self-\(verdict)", name: String(text.prefix(80))))
                if verdict == "fail" { guestMessage = text }
            case .note(let id, let tok, let text) where id == test.guest?.test && tok == token: path.append(PathStep(tNs: ns, kind: "note", name: String(text.prefix(80))))
            default: break
            }
        }

        // Whole-test checks.
        var inputs = CheckInputs()
        let windows = audioWindows(m.audioMarks)
        inputs.audioWindows = windows
        let growth = AnomalyDetector.memoryGrowth(samples: m.samples, thresholdMB: 1e9, testId: test.id)
        inputs.footprintGrowthMB = growth.growthMB
        inputs.footprintSamples = m.footprintsMB.count
        let pacing = Pacing.stats(intervalsMs: Pacing.intervalsMs(m.presentNs), dropped: m.presentDropped)
        inputs.pacing = pacing
        inputs.guestErrors = Int(m.lastGuest.errors)
        var checks: [CheckResult] = []
        for c in test.checks ?? [] { checks.append(CheckEvaluator.evaluate(c, inputs)) }

        // Anomalies: the log, the counters, memory, pacing, a stalled picture.
        let slice = logs.slice(from: startIdx, to: endIdx)
        var anomalies = detector.scan(log: slice, testId: test.id)
        anomalies += AnomalyDetector.scan(before: before, after: after, samples: m.samples, testId: test.id)
        if let a = AnomalyDetector.memoryGrowth(samples: m.samples, thresholdMB: 128, testId: test.id).anomaly { anomalies.append(a) }
        anomalies += AnomalyDetector.pacing(pacing, testId: test.id)
        if m.videoStallSeen {
            anomalies.append(Anomaly(id: "video.stall", kind: "video_stall", severity: "fail", subsystem: "render.present", testId: test.id, tNs: endNs,
                                     message: "The core flagged the picture as stalled (no new frames for several seconds while the emulator stayed alive).",
                                     evidence: ["cemu_bridge_video_stall_kind() was non-zero"]))
        }

        // Questionnaire.
        var answers: [AnswerRecord] = []
        let questions = test.questionnaire ?? []
        if !questions.isEmpty, request.attended, m.errorReason == nil {
            if let host = host, !host.isCancelled {
                host.status("Answer the questions about \(test.title)")
                let req = QuestionRequest(testId: test.id, testTitle: test.title, questions: questions, stimulus: test.stimulus)
                if let given = await host.ask(req) {
                    logs.drain()
                    let answeredNs = core.nowNs
                    let context = logs.slice(from: max(startIdx, endIdx - 20), to: logs.count)
                    for q in questions {
                        guard let a = given[q.id] else { continue }
                        answers.append(AnswerRecord(questionId: q.id, question: q.text, type: q.type, answer: a, bad: Self.isBad(q, a),
                                                    severity: q.severity ?? "fail", subsystem: q.subsystem ?? (test.subsystems.first ?? ""),
                                                    answeredAt: Self.nowIso(), tNs: answeredNs, testId: test.id, runToken: token,
                                                    logContext: Array(context.suffix(60))))
                    }
                }
            }
        }

        // Glitches the person flagged while the test ran.
        var flags: [UserFlag] = []
        if let host = host {
            for f in host.takeGlitchFlags() {
                let t = f.tNs
                flags.append(UserFlag(tNs: t, at: Self.nowIso(), note: f.note, logContext: logs.context(around: t, radius: 25)))
            }
        }

        let (result, reason) = Judge.verdict(test: test, expectations: m.checkpoints.flatMap { $0.expectations }, checks: checks, script: m.scriptResults,
                                             answers: answers, anomalies: anomalies.filter { $0.severity == "fail" }, guestResult: m.lastGuest.resultName,
                                             guestErrors: Int(m.lastGuest.errors), guestMessage: guestMessage, errorReason: m.errorReason)

        // Log slice: whole slice to a file, a bounded version in the report.
        let fileRel = "logs/\(test.id)-\(item.iteration)-\(token).txt"
        try? ReportWriter.writeLogSlice(slice, to: reportDir.appendingPathComponent(fileRel))
        var kept = slice
        var truncated = false
        let compact = result == .pass && records.count > 40
        let cap = compact ? 30 : 600
        if slice.count > cap {
            truncated = true
            let marked = slice.filter { $0.tag != nil }
            let head = slice.prefix(cap / 4), tailLines = slice.suffix(cap / 4)
            var seen = Set<UInt64>()
            kept = []
            for l in Array(head) + marked.prefix(cap / 2) + Array(tailLines) where seen.insert(l.tNs &* 31 &+ UInt64(l.text.hashValue & 0xFFFF)).inserted { kept.append(l) }
            kept.sort { $0.tNs < $1.tNs }
        }

        let foot = m.footprintsMB
        let perf = PerformanceRecord(frameIntervals: pacing, reportedFps: core.fps, guestFrames: Int(m.lastGuest.frames),
                                     footprintStartMB: foot.first ?? 0, footprintEndMB: foot.last ?? 0, footprintPeakMB: foot.max() ?? 0,
                                     availableMinMB: m.availableMB.min() ?? 0, snapshotSamples: m.samples.count, videoStallSeen: m.videoStallSeen,
                                     thermalStateEnd: Platform.thermalStateName(), perfLine: core.perfLine)

        var delta: JSONValue?
        if let a = after, let b = before { delta = a.delta(from: b) }

        return TestRecord(
            id: test.id, title: test.title, suite: item.suite.suite, subsystems: test.subsystems, runIndex: records.count, iteration: item.iteration,
            token: token, result: result, reason: reason, configuration: configuration(item, params: params),
            stimulus: test.stimulus, expected: test.expected, startedAt: Self.iso(startDate), endedAt: Self.iso(endDate),
            startNs: startNs, endNs: endNs, durationMs: endDate.timeIntervalSince(startDate) * 1000.0,
            path: path, checkpoints: m.checkpoints, checks: checks, scriptSteps: m.scriptResults, answers: answers, userFlags: flags,
            performance: perf, snapshotBefore: compact ? nil : before, snapshotAfter: compact ? nil : after, snapshotDelta: delta,
            logSlice: LogSlice(startNs: startNs, endNs: endNs, lineCount: slice.count, droppedLines: logs.droppedTotal - startDropped, truncated: truncated, file: fileRel, lines: kept),
            anomalies: anomalies, guestResult: m.lastGuest.resultName, guestChecksum: String(format: "%08x", m.lastGuest.checksum),
            reproduction: reproduction(item, params: params))
    }

    static func isBad(_ q: QuestionDef, _ answer: String) -> Bool {
        switch q.type {
        case "yesno": return q.bad.map { $0.lowercased() == answer.lowercased() } ?? false
        case "scale": if let v = Int(answer), let floor = q.badBelow { return v < floor }; return false
        case "choice": return (q.badOptions ?? []).contains(answer)
        default: return false
        }
    }

    /// Consecutive audio-counter marks become (start, end) windows per guest step.
    func audioWindows(_ marks: [(step: Int, audio: JSONValue)]) -> [Int: (start: JSONValue, end: JSONValue)] {
        var out: [Int: (start: JSONValue, end: JSONValue)] = [:]
        guard marks.count >= 2 else { return out }
        for i in 0..<(marks.count - 1) {
            let step = marks[i].step
            if step >= 0 && step < 9999 { out[step] = (marks[i].audio, marks[i + 1].audio) }
        }
        return out
    }
}
