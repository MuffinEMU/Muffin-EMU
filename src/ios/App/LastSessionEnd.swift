// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import Foundation
import SwiftUI

/// Notices, at the next launch, that the last run ended with a game still up and the app on screen:
/// iOS ended the process (nearly always for memory) or it crashed. A stop the player made clears
/// the marker, and a kill from the app switcher is a background kill, which is left alone: that is
/// most often the player's own doing.
///
/// The marker is a few UserDefaults keys written when a title starts loading and removed when it
/// stops. UserDefaults is flushed when the app leaves the foreground (CemuApp), and a jetsam in the
/// foreground comes well after the boot wrote them, so the marker survives the kill it is for.
enum LastSessionEnd {
    private static let gameKey = "muffin.session.runningGame"
    private static let backgroundedKey = "muffin.session.backgrounded"

    struct Notice: Equatable {
        /// The game that was running, as the library shows it.
        let game: String
    }

    /// What the last run left behind. Read once, the first time it is asked for (the library asks before
    /// any title can start), and the marker is cleared so the notice shows once.
    static let fromLastRun: Notice? = {
        let d = UserDefaults.standard
        defer {
            d.removeObject(forKey: gameKey)
            d.removeObject(forKey: backgroundedKey)
        }
        guard let game = d.string(forKey: gameKey) else { return nil }
        if d.bool(forKey: backgroundedKey) { return nil }
        return Notice(game: game)
    }()

    /// GameManager, on every emulation state change. A title that is loading or running is marked; idle and
    /// error (the player stopped it, or the engine ended it and said so) clear the marker.
    static func emulationStateChanged(_ state: EmulationState, game: GameMetadata?) {
        _ = fromLastRun // the old marker is read before a new one can replace it
        let d = UserDefaults.standard
        switch state {
        case .loading, .running, .paused:
            d.set(game.map { $0.displayTitle ?? $0.title } ?? "a game", forKey: gameKey)
            d.set(false, forKey: backgroundedKey)
        case .idle, .error:
            d.removeObject(forKey: gameKey)
            d.removeObject(forKey: backgroundedKey)
        }
    }

    /// ContentView, on every scene phase change. A kill while backgrounded is not reported.
    static func scenePhaseChanged(_ phase: ScenePhase) {
        let d = UserDefaults.standard
        guard d.string(forKey: gameKey) != nil else { return }
        d.set(phase == .background, forKey: backgroundedKey)
    }
}

/// One line in the library after a run that ended on its own, with the usual cause and the one place to
/// send the log. Closes for the session.
struct LibraryLastSessionBanner: View {
    let notice: LastSessionEnd.Notice
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MuffinTheme.cautionText)
                .accessibilityHidden(true)
            Text("MuffinEMU closed on its own last time, while \(notice.game) was running. That's usually memory: lower the resolution under Settings > Graphics and close other apps. The engine's log from that run is still here.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(MuffinTheme.brownDarkest)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if !BugReport.logFiles.isEmpty {
                Button("Share log") { DocumentImport.presentShare(BugReport.logFiles) }
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .buttonStyle(MuffinSecondaryButtonStyle())
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MuffinTheme.brownMid)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MuffinTheme.formGround, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MuffinTheme.cautionText.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
