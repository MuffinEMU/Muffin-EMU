//
//  Views.swift
//  The screens: set up a run, watch it (with the two surfaces the core draws into), answer the
//  questionnaire after each test, and browse or share the reports.
//
#if os(iOS)
import SwiftUI
import UIKit

@main
struct AuditApp: App {
    @StateObject private var session = AuditSession()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(session)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var session: AuditSession

    var body: some View {
        ZStack {
            TabView {
                SetupView()
                    .tabItem { Label("Run", systemImage: "play.circle") }
                ReportsView()
                    .tabItem { Label("Reports", systemImage: "doc.text") }
                AboutView()
                    .tabItem { Label("About", systemImage: "info.circle") }
            }
            // While a run is going the run screen covers everything; the render surfaces live in it.
            if session.running {
                RunView().transition(.opacity)
            }
        }
        .sheet(item: $session.question) { request in
            QuestionnaireView(request: request)
        }
    }
}

// MARK: - Render surfaces

struct SurfaceHost: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Setup

struct SetupView: View {
    @EnvironmentObject var session: AuditSession
    @State private var mode = "standard"
    @State private var suiteIds: Set<String> = []
    @State private var renderer = "metal"
    @State private var cpu = "auto"
    @State private var pad = false
    @State private var attended = true
    @State private var soakMinutes = 60
    @State private var repeatCount = 1
    @State private var seedText = "1"
    @State private var logProfile = 1

