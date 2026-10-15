// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI
import UIKit

/// "Record screen" in the HOME menu: saves the picture the game is showing to an MP4, with the game's sound.
///
/// The picture is taken inside the renderer (ios/Bridge/IOSScreenRecorder.mm, reached through
/// cemu_bridge_screen_record_*), at 1080p or higher, so it holds neither the on-screen
/// controls nor this app's overlays. Which screen it follows is the main output, the TV or the GamePad
/// according to the Screen Layout, and a layout change mid-recording keeps recording the same file at
/// the size it started with. This side picks the file name, keeps the clock for the red indicator, watches
/// the free space and the encoder, and reports the result through the same notice as Record audio.
///
/// Files go to Documents/Recordings, next to Record audio's, which the Files app shows.
@MainActor
final class ScreenRecorder: ObservableObject {
    static let shared = ScreenRecorder()

    /// A recording stops, and a new one will not start, with less than this much storage free.
    static let minimumFreeBytes = 500 * 1024 * 1024

    @Published private(set) var isRecording = false
    /// Whole seconds recorded so far.
    @Published private(set) var elapsed = 0

    private var timer: Timer?
    private var url: URL?
    /// A stop is still closing the file on its background queue; a new recording waits for it.
    private var isFinishing = false

    private init() {}

    func toggle(gameName: String) {
        if isRecording { stop() } else { start(gameName: gameName) }
    }

    func start(gameName: String) {
        guard !isRecording else { return }
        let audio = AudioRecorder.shared
        guard !isFinishing else {
            audio.failureMessage = "Still saving the last recording. Try again in a moment."
            return
        }
        guard Self.freeBytes() >= Self.minimumFreeBytes else {
            audio.failureMessage = "Not enough storage to record. Free up some space and try again."
            return
        }
        let folder = AudioRecorder.recordingsFolder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            audio.failureMessage = "Couldn't create the Recordings folder."
            return
        }
        let stamp = Self.fileStamp.string(from: Date())
        let url = folder.appendingPathComponent("\(AudioRecorder.safeFileName(gameName)) \(stamp).mp4")
        guard url.path.withCString({ cemu_bridge_screen_record_start($0) }) else {
            audio.failureMessage = "Couldn't start recording."
            return
        }
        self.url = url
        audio.finished = nil
        audio.failureMessage = nil
        elapsed = 0
        isRecording = true
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard isRecording else { return }
        elapsed = Int(cemu_bridge_screen_record_seconds())
        if cemu_bridge_screen_record_failed() {
            stop(notice: "The recording stopped because the video couldn't be written.")
        } else if Self.freeBytes() < Self.minimumFreeBytes {
            stop(notice: "The recording stopped because storage is almost full. What was recorded is saved in the Recordings folder.")
        }
    }

    /// Stops and finishes the file. Safe to call when nothing is recording. Also used when the game quits and
    /// when the app leaves the foreground, so a recording is always closed properly. `notice` replaces the
    /// usual "saved" message when the recording ended for a reason the player should know.
    func stop(notice: String? = nil) {
        guard isRecording, let url else { return }
        isRecording = false
        isFinishing = true
        timer?.invalidate()
        timer = nil
        self.url = nil
        // Closing the file waits for the encoder, so it runs off the main thread. A background task keeps
        // the app alive for it when the stop comes from leaving the foreground.
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Finish screen recording") {
            UIApplication.shared.endBackgroundTask(task)
        }
        let backgroundTask = task
        DispatchQueue.global(qos: .userInitiated).async {
            let written = cemu_bridge_screen_record_stop()
            Task { @MainActor in
                ScreenRecorder.shared.isFinishing = false
                let audio = AudioRecorder.shared
                if !written {
                    audio.failureMessage = notice ?? "Nothing was recorded."
                } else if let notice {
                    audio.failureMessage = notice
                } else {
                    audio.finished = AudioRecorder.Finished(url: url)
                }
                if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            }
        }
    }

    private static func freeBytes() -> Int {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity ?? Int.max
    }

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter
    }()
}
