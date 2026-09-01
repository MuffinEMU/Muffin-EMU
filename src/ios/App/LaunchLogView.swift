import SwiftUI
import Combine

/// Drains the engine's in-app log ring (see `Cemu/Logging/IOSLiveLog.h`) into something
/// SwiftUI can render, and nothing more.
///
/// Polled rather than pushed, for the reason spelled out in IOSLiveLog.h: the engine
/// logs from the title thread, the GPU thread and any number of coreinit threads, and a
/// callback per line would mean a main-actor hop per line at whatever rate the RPL
/// loader feels like. Draining on a timer from the main thread instead means the UI's
/// cost is bounded by the UI's own cadence, and a stalled reader costs the engine
/// nothing at all.
///
/// 10 Hz deliberately. Fast enough that the log reads as live while a boot is moving,
/// slow enough that a burst of a few hundred lines (the HLE export scan) is one
/// SwiftUI update rather than a few hundred.
@MainActor
final class LaunchLogStore: ObservableObject {
    /// Newest last, which is the order they are rendered in and the order they scroll
    /// in. Capped independently of the C ring: this is the render list, and SwiftUI
    /// does not need more rows than a person can scroll back through.
    @Published private(set) var lines: [String] = []
    /// Lines the C ring evicted before this store reached them. Shown rather than
    /// swallowed - a gap the reader knows about is worth more than a tidy list that
    /// quietly is not the whole boot.
    @Published private(set) var droppedLines: UInt64 = 0

    private static let maxRenderedLines = 600

    private var cursor: UInt64 = 0
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        drain()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.drain() }
        }
        // .common, not the default run-loop mode: the default mode stops firing while a
        // scroll view is tracking a drag, which is exactly when someone is reading back
        // through the log and would notice it freeze.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func drain() {
        var dropped: UInt64 = 0
        // The returned buffer is thread-local storage owned by the C side and valid
        // only until the next drain on this thread, so String(cString:) copying it
        // immediately is the contract, not a convenience.
        let chunk = withUnsafeMutablePointer(to: &cursor) { cursorPtr in
            withUnsafeMutablePointer(to: &dropped) { droppedPtr in
                String(cString: ios_live_log_drain(cursorPtr, droppedPtr))
            }
        }
        if dropped > 0 {
            droppedLines += dropped
        }
        guard !chunk.isEmpty else { return }

        lines.append(contentsOf: chunk.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        if lines.count > Self.maxRenderedLines {
            lines.removeFirst(lines.count - Self.maxRenderedLines)
        }
    }
}

/// The on-screen launch log: what the engine is doing, with timestamps, while a title
/// boots.
///
/// This exists because on a sideloaded build under LiveContainer there is no console, no
/// debugger and no practical way to read log.txt without backgrounding the app - so a
/// boot that stalls, or one that finishes and renders black, looks identical from the
/// device: a black rectangle and a UI that still animates. Every diagnosis in this port
/// so far has needed a log pulled off the device and mailed to someone. This puts the
/// same timeline on the glass.
///
/// Shown during loading only, per the setting that gates it. Once a title is running the
/// log is noise over the picture, and the picture is the point.
struct LaunchLogView: View {
    @ObservedObject var store: LaunchLogStore
    /// Nil while the log is the whole screen (booting). Set once there is something
    /// behind it worth seeing, so the overlay can dim rather than cover.
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MuffinTheme.pixelBlue)

                Text("Launch log")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))

                if store.droppedLines > 0 {
                    Text("\(store.droppedLines) earlier lines dropped")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundColor(MuffinTheme.blushPink)
                }

                Spacer()

                Text("\(store.lines.count) lines")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.55))

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(store.lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundColor(colour(for: line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                // Follows the tail as it grows, which is the behaviour that makes a live
                // log readable at all. Keyed on the count rather than the last line's
                // text, so two identical consecutive lines still scroll.
                .onChange(of: store.lines.count) { count in
                    guard count > 0 else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color.black.opacity(0.82))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    /// Severity by content, not by log level: the engine emits nearly all of this at
    /// LogType::Force (that is what survives a build with no log-category UI), so the
    /// level carries no signal and the text is all there is. Kept deliberately narrow -
    /// the point is to make the handful of lines that decide a boot findable in a wall
    /// of scrolling text, not to colour it in.
    private func colour(for line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("crash") || lower.contains("failed") || lower.contains("error")
            || lower.contains("dropped a frame") || lower.contains("not present")
            // The decryption failure. Red because it is the line that explains why an
            // encrypted game did not start, and it is the one the user can act on.
            || lower.contains("no key in keys.txt decrypts it") {
            return MuffinTheme.blushPink
        }
        if lower.contains("presented the first frame") || lower.contains("run title")
            || lower.contains("first swap request") || lower.contains("cleared the empty frame")
            // "launching real title <id>" is the proof that a decrypted disc image
            // mounted and was resolved to an actual title, as opposed to falling through
            // to the standalone-executable path.
            || lower.contains("launching real title")
            // Homebrew's equivalent of the GX2 swap marker: proof that the rom itself
            // drew a frame and handed it over, on the OSScreen path GX2 never touches.
            || lower.contains("osscreenflipbuffersex") {
            return .green
        }
        if lower.contains("ios display:") || lower.contains("ios data path")
            || lower.contains("keys.txt reloaded") || lower.contains("title list initialized") {
            return MuffinTheme.pixelBlue
        }
        return .white.opacity(0.72)
    }
}
