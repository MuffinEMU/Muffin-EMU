//
//  LogCapture.swift
//  Keeps the whole run's core log, each line stamped on the core's monotonic clock, and cuts it into
//  per-test slices. The core's own live-log ring holds only the most recent 1024 lines, so this drains
//  it often (the runner calls drain() every 20 ms) and counts any lines it lost.
//
//  The test id goes into the log itself as well: the runner writes "AUDIT> BEGIN <id> ..." lines through
//  cemu_bridge_log_line, so the core's own log.txt carries the same tags as the report's slices.
//
import Foundation

final class LogCapture {
    private(set) var lines: [LogLine] = []
    private var cursor: UInt64 = 0
    private(set) var droppedTotal: Int = 0
    private let maxLines = 400_000

    /// Called for every probe line as it arrives, with the tNs stamped on it.
    var onProbe: ((ProbeEvent, UInt64) -> Void)?

    var count: Int { lines.count }

    /// Clears everything; call when a new title is about to boot (the core restarts its own log then too).
    func reset() {
        // Skip to the end of the core's ring instead of rewinding: its sequence numbers keep counting across boots,
        // so a cursor of zero would read as "everything since the beginning of time was dropped".
        var dropped: UInt64 = 0
        _ = ios_live_log_drain(&cursor, &dropped)
        lines.removeAll()
    }

    /// Pulls whatever the core logged since the last call. Returns the new lines.
    @discardableResult
    func drain() -> [LogLine] {
        var dropped: UInt64 = 0
        guard let cstr = ios_live_log_drain(&cursor, &dropped) else { return [] }
        let batchNs = cemu_audit_now_ns()
        droppedTotal += Int(dropped)
        let text = String(cString: cstr)
        if text.isEmpty { return [] }
        return ingest(text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init), batchNs: batchNs)
    }

    /// Stamps and stores raw lines (split from one drain) and fires probe callbacks. The core's "+seconds"
    /// column orders lines within the batch precisely; the batch as a whole is anchored at `batchNs`.
    @discardableResult
    func ingest(_ raw: [String], batchNs: UInt64) -> [LogLine] {
        var parsed: [(Double?, String)] = raw.map { line in
            let (e, t) = Probe.splitCoreStamp(line)
            return (e, t)
        }
        let lastElapsed = parsed.last(where: { $0.0 != nil })?.0
        var out: [LogLine] = []
        out.reserveCapacity(parsed.count)
        for (elapsed, text) in parsed {
            var ns = batchNs
            if let e = elapsed, let last = lastElapsed, last >= e {
                let back = UInt64((last - e) * 1_000_000_000.0)
                ns = batchNs > back ? batchNs - back : 0
            }
            let tag: String? = text.contains(Probe.prefix + " ") ? "guest" : (text.contains("AUDIT> ") ? "host" : nil)
            let line = LogLine(tNs: ns, coreElapsed: elapsed, text: text, tag: tag)
            out.append(line)
            lines.append(line)
            if tag == "guest", let event = Probe.parse(line: text) { onProbe?(event, ns) }
        }
        parsed.removeAll()
        if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
        return out
    }

    /// Writes a line into the core's log (and so into this capture on the next drain), tagged as the host's.
    func hostLine(_ text: String) {
        cemu_bridge_log_line("AUDIT> " + text)
    }

    /// Lines with index in [from, to).
    func slice(from: Int, to: Int) -> [LogLine] {
        let lo = max(0, min(from, lines.count)), hi = max(lo, min(to, lines.count))
        return Array(lines[lo..<hi])
    }

    /// `radius` lines either side of the line nearest to `tNs`.
    func context(around tNs: UInt64, radius: Int = 25) -> [LogLine] {
        guard !lines.isEmpty else { return [] }
        var idx = 0
        for i in stride(from: lines.count - 1, through: 0, by: -1) where lines[i].tNs <= tNs { idx = i; break }
        return slice(from: idx - radius, to: idx + radius + 1)
    }
}
