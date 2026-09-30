//
//  Planner.swift
//  Turns a run request into the order tests run in. Pure Swift, unit-tested.
//
import Foundation

struct PlannedTest {
    var suite: SuiteFile
    var test: TestDef
    var iteration: Int
    var seed: UInt32
    var paramOverrides: [String: String]
    var calibration: Bool
}

// MARK: - Planner

struct Planner {
    let catalogue: Catalogue
    let request: RunRequest
    let deviceTier: Int
    private var queue: [PlannedTest] = []
    private var cycle = 0
    private var produced = 0
    private var calibrationDone = false
    private(set) var estimatedTotal = 0

    init(catalogue: Catalogue, request: RunRequest, deviceTier: Int) {
        self.catalogue = catalogue
        self.request = request
        self.deviceTier = deviceTier
        queue = base(cycle: 0)
        estimatedTotal = request.mode == "soak" ? 0 : queue.count * max(1, request.repeatCount)
    }

    private func selected() -> [(suite: SuiteFile, test: TestDef)] {
        let all = catalogue.allTests
        var out = all.filter { item in
            (request.suiteIds.isEmpty || request.suiteIds.contains(item.suite.suite)) &&
            (request.testIds.isEmpty || request.testIds.contains(item.test.id))
        }
        if request.mode == "quick" { out = out.filter { ($0.test.tags ?? []).contains("quick") } }
        if request.mode == "soak" { out = out.filter { $0.test.requires?.attended != true } }
        return out
    }

    private func mix(_ a: UInt32, _ b: UInt32) -> UInt32 {
        var x = a &* 0x9E37_79B1 ^ (b &+ 0x7F4A_7C15)
        x ^= x >> 15; x = x &* 0x85EB_CA6B; x ^= x >> 13
        return x == 0 ? 1 : x
    }

    private func hash(_ s: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for b in s.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return h
    }

    private func base(cycle: Int) -> [PlannedTest] {
        var items = selected()
        let soak = request.mode == "soak"
        if soak && cycle > 0 {
            // A different order every pass, decided by the run's seed so the run can be repeated.
            var state = mix(request.seed, UInt32(cycle))
            for i in stride(from: items.count - 1, to: 0, by: -1) {
                state = mix(state, UInt32(i))
                items.swapAt(i, Int(state % UInt32(i + 1)))
            }
        }
        var planned: [PlannedTest] = items.map { item in
            let t = item.test
            var seed = t.guest?.seed ?? 1
            if (t.guest?.seedMode ?? "fixed") == "random" { seed = mix(mix(request.seed, hash(t.id)), UInt32(cycle)) }
            var overrides: [String: String] = [:]
            if let variants = t.soak?.paramVariants, !variants.isEmpty, soak { overrides = variants[cycle % variants.count] }
            return PlannedTest(suite: item.suite, test: t, iteration: cycle, seed: seed, paramOverrides: overrides, calibration: false)
        }
        // Every frame-judged test needs to know which way the screen came out; run the calibration test first when it is not already first.
        if cycle == 0, let cal = catalogue.allTests.first(where: { ($0.test.tags ?? []).contains("calibration") }),
           planned.contains(where: { !($0.test.checkpoints ?? []).isEmpty }),
           planned.first?.test.id != cal.test.id {
            planned.removeAll { $0.test.id == cal.test.id }
            planned.insert(PlannedTest(suite: cal.suite, test: cal.test, iteration: 0, seed: cal.test.guest?.seed ?? 1, paramOverrides: [:], calibration: true), at: 0)
        }
        return planned
    }

    mutating func next(now: Date, started: Date) -> PlannedTest? {
        if request.mode == "soak" {
            if now.timeIntervalSince(started) >= Double(request.soakMinutes) * 60.0 { return nil }
            if queue.isEmpty { cycle += 1; queue = base(cycle: cycle); if queue.isEmpty { return nil } }
            produced += 1
            return queue.removeFirst()
        }
        if queue.isEmpty {
            guard cycle + 1 < max(1, request.repeatCount) else { return nil }
            cycle += 1
            queue = base(cycle: cycle)
            if queue.isEmpty { return nil }
        }
        produced += 1
        return queue.removeFirst()
    }
}
