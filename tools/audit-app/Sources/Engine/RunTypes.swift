//
//  RunTypes.swift
//  What a run is asked to do, and the interface the runner uses to talk to whatever is showing it.
//
import Foundation

struct SurfaceInfo {
    var tv: UnsafeMutableRawPointer
    var tvWidth: Int
    var tvHeight: Int
    var pad: UnsafeMutableRawPointer?
    var padWidth: Int
    var padHeight: Int
    var scale: Double
}

struct ResultRow: Identifiable {
    var id: String
    var title: String
    var result: TestResult
    var reason: String
}

struct QuestionRequest: Identifiable {
    var id = UUID()
    var testId: String
    var testTitle: String
    var questions: [QuestionDef]
    var stimulus: String
}

protocol RunnerHost: AnyObject {
    var isCancelled: Bool { get }
    func status(_ text: String)
    func progress(done: Int, total: Int, current: String)
    func record(_ row: ResultRow)
    /// Shows the questionnaire and waits. nil means the person skipped it.
    func ask(_ request: QuestionRequest) async -> [String: String]?
    /// The render surfaces, created on the main thread and laid out. nil if the UI cannot provide them.
    func surfaces() async -> SurfaceInfo?
    /// Registers the surfaces with the core (main thread). Returns false if it could not.
    func attach(_ surfaces: SurfaceInfo, pad: Bool, to core: CoreDriver) async -> Bool
    /// Notes the moment the person tapped "flag a glitch".
    func takeGlitchFlags() -> [(tNs: UInt64, note: String)]
}
