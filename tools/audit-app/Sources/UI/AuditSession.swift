//
//  AuditSession.swift
//  The object the screens watch and the runner reports to: run state, the render surfaces, the
//  questionnaire hand-off and the "flag a glitch" button.
//
#if os(iOS)
import SwiftUI
import UIKit

/// The view the core draws into. The core needs the view's own layer to be a CAMetalLayer.
final class MetalSurfaceView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
}

final class AuditSession: ObservableObject, RunnerHost {
    // MARK: Screen state (main thread only)
    @Published var statusText = "Ready"
    @Published var progressDone = 0
    @Published var progressTotal = 0
    @Published var currentTitle = ""
    @Published var rows: [ResultRow] = []
    @Published var running = false
    @Published var question: QuestionRequest?
    @Published var lastReportFolder: URL?
    @Published var catalogueError: String?
    @Published var glitchCount = 0
    @Published var runUsesPad = false

    // MARK: Catalogue
    private(set) var catalogue = Catalogue(suites: [])
    private(set) var catalogueHash = ""
    private(set) var detector = AnomalyDetector(patterns: [])

    // MARK: Surfaces
    let tvView = MetalSurfaceView()
    let padView = MetalSurfaceView()

    // MARK: Cross-thread state
    private let lock = NSLock()
    private var cancelFlag = false
    private var flags: [(tNs: UInt64, note: String)] = []
    private var answerContinuation: CheckedContinuation<[String: String]?, Never>?
    private var runTask: Task<Void, Never>?

    init() {
        tvView.backgroundColor = .black
        padView.backgroundColor = .black
        loadCatalogue()
    }

    func loadCatalogue() {
        var files: [(name: String, data: Data)] = []
        var raw: [Data] = []
        let urls = (Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Catalogue") ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            if url.lastPathComponent == "anomaly-patterns.json" {
                detector = AnomalyDetector.load(data: data)
                continue
            }
            files.append((url.lastPathComponent, data))
            raw.append(data)
        }
        do {
            let c = try Catalogue.load(files: files)
            catalogue = c
            catalogueHash = c.contentHash(rawFiles: raw)
            catalogueError = nil
        } catch {
            catalogueError = "\(error)"
        }
    }

    // MARK: Run control

    func start(_ request: RunRequest) {
        guard !running else { return }
        guard let rpx = Bundle.main.url(forResource: "audit", withExtension: "rpx") else {
            statusText = "audit.rpx is missing from the app bundle; nothing to run."
            return
        }
        lock.lock(); cancelFlag = false; flags.removeAll(); lock.unlock()
        running = true
        rows = []
        progressDone = 0
        progressTotal = 0
        glitchCount = 0
        runUsesPad = request.padSurface
        lastReportFolder = nil
        statusText = "Starting..."

        let folder = Self.reportsRoot().appendingPathComponent(Self.folderName(), isDirectory: true)
        let runner = AuditRunner(catalogue: catalogue, detector: detector, catalogueHash: catalogueHash, request: request, host: self,
                                 rpxPath: rpx.path, reportDir: folder)
        runTask = Task { [weak self] in
            let url = await runner.run()
            await MainActor.run {
                self?.running = false
                self?.lastReportFolder = url
            }
        }
    }

    func stop() {
        lock.lock(); cancelFlag = true; lock.unlock()
        statusText = "Stopping after the current step..."
        // A pending questionnaire must not keep the run waiting.
        DispatchQueue.main.async { [weak self] in self?.resolveQuestion(nil) }
    }

    func flagGlitch() {
        let ns = CoreDriver.shared.initialized ? CoreDriver.shared.nowNs : 0
        lock.lock(); flags.append((ns, "")); lock.unlock()
        glitchCount += 1
    }

    static func reportsRoot() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("MuffinAuditReports", isDirectory: true)
    }

    static func folderName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let sha = String(BuildInfo.plist("AuditMuffinSha").prefix(7))
        return "\(f.string(from: Date()))-\(sha)-\(Platform.machine.replacingOccurrences(of: ",", with: "_"))"
    }

    // MARK: RunnerHost

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelFlag
    }

    func status(_ text: String) {
        DispatchQueue.main.async { [weak self] in self?.statusText = text }
    }

    func progress(done: Int, total: Int, current: String) {
        DispatchQueue.main.async { [weak self] in
            self?.progressDone = done
            self?.progressTotal = total
            self?.currentTitle = current
        }
    }

    func record(_ row: ResultRow) {
        DispatchQueue.main.async { [weak self] in self?.rows.append(row) }
    }

    func takeGlitchFlags() -> [(tNs: UInt64, note: String)] {
        lock.lock(); defer { lock.unlock() }
        let out = flags
        flags.removeAll()
        return out
    }

    func ask(_ request: QuestionRequest) async -> [String: String]? {
        await withCheckedContinuation { (continuation: CheckedContinuation<[String: String]?, Never>) in
            DispatchQueue.main.async {
                self.answerContinuation = continuation
                self.question = request
            }
        }
    }

    /// Called by the questionnaire sheet. nil = skipped.
    func resolveQuestion(_ answers: [String: String]?) {
        guard let c = answerContinuation else { question = nil; return }
        answerContinuation = nil
        question = nil
        c.resume(returning: answers)
    }

    func surfaces() async -> SurfaceInfo? {
        // The render view has to be on screen with a real size before the core can draw into it.
        for _ in 0..<100 {
            let ready = await MainActor.run { self.tvView.window != nil && self.tvView.bounds.width > 8 && self.tvView.bounds.height > 8 }
            if ready { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return await MainActor.run {
            guard self.tvView.window != nil, self.tvView.bounds.width > 8 else { return nil }
            let scale = Double(self.tvView.window?.screen.scale ?? UIScreen.main.scale)
            let padReady = self.padView.window != nil && self.padView.bounds.width > 8
            return SurfaceInfo(tv: Unmanaged.passUnretained(self.tvView).toOpaque(),
                               tvWidth: Int(self.tvView.bounds.width.rounded()), tvHeight: Int(self.tvView.bounds.height.rounded()),
                               pad: padReady ? Unmanaged.passUnretained(self.padView).toOpaque() : nil,
                               padWidth: Int(self.padView.bounds.width.rounded()), padHeight: Int(self.padView.bounds.height.rounded()),
                               scale: scale)
        }
    }

    func attach(_ surfaces: SurfaceInfo, pad: Bool, to core: CoreDriver) async -> Bool {
        await MainActor.run {
            // A previous boot's sublayers must not sit on top of the next one's output.
            self.tvView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            core.attachTV(view: surfaces.tv, widthPoints: surfaces.tvWidth, heightPoints: surfaces.tvHeight, scale: surfaces.scale)
            if pad, let p = surfaces.pad {
                self.padView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
                core.attachPad(view: p, widthPoints: surfaces.padWidth, heightPoints: surfaces.padHeight, scale: surfaces.scale)
            }
            return true
        }
    }
}
#endif
