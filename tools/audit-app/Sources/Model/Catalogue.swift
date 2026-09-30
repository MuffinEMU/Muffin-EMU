//
//  Catalogue.swift
//  The test catalogue: data, not code. A suite is one JSON file (Catalogue/suite-*.json in the app
//  bundle); adding a file adds a suite, adding an entry to "tests" adds a test. The format is
//  documented in docs/AUDIT.md ("Test catalogue format") and validated in CI by
//  tools/audit-app/validate_catalogue.py.
//
import Foundation

struct SuiteFile: Codable {
    var schema: String
    var suite: String
    var title: String
    var description: String?
    var order: Int?
    var tests: [TestDef]
}

struct TestDef: Codable, Identifiable {
    var id: String
    var title: String
    /// Dotted subsystem names ("render.copy", "audio.output"). The report rolls failures up by these.
    var subsystems: [String]
    /// "guest" runs a test inside audit.rpx; "host" runs an action in the app itself.
    var kind: String
    var guest: GuestSpec?
    var host: HostSpec?
    var requires: Requirements?
    var estimatedSec: Int?
    var timeoutSec: Int?
    var stimulus: String
    var expected: String
    /// What to do outside the tool to see the same thing, in words.
    var reproduce: String?
    var checkpoints: [CheckpointDef]?
    var script: [ScriptStep]?
    var checks: [CheckDef]?
    var questionnaire: [QuestionDef]?
    var soak: SoakSpec?
    var tags: [String]?
}

struct GuestSpec: Codable {
    var test: String
    var params: [String: String]?
    var durationMs: Int?
    /// nil or "fixed" uses `seed`; "random" picks a new seed per run and records it.
    var seedMode: String?
    var seed: UInt32?

    /// "key=value;key=value", sorted so the same parameters always produce the same string.
    func paramString(overrides: [String: String] = [:]) -> String {
        var merged = params ?? [:]
        for (k, v) in overrides { merged[k] = v }
        return merged.keys.sorted().map { "\($0)=\(merged[$0] ?? "")" }.joined(separator: ";")
    }
}

struct HostSpec: Codable {
    /// "reboot_cycle": boot the guest, handshake and stop it, repeatedly.
    var action: String
    var params: [String: String]?
}

struct Requirements: Codable {
    /// Needs frame readback (Metal with the audit hooks).
    var capture: Bool?
    var minTier: Int?
    var apis: [String]?
    var pad: Bool?
    /// Needs a person to listen or look; skipped in unattended soak runs.
    var attended: Bool?
}

struct CheckpointDef: Codable {
    /// The checkpoint name the guest raises. A trailing "*" matches any name with that prefix.
    var name: String
    var capture: CaptureSpec?
    var expect: [Expectation]?

    func matches(_ guestName: String) -> Bool {
        if name.hasSuffix("*") { return guestName.hasPrefix(String(name.dropLast())) }
        return name == guestName
    }
}

struct CaptureSpec: Codable {
    /// "tv", "pad" or both.
    var views: [String]?
    /// Frames to capture at this checkpoint. More than one lets flicker, tearing and frame-order checks run.
    var count: Int?
}

/// One thing a checkpoint asserts about the captured frame(s). `type` picks which fields matter:
///
///   region_color     rect, rgb, tol                      mean colour of the rect
///   quadrants        rect, tl, tr, bl, br, tol           mean colour of each quarter of the rect (null = not asserted)
///   not_black        rect?, maxBlackFraction             the rect is not (mostly) black
///   mean_color       rgb, tol                            whole-frame mean colour
///   orientation      (none)                              measures which way the screen came out; always informational
///   frames_identical maxDistinct                         across a burst, at most this many distinct frame hashes
///   frame_counter    maxTornFraction, maxBackwards       decodes the frame number drawn in the top and bottom strips
struct Expectation: Codable {
    var type: String
    var name: String?
    /// [x, y, w, h], 0...1 across the frame, y measured from the top of the screen as the guest draws it.
    var rect: [Double]?
    var rgb: [Int]?
    var tl: [Int]?
    var tr: [Int]?
    var bl: [Int]?
    var br: [Int]?
    var tol: Int?
    var view: String?
    var maxBlackFraction: Double?
    var maxDistinct: Int?
    var maxTornFraction: Double?
    var maxBackwards: Int?
    /// "fail" (default), "warn" or "info". Info results are recorded and never fail the test.
    var severity: String?
    var note: String?
}