    var body: some View {
        NavigationView {
            Form {
                if let err = session.catalogueError {
                    Section { Text("Catalogue error: \(err)").foregroundColor(.red) }
                }
                Section(header: Text("This build")) {
                    LabeledValue("MuffinEMU", "\(BuildInfo.plist("AuditMuffinRef")) @ \(String(BuildInfo.plist("AuditMuffinSha").prefix(10)))")
                    LabeledValue("Core fingerprint", String(BuildInfo.plist("AuditCoreFingerprint").prefix(16)))
                    LabeledValue("Audit app", "\(BuildInfo.appVersion) (\(BuildInfo.appBuild))")
                }
                Section(header: Text("Suites")) {
                    ForEach(session.catalogue.suites, id: \.suite) { s in
                        Toggle(isOn: Binding(get: { suiteIds.contains(s.suite) }, set: { on in
                            if on { suiteIds.insert(s.suite) } else { suiteIds.remove(s.suite) }
                        })) {
                            VStack(alignment: .leading) {
                                Text(s.title)
                                Text("\(s.tests.count) tests - \(s.tests.reduce(0) { $0 + ($1.estimatedSec ?? 30) } / 60) min").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
                Section(header: Text("Run")) {
                    Picker("Mode", selection: $mode) {
                        Text("Quick").tag("quick"); Text("Standard").tag("standard"); Text("Soak").tag("soak")
                    }.pickerStyle(SegmentedPickerStyle())
                    if mode == "soak" {
                        Stepper("Soak for \(soakMinutes) min", value: $soakMinutes, in: 10...720, step: 10)
                        Text("Repeats the unattended tests in a new order each pass for the time given, with no questions asked. A report is written after every test, so a long run that dies still leaves one.").font(.caption).foregroundColor(.secondary)
                    } else {
                        Stepper("Repeat \(repeatCount) time(s)", value: $repeatCount, in: 1...20)
                    }
                    Toggle("Ask the questions (attended)", isOn: $attended).disabled(mode == "soak")
                    Toggle("Show the GamePad screen too", isOn: $pad)
                }
                Section(header: Text("Core")) {
                    Picker("Renderer", selection: $renderer) { Text("Metal").tag("metal"); Text("Vulkan (MoltenVK)").tag("vulkan") }
                    Picker("CPU", selection: $cpu) { Text("Auto").tag("auto"); Text("Interpreter").tag("interpreter"); Text("Recompiler").tag("recompiler") }
                    Picker("Logging", selection: $logProfile) { Text("Probe only").tag(0); Text("Audit").tag(1); Text("Verbose").tag(2) }
                    HStack { Text("Seed"); TextField("1", text: $seedText).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                }
                Section {
                    Button(action: begin) {
                        HStack { Spacer(); Text("Start").bold(); Spacer() }
                    }.disabled(suiteIds.isEmpty || session.catalogueError != nil)
                    if let last = session.lastReportFolder {
                        Text("Last report: \(last.lastPathComponent)").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("MuffinEMU Audit")
            .onAppear { if suiteIds.isEmpty { suiteIds = Set(session.catalogue.suites.map { $0.suite }) } }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func begin() {
        var r = RunRequest()
        r.mode = mode
        r.suiteIds = suiteIds.sorted()
        r.renderer = renderer
        r.cpu = cpu
        r.padSurface = pad
        r.attended = mode == "soak" ? false : attended
        r.soakMinutes = mode == "soak" ? soakMinutes : 0
        r.repeatCount = repeatCount
        r.seed = UInt32(seedText) ?? 1
        r.logProfile = logProfile
        session.start(r)
    }
}

struct LabeledValue: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        HStack { Text(label); Spacer(); Text(value).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle) }
    }
}

// MARK: - Run

struct RunView: View {
    @EnvironmentObject var session: AuditSession

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            VStack(spacing: 8) {
                surfaces(wide: wide, width: geo.size.width)
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.currentTitle.isEmpty ? "Preparing" : session.currentTitle).font(.headline)
                    Text(session.statusText).font(.subheadline).foregroundColor(.secondary)
                    if session.progressTotal > 0 {
                        ProgressView(value: Double(session.progressDone), total: Double(max(session.progressTotal, 1)))
                    }
                }
                .padding(.horizontal)
                List(session.rows.reversed()) { row in
                    HStack {
                        Text(symbol(row.result)).foregroundColor(color(row.result))
                        VStack(alignment: .leading) {
                            Text(row.title).font(.subheadline)
                            Text(row.reason).font(.caption).foregroundColor(.secondary).lineLimit(2)
                        }
                    }
                }
                .listStyle(PlainListStyle())
                HStack(spacing: 12) {
                    Button(action: { session.flagGlitch() }) {
                        Label("Flag a glitch (\(session.glitchCount))", systemImage: "flag.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(.orange)
                    Button(role: .destructive, action: { session.stop() }) {
                        Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color(UIColor.systemBackground))
        }
    }

    @ViewBuilder private func surfaces(wide: Bool, width: CGFloat) -> some View {
        // Both views are always in the hierarchy so the core has somewhere to draw; the pad view is hidden
        // unless this run uses the GamePad surface.
        HStack(spacing: 8) {
            SurfaceHost(view: session.tvView)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(Color.black)
            SurfaceHost(view: session.padView)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .background(Color.black)
                .frame(width: session.runUsesPad ? nil : 2, height: session.runUsesPad ? nil : 2)
                .opacity(session.runUsesPad ? 1 : 0.01)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: wide ? 260 : 200)
    }

    private func symbol(_ r: TestResult) -> String {
        switch r { case .pass: return "PASS"; case .fail: return "FAIL"; case .skip: return "SKIP"; case .error: return "ERR " }
    }
    private func color(_ r: TestResult) -> Color {
        switch r { case .pass: return .green; case .fail: return .red; case .skip: return .gray; case .error: return .orange }
    }
}

// MARK: - Questionnaire

struct QuestionnaireView: View {
    @EnvironmentObject var session: AuditSession
    let request: QuestionRequest
    @State private var answers: [String: String] = [:]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("What you just saw and heard")) {
                    Text(request.stimulus).font(.callout)
                }
                ForEach(request.questions) { q in
                    Section(header: Text(q.text).textCase(nil).font(.headline)) { input(q) }
                }
            }
            .navigationTitle(request.testTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Skip") { session.resolveQuestion(nil) } }
                ToolbarItem(placement: .confirmationAction) { Button("Submit") { session.resolveQuestion(answers) }.disabled(!complete) }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .interactiveDismissDisabled(true)
    }

    private var complete: Bool {
        request.questions.allSatisfy { ($0.optional ?? false) || $0.type == "text" || answers[$0.id] != nil }
    }

    @ViewBuilder private func input(_ q: QuestionDef) -> some View {
        switch q.type {
        case "yesno":
            Picker("", selection: Binding(get: { answers[q.id] ?? "" }, set: { answers[q.id] = $0 })) {
                Text("Yes").tag("yes"); Text("No").tag("no")
            }.pickerStyle(SegmentedPickerStyle())
        case "scale":
            Picker("", selection: Binding(get: { answers[q.id] ?? "" }, set: { answers[q.id] = $0 })) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag("\($0)") }
            }.pickerStyle(SegmentedPickerStyle())
            HStack { Text("1 = very bad").font(.caption); Spacer(); Text("5 = perfect").font(.caption) }.foregroundColor(.secondary)
        case "choice":
            Picker("", selection: Binding(get: { answers[q.id] ?? "" }, set: { answers[q.id] = $0 })) {
                ForEach(q.options ?? [], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(MenuPickerStyle())
        default:
            TextField("Optional note", text: Binding(get: { answers[q.id] ?? "" }, set: { answers[q.id] = $0 }))
        }
    }
}

// MARK: - Reports

struct ReportEntry: Identifiable {
    var id: URL { url }
    var url: URL
    var verdict: String
    var line: String
}

struct ReportsView: View {
    @EnvironmentObject var session: AuditSession
    @State private var entries: [ReportEntry] = []
    @State private var sharing: [Any]?

    var body: some View {
        NavigationView {
            List {
                if entries.isEmpty { Text("No reports yet. Run the audit and they appear here, and in the Files app under MuffinEMU Audit.").foregroundColor(.secondary) }
                ForEach(entries) { e in
                    NavigationLink(destination: ReportDetailView(url: e.url)) {
                        VStack(alignment: .leading) {
                            Text(e.url.lastPathComponent).font(.subheadline)
                            Text("\(e.verdict.uppercased()) - \(e.line)").font(.caption).foregroundColor(e.verdict == "pass" ? .green : .red)
                        }
                    }
                    .swipeActions {
                        Button("Share") { share(e.url) }.tint(.blue)
                        Button("Delete", role: .destructive) { try? FileManager.default.removeItem(at: e.url); reload() }
                    }
                }
            }
            .navigationTitle("Reports")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Refresh") { reload() } } }
            .onAppear { reload() }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let items = sharing { ShareSheet(items: items) }
        }
    }

    private func reload() {
        let root = AuditSession.reportsRoot()
        let dirs = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).sorted { $0.lastPathComponent > $1.lastPathComponent }
        entries = dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("report.json")),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let summary = obj["summary"] as? [String: Any] else { return nil }
            let counts = summary["counts"] as? [String: Int] ?? [:]
            return ReportEntry(url: dir, verdict: summary["verdict"] as? String ?? "?",
                               line: "\(counts["pass"] ?? 0) pass, \(counts["fail"] ?? 0) fail, \(counts["error"] ?? 0) error, \(counts["skip"] ?? 0) skip")
        }
    }

    private func share(_ dir: URL) {
        // A folder, zipped by the system, so the JSON, the Markdown, the logs and the thumbnails travel together.
        var zipped: URL?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: dir, options: .forUploading, error: &error) { tmp in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(dir.lastPathComponent + ".zip")
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: tmp, to: dest)
            zipped = dest
        }
        sharing = zipped.map { [$0] } ?? [dir.appendingPathComponent("report.json"), dir.appendingPathComponent("report.md")]
    }
}

