//
//  Pacing.swift
//  Frame pacing from the present timestamps the core records on the GPU thread, and the checks the
//  catalogue can ask of them. Pure Swift.
//
import Foundation

enum Pacing {
    /// Intervals in milliseconds between consecutive present timestamps (nanoseconds).
    static func intervalsMs(_ presentNs: [UInt64]) -> [Double] {
        guard presentNs.count >= 2 else { return [] }
        var out: [Double] = []
        out.reserveCapacity(presentNs.count - 1)
        for i in 1..<presentNs.count {
            let a = presentNs[i - 1], b = presentNs[i]
            if b >= a { out.append(Double(b - a) / 1_000_000.0) }
        }
        return out
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let rank = p * Double(sorted.count - 1)
        let lo = Int(rank.rounded(.down)), hi = Int(rank.rounded(.up))
        if lo == hi { return sorted[lo] }
        return sorted[lo] + (sorted[hi] - sorted[lo]) * (rank - Double(lo))
    }

    /// `dropped` is how many timestamps the core's ring lost (the app was slow to drain it), reported
    /// rather than hidden: a pacing figure from a stream with holes in it is only as good as that count says.
    static func stats(intervalsMs: [Double], dropped: Int) -> FramePacingStats? {
        guard !intervalsMs.isEmpty else { return nil }
        let sorted = intervalsMs.sorted()
        let mean = intervalsMs.reduce(0, +) / Double(intervalsMs.count)
        let variance = intervalsMs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(intervalsMs.count)
        let median = percentile(sorted, 0.5)
        let long = intervalsMs.filter { $0 > median * 1.5 }.count
        let veryLong = intervalsMs.filter { $0 > median * 2.5 }.count
        return FramePacingStats(count: intervalsMs.count, meanMs: mean, p50Ms: median,
                                p95Ms: percentile(sorted, 0.95), p99Ms: percentile(sorted, 0.99),
                                maxMs: sorted.last ?? 0, stdDevMs: variance.squareRoot(),
                                fps: mean > 0 ? 1000.0 / mean : 0, long: long, veryLong: veryLong, dropped: dropped)
    }
}