/// A measurement over the whole test rather than one frame.
///
///   audio_window   step, minRms, maxUnderrunFrames, maxDiscontinuities, minPeak, maxPeak
///   memory_growth  maxGrowthMB                           footprint growth across the run
///   frame_pacing   minFps, maxP99Ms, maxLongFraction     present intervals measured on the GPU thread
///   guest_clean    (none)                                the guest reported no errors of its own
struct CheckDef: Codable {
    var type: String
    var name: String?
    var step: Int?
    var minRms: Double?
    var maxUnderrunFrames: Int?
    var maxDiscontinuities: Int?
    var minPeak: Int?
    var maxPeak: Int?
    var maxGrowthMB: Double?
    var minFps: Double?
    var maxP99Ms: Double?
    var maxLongFraction: Double?
    var severity: String?
}

/// One step of an input script (the host drives the emulated GamePad and reads what the guest saw).
///
///   press       button, holdMs, expectHold (VPAD bitmask the guest must report while held)
///   stick       stick ("left" or "right"), x, y, settleMs, tolerance (the guest must report about x, y)
///   touch       x, y (0...1 across the pad screen), settleMs, tolerance in pixels of 1280x720
///   release     let everything go and require the guest to report that
///   wait        holdMs
struct ScriptStep: Codable {
    var action: String
    var label: String?
    var button: String?
    var stick: String?
    var x: Double?
    var y: Double?
    var holdMs: Int?
    var settleMs: Int?
    var expectHold: Int?
    var tolerance: Double?
    var severity: String?
}

struct QuestionDef: Codable, Identifiable {
    var id: String
    var text: String
    /// "yesno", "scale" (1...5), "choice" or "text".
    var type: String
    /// For yesno: the answer that means something was wrong ("yes" or "no").
    var bad: String?
    /// For scale: answers below this are a problem.
    var badBelow: Int?
    var options: [String]?
    var badOptions: [String]?
    /// "fail" (default), "warn" or "info".
    var severity: String?
    var subsystem: String?
    var optional: Bool?
}

struct SoakSpec: Codable {
    /// Relative share of a long run (default 1).
    var weight: Int?
    /// Parameter sets to rotate through on successive runs of this test in a soak.
    var paramVariants: [[String: String]]?
}

// MARK: - Loading

enum CatalogueError: Error, CustomStringConvertible {
    case badSchema(String, String)
    case duplicateTest(String)
    case decode(String, String)

    var description: String {
        switch self {
        case .badSchema(let file, let schema): return "\(file): unsupported schema \(schema)"
        case .duplicateTest(let id): return "duplicate test id \(id)"
        case .decode(let file, let why): return "\(file): \(why)"
        }
    }
}

struct Catalogue {
    static let schema = "muffinaudit.suite/1"

    var suites: [SuiteFile]

    var allTests: [(suite: SuiteFile, test: TestDef)] {
        suites.flatMap { s in s.tests.map { (s, $0) } }
    }

    func test(id: String) -> (suite: SuiteFile, test: TestDef)? {
        allTests.first { $0.test.id == id }
    }

    /// Parses suite files given as (file name, bytes). Sorted by each suite's `order`, then name.
    static func load(files: [(name: String, data: Data)]) throws -> Catalogue {
        var suites: [SuiteFile] = []
        var seen = Set<String>()
        for file in files {
            do {
                let suite = try JSONDecoder().decode(SuiteFile.self, from: file.data)
                guard suite.schema == schema else { throw CatalogueError.badSchema(file.name, suite.schema) }
                for t in suite.tests {
                    if !seen.insert(t.id).inserted { throw CatalogueError.duplicateTest(t.id) }
                }
                suites.append(suite)
            } catch let e as CatalogueError {
                throw e
            } catch {
                throw CatalogueError.decode(file.name, "\(error)")
            }
        }
        suites.sort { ($0.order ?? 100, $0.suite) < ($1.order ?? 100, $1.suite) }
        return Catalogue(suites: suites)
    }

    /// Stable identifier of exactly this catalogue's content, recorded in every report so two reports can say whether
    /// they ran the same tests with the same expectations.
    func contentHash(rawFiles: [Data]) -> String {
        var h: UInt64 = 1469598103934665603
        for data in rawFiles.sorted(by: { $0.count < $1.count || ($0.count == $1.count && $0.lexicographicallyPrecedes($1)) }) {
            for b in data {
                h = (h ^ UInt64(b)) &* 1099511628211
            }
            h = (h ^ 0xFF) &* 1099511628211
        }
        return String(format: "%016llx", h)
    }
}
