import SwiftUI
import UIKit
import AVFoundation

/// "Record audio" in the HOME menu: saves the game's TV sound to an M4A (AAC) file.
///
/// The audio itself is copied and encoded inside the core (audio/iOSAudioRecorder.mm, reached
/// through cemu_bridge_audio_record_*), so what the player hears is untouched. This side picks the
/// file name, keeps the clock for the red indicator, adds the title and comment tags once the file is
/// finished, and offers to share it.
///
/// Files go to Documents/Recordings, which the Files app shows (On My iPad/iPhone > MuffinEMU).
@MainActor
final class AudioRecorder: ObservableObject {
    static let shared = AudioRecorder()

    /// Settings > Audio > "Save all audio automatically": every game session is recorded from the
    /// moment it runs, and again after the app comes back to the foreground, without touching the
    /// HOME menu toggle.
    static let autoRecordKey = "muffin.audio.autoRecord"
    static var autoRecordEnabled: Bool { UserDefaults.standard.bool(forKey: autoRecordKey) }

    /// Starts a recording when auto-save is on and none is running.
    func autoStartIfEnabled(gameName: String) {
        guard Self.autoRecordEnabled, !isRecording else { return }
        start(gameName: gameName)
    }

    struct Finished: Identifiable, Equatable {
        let id = UUID()
        let url: URL
    }

    @Published private(set) var isRecording = false
    /// Whole seconds of audio recorded so far.
    @Published private(set) var elapsed = 0
    /// Set when a recording has been written, until the notice is dismissed.
    @Published var finished: Finished?
    /// Set when a recording could not be started or produced nothing.
    @Published var failureMessage: String?

    private var timer: Timer?
    private var gameName = ""
    private var url: URL?

    private init() {}

    static var recordingsFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Recordings", isDirectory: true)
    }

    func toggle(gameName: String) {
        if isRecording { stop() } else { start(gameName: gameName) }
    }

    func start(gameName: String) {
        guard !isRecording else { return }
        let folder = Self.recordingsFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            failureMessage = "Couldn't create the Recordings folder."
            return
        }
        let stamp = Self.fileStamp.string(from: Date())
        let url = folder.appendingPathComponent("\(Self.safeFileName(gameName)) \(stamp).m4a")
        let started = url.path.withCString { cemu_bridge_audio_record_start($0) }
        guard started else {
            failureMessage = "Couldn't start recording."
            return
        }
        self.url = url
        self.gameName = gameName
        finished = nil
        failureMessage = nil
        elapsed = 0
        isRecording = true
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.elapsed = Int(cemu_bridge_audio_record_seconds())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops and finishes the file. Safe to call when nothing is recording. Also used when the game
    /// quits and when the app leaves the foreground, so a recording is always closed properly.
    func stop() {
        guard isRecording, let url else { return }
        isRecording = false
        timer?.invalidate()
        timer = nil
        self.url = nil
        let title = gameName
        // Closing the file waits for the encoder, so it runs off the main thread. A background task keeps
        // the app alive for it when the stop comes from leaving the foreground.
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Finish audio recording") {
            UIApplication.shared.endBackgroundTask(task)
        }
        let backgroundTask = task
        DispatchQueue.global(qos: .userInitiated).async {
            cemu_bridge_audio_record_stop()
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            let usable = size > 0
            if usable { Self.addTags(to: url, title: title) }
            Task { @MainActor in
                if usable {
                    self.finished = Finished(url: url)
                } else {
                    try? FileManager.default.removeItem(at: url)
                    self.failureMessage = "Nothing was recorded. The game didn't play any sound."
                }
                if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            }
        }
    }

    // MARK: Tags

    /// Title, artist and comment, written by re-wrapping the finished file without re-encoding it.
    /// Best effort: if it fails the untagged recording is kept as it is.
    nonisolated private static func addTags(to url: URL, title: String) {
        func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            item.extendedLanguageTag = "und"
            return item
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("tagged-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: temp) }
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return }
        export.outputURL = temp
        export.outputFileType = .m4a
        export.metadata = [
            item(.commonIdentifierTitle, title),
            item(.commonIdentifierArtist, "MuffinEMU"),
            item(.iTunesMetadataUserComment, "Recorded in MuffinEMU"),
        ]
        let done = DispatchSemaphore(value: 0)
        export.exportAsynchronously { done.signal() }
        done.wait()
        guard export.status == .completed,
              (try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int) ?? 0 > 0 else { return }
        _ = try? FileManager.default.replaceItemAt(url, withItemAt: temp)
    }

    // MARK: Names

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()

    /// A game name made safe for a file name: no path separators or characters Files dislikes.
    static func safeFileName(_ name: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:?*\"<>|%").union(.controlCharacters)
        let cleaned = name.components(separatedBy: banned).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
        let trimmed = String(cleaned.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return trimmed.isEmpty ? "Recording" : trimmed
    }
}

// MARK: - Views

/// The small red "Recording 0:42" pill, shown over the game while a recording runs.
struct RecordingIndicator: View {
    @ObservedObject private var recorder = AudioRecorder.shared

    var body: some View {
        if recorder.isRecording {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 7, height: 7)
                Text("Recording \(Self.clock(recorder.elapsed))")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.red))
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Recording audio, \(recorder.elapsed) seconds")
        }
    }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// The notice that follows a recording, with a Share button, and the line shown when one fails.
/// Attached high in the view tree so it still appears after the game has been quit.
struct AudioRecordingNoticeModifier: ViewModifier {
    @ObservedObject private var recorder = AudioRecorder.shared
    @State private var sharing: AudioRecorder.Finished?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) { notice }
            .sheet(item: $sharing) { item in
                ActivityShareSheet(items: [item.url])
            }
    }

    @ViewBuilder private var notice: some View {
        if let finished = recorder.finished {
            card(message: "Recording saved to Files, in the Recordings folder.") {
                Button("Share") {
                    sharing = finished
                    recorder.finished = nil
                }
                .accessibilityHint("Saves the recording to Files, sends it by AirDrop and more.")
                Button("Dismiss") { recorder.finished = nil }
            }
            .id(finished.id)
            // Long enough to read and act on, short enough not to sit over the game.
            .task(id: finished.id) {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if recorder.finished?.id == finished.id { recorder.finished = nil }
            }
        } else if let message = recorder.failureMessage {
            card(message: message) {
                Button("OK") { recorder.failureMessage = nil }
            }
            .task(id: message) {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if recorder.failureMessage == message { recorder.failureMessage = nil }
            }
        }
    }

    private func card<Buttons: View>(message: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            buttons()
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.85)))
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .transition(.opacity)
        .accessibilityElement(children: .contain)
    }
}

/// UIActivityViewController, so the recording can go to Files, AirDrop, Messages and so on.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
