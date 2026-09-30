//
//  Judge.swift
//  Puts a test's measurements, answers and anomalies together into one verdict and one reason, and
//  turns the verdicts into the report's findings and summary. Pure Swift.
//
import Foundation

struct Judge {
    /// `errorReason` is set by the runner when the test could not be run to completion (the guest hung, the core
    /// died, a capture could not start); such a test is an error, not a pass or a fail.
    static func verdict(test: TestDef, expectations: [ExpectationResult], checks: [CheckResult], script: [ScriptResult],
                        answers: [AnswerRecord], anomalies: [Anomaly], guestResult: String, guestErrors: Int, guestMessage: String,
                        errorReason: String?) -> (TestResult, String) {
        if let e = errorReason { return (.error, e) }

        var failures: [String] = []
        var warnings = 0

        for r in expectations where !r.pass {
            if r.severity == "fail" { failures.append("\(r.name): \(r.measured)") }
            else if r.severity == "warn" { warnings += 1 }
        }
        for c in checks where !c.pass {
            if c.severity == "fail" { failures.append("\(c.name): \(c.summary)") }
            else if c.severity == "warn" { warnings += 1 }
        }
        for s in script where !s.pass {
            if s.severity == "fail" { failures.append("\(s.label): wanted \(s.expected), saw \(s.measured)") }
            else if s.severity == "warn" { warnings += 1 }
        }
        for a in answers where a.bad {
            if a.severity == "fail" { failures.append("user reported: \(a.question) -> \(a.answer)") }
            else if a.severity == "warn" { warnings += 1 }
        }
        for a in anomalies where a.severity == "fail" {
            failures.append("anomaly: \(a.message)")
        }
        if guestResult == "error" || guestErrors > 0 {
            let detail = guestMessage.isEmpty ? "" : ": \(guestMessage)"
            failures.append("the guest reported \(max(guestErrors, 1)) error(s)\(detail)")
        }

        if failures.isEmpty {
            let total = expectations.count + checks.count + script.count + answers.count
            var reason = total == 0 ? "ran to completion" : "all \(total) checks passed"
            if warnings > 0 { reason += " (\(warnings) warning\(warnings == 1 ? "" : "s"))" }
            return (.pass, reason)
        }
        let head = failures.prefix(3).joined(separator: "; ")
        return (.fail, failures.count > 3 ? head + "; and \(failures.count - 3) more" : head)
    }

    // MARK: Findings

    static func findings(from tests: [TestRecord], reproduceText: (TestRecord) -> String) -> [Finding] {
        var out: [Finding] = []
        for t in tests where t.result == .fail || t.result == .error {
            let failedExp = t.checkpoints.flatMap { cp in cp.expectations.filter { !$0.pass && $0.severity == "fail" }.map { "\(cp.name)/\($0.name): \($0.measured)" } }
            let failedChecks = t.checks.filter { !$0.pass && $0.severity == "fail" }.map { "\($0.name): \($0.summary)" }
                + t.scriptSteps.filter { !$0.pass && $0.severity == "fail" }.map { "\($0.label): wanted \($0.expected), saw \($0.measured)" }
            let reported = t.answers.filter { $0.bad && $0.severity != "info" }.map { UserReport(question: $0.question, answer: $0.answer, tNs: $0.tNs) }
                + t.userFlags.map { UserReport(question: "User flagged a glitch", answer: $0.note.isEmpty ? "(no note)" : $0.note, tNs: $0.tNs) }

            // The log lines on this path: anomalies' evidence first, then guest notes and self-check failures, then a few core lines.
            var highlights: [LogLine] = []
            for a in t.anomalies where a.severity != "info" {
                if let ns = a.tNs, let line = t.logSlice.lines.first(where: { $0.tNs >= ns && $0.tag == nil }) { highlights.append(line) }
            }
            highlights += t.logSlice.lines.filter { $0.tag == "guest" && ($0.text.contains(" SELF ") && $0.text.contains(" fail ")) }.prefix(3)
            for f in t.userFlags { highlights += f.logContext.prefix(6) }
            if highlights.isEmpty { highlights = Array(t.logSlice.lines.suffix(5)) }

            var sentence = "Test \(t.id) \(t.result == .error ? "could not complete" : "failed"): \(t.reason)."
            if !reported.isEmpty {
                sentence += " The user reported: " + reported.prefix(3).map { "\($0.question) -> \($0.answer)" }.joined(separator: "; ") + "."
            }
            if let first = highlights.first { sentence += " On this path the log shows: \"\(first.text.prefix(140))\"." }

            out.append(Finding(testId: t.id, title: t.title, result: t.result, reason: t.reason, sentence: sentence,
                               subsystems: t.subsystems, failedExpectations: failedExp, failedChecks: failedChecks,
                               userReported: reported, logHighlights: Array(highlights.prefix(8)),
                               path: t.path.map { "\($0.kind):\($0.name)" }, reproduce: reproduceText(t)))
        }
        return out
    }

    static func summary(tests: [TestRecord], anomalies: [Anomaly], durationSec: Double, complete: Bool) -> ReportSummary {
        var counts: [String: Int] = ["pass": 0, "fail": 0, "skip": 0, "error": 0]
        for t in tests { counts[t.result.rawValue, default: 0] += 1 }

        var bySub: [String: (tests: Set<String>, anomalies: Int)] = [:]
        for t in tests where t.result == .fail || t.result == .error {
            for s in t.subsystems { bySub[s, default: ([], 0)].tests.insert(t.id) }
        }
        for a in anomalies where a.severity == "fail" || a.severity == "warn" {
            bySub[a.subsystem, default: ([], 0)].anomalies += 1
        }
        let affected = bySub.map { SubsystemSummary(subsystem: $0.key, failedTests: $0.value.tests.sorted(), anomalies: $0.value.anomalies) }
            .sorted { $0.subsystem < $1.subsystem }

        var anomalyCounts: [String: Int] = [:]
        for a in anomalies { anomalyCounts[a.severity, default: 0] += 1 }

        let verdict: String
        if !complete { verdict = "incomplete" }
        else if counts["fail", default: 0] > 0 || counts["error", default: 0] > 0 { verdict = "fail" }
        else { verdict = "pass" }
        return ReportSummary(verdict: verdict, counts: counts, totalTests: tests.count, durationSec: durationSec,
                             affectedSubsystems: affected, anomalyCounts: anomalyCounts)
    }
}
