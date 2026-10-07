import SwiftUI
import UIKit
import Darwin

/// The JIT enablers MuffinEMU can hand off to. Each URL below was checked against the
/// enabler's own source on GitHub:
///   StikDebug     Info.plist registers `stikdebug` and `stikjit`; HomeView.swift handles
///                 host `enable-jit` with a `bundle-id` query item.
///   LiveContainer LiveContainer/Info.plist registers `livecontainer`; LCAppListView.swift
///                 handles host `livecontainer-launch` with `bundle-name` and `jit=true`.
/// SideStore is not offered: its URLHandler.swift only handles backup, install, source,
/// pairing and certificate links, with no JIT link. A person using SideStore can pick
/// Custom URL if they have a link of their own.
enum JITEnabler: String, CaseIterable, Identifiable {
    case none, stikDebug, liveContainer, custom

    static let storageKey = "muffin.jit.enabler"
    static let customURLKey = "muffin.jit.customURL"
    static let customPlaceholder = "myenabler://enable?bundle={bundleId}"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .none: return "None"
        case .stikDebug: return "StikDebug"
        case .liveContainer: return "LiveContainer"
        case .custom: return "Custom URL"
        }
    }

    /// The scheme to ask canOpenURL about; nil when there's nothing fixed to check.
    var scheme: String? {
        switch self {
        case .stikDebug: return "stikdebug"
        case .liveContainer: return "livecontainer"
        case .none, .custom: return nil
        }
    }

    static var current: JITEnabler {
        JITEnabler(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .none
    }

    static func template(for enabler: JITEnabler, custom: String) -> String? {
        switch enabler {
        case .none: return nil
        case .stikDebug: return "stikdebug://enable-jit?bundle-id={bundleId}"
        case .liveContainer: return "livecontainer://livecontainer-launch?bundle-name={bundleId}&jit=true"
        case .custom: return custom.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Fills `{bundleId}` with MuffinEMU's real bundle ID, percent-encoded for a query.
    static func url(for enabler: JITEnabler, custom: String) -> URL? {
        guard var text = template(for: enabler, custom: custom), !text.isEmpty else { return nil }
        let id = Bundle.main.bundleIdentifier ?? ""
        let safe = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        text = text.replacingOccurrences(of: "{bundleId}", with: safe)
        return URL(string: text)
    }
}

enum JITStatus {
    private typealias CsopsFn = @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer?, Int) -> Int32

    /// True when the process carries CS_DEBUGGED, the same flag the core's recompiler
    /// checks (ios_process_is_debugged in CemuBridge.mm). The bridge only latches its own
    /// copy when the engine starts, so the app reads the live flag itself.
    static var isActive: Bool {
        // RTLD_DEFAULT is (void *)-2 on Darwin.
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "csops") else { return false }
        let csops = unsafeBitCast(sym, to: CsopsFn.self)
        var flags: UInt32 = 0
        guard csops(getpid(), 0, &flags, MemoryLayout<UInt32>.size) == 0 else { return false }
        return flags & 0x1000_0000 != 0
    }
}

/// Asks, at most once per launch and never during a game, whether to turn JIT on.
@MainActor
final class JITEnablerPrompter: ObservableObject {
    static let shared = JITEnablerPrompter()

    @Published var showPrompt = false
    @Published var resultNote: String?
    private(set) var enablerName = ""
    private var askedThisLaunch = false
    private var awaitingReturn = false

    /// Call once the library is on screen. `gameRunning` is true while a game is loading,
    /// running or paused.
    func launchCheck(gameRunning: Bool) {
        guard !askedThisLaunch, !gameRunning else { return }
        let enabler = JITEnabler.current
        guard enabler != .none, !JITStatus.isActive else { return }
        askedThisLaunch = true
        enablerName = enabler.name
        showPrompt = true
    }

    func enable() {
        let enabler = JITEnabler.current
        let custom = UserDefaults.standard.string(forKey: JITEnabler.customURLKey) ?? ""
        guard let url = JITEnabler.url(for: enabler, custom: custom) else {
            resultNote = "The \(enabler.name) link isn't valid. Check it in Settings, under JIT enabler."
            return
        }
        awaitingReturn = true
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            Task { @MainActor in
                guard let self, !opened else { return }
                self.awaitingReturn = false
                self.resultNote = "MuffinEMU couldn't open \(enabler.name). Make sure it's installed."
            }
        }
    }

    func dontAskAgain() {
        UserDefaults.standard.set(JITEnabler.none.rawValue, forKey: JITEnabler.storageKey)
    }

    /// Call when the app becomes active again. Checks JIT after the enabler had a moment.
    func appBecameActive() {
        guard awaitingReturn else { return }
        awaitingReturn = false
        Task { @MainActor in
            for _ in 0..<4 {
                if JITStatus.isActive { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            resultNote = JITStatus.isActive
                ? "JIT is active. Games will use the recompiler the next time you start one."
                : "JIT still isn't active. MuffinEMU will use the slower interpreter. You can try again in Settings, under JIT enabler."
        }
    }
}

extension View {
    /// The once-per-launch prompt and the result note.
    func jitEnablerPrompt(blocked: @escaping () -> Bool) -> some View {
        modifier(JITEnablerPromptModifier(blocked: blocked))
    }
}

private struct JITEnablerPromptModifier: ViewModifier {
    /// True while a game is loading, running or paused, or something else is on screen.
    let blocked: () -> Bool
    @ObservedObject private var prompter = JITEnablerPrompter.shared
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task {
                // Let the library settle first, so the alert doesn't land on the launch intro.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                prompter.launchCheck(gameRunning: blocked())
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { prompter.appBecameActive() }
            }
            .alert("JIT isn't active. Enable it with \(prompter.enablerName)?",
                   isPresented: $prompter.showPrompt) {
                Button("Enable") { prompter.enable() }
                Button("Not now", role: .cancel) {}
                Button("Don't ask again", role: .destructive) { prompter.dontAskAgain() }
            } message: {
                Text("JIT lets MuffinEMU run games with the fast recompiler. Without it the slower interpreter runs.")
            }
            .alert("JIT enabler", isPresented: Binding(
                get: { prompter.resultNote != nil },
                set: { if !$0 { prompter.resultNote = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(prompter.resultNote ?? "")
            }
    }
}