struct ReportDetailView: View {
    let url: URL
    @State private var text = ""
    @State private var sharing: [Any]?

    var body: some View {
        ScrollView {
            Text(text).font(.system(.footnote, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding()
        }
        .navigationTitle("Report")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Share") { sharing = [url.appendingPathComponent("report.json"), url.appendingPathComponent("report.md")] }
            }
        }
        .onAppear { text = (try? String(contentsOf: url.appendingPathComponent("report.md"), encoding: .utf8)) ?? "report.md is missing" }
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let items = sharing { ShareSheet(items: items) }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("What this is")) {
                    Text("MuffinEMU Audit exercises the emulator on this device with pathological test scenes and records what happened. It is a throwaway tool built against one MuffinEMU revision; the reports are what matter. Install it next to MuffinEMU: it shares nothing with it.")
                }
                Section(header: Text("Where the reports are")) {
                    Text("Files app > On My iPhone/iPad > MuffinEMU Audit > MuffinAuditReports. Each run is a folder with report.json (for tools), report.md (for people), log slices and thumbnails of failed frames.")
                }
                Section(header: Text("Comparing two builds")) {
                    Text("Copy two report.json files to a computer and run tools/audit-app/audit_diff.py known-good.json current.json.")
                }
            }
            .navigationTitle("About")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
#endif
