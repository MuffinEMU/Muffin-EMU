// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import SwiftUI

/// The one-time welcome in the app that was moved to: a new bundle identifier is a new app with an empty
/// container, so the first launch offers to bring everything over from the old MuffinEMU. It shows once,
/// and only where there is nothing here yet; Settings keeps the same import for later.
enum MigrationWelcome {
    static let seenKey = "muffin.migration.welcomeSeen"

    static var shouldOffer: Bool {
        guard !MigrationArchive.isLegacyApp, !UserDefaults.standard.bool(forKey: seenKey) else { return false }
        return containerIsEmpty
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    /// Nothing the player would miss is here: no game files, no Wii U storage, no keys.
    private static var containerIsEmpty: Bool {
        guard let documents = MigrationArchive.documents else { return false }
        let fm = FileManager.default
        for path in ["mlc/mlc01", "mlc/keys.txt", "keys/keys.txt"] {
            if fm.fileExists(atPath: documents.appendingPathComponent(path).path) { return false }
        }
        let roms = documents.appendingPathComponent("Roms", isDirectory: true)
        let games = (try? fm.contentsOfDirectory(atPath: roms.path)) ?? []
        return games.allSatisfy { $0.hasPrefix(".") }
    }
}

struct MigrationWelcomeView: View {
    var onFinished: () -> Void
    @StateObject private var model = MigrationModel()

    var body: some View {
        ZStack {
            MuffinTheme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Text("Welcome to the new MuffinEMU")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text("MuffinEMU has a new app identity. This is a separate app from the one you used before, so it starts empty: your games, saves, keys and settings are still in the old app.")
                            .font(.system(size: 15))
                            .multilineTextAlignment(.center)
                    }

                    MuffinCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Bring your data over")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            Text("In the old MuffinEMU, open Settings, then Move to the new MuffinEMU, and choose Export everything. Then pick that file here. Games can be left out and copied across in Files instead.")
                                .font(.system(size: 14))
                                .foregroundColor(MuffinTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            MigrationImportControls(model: model, showsMessage: true)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(action: onFinished) {
                        Text(model.phase == .idle && model.message != nil && !model.messageIsError ? "Done" : "Not now")
                    }
                    .buttonStyle(MuffinSecondaryButtonStyle())
                    .disabled(model.isBusy || model.phase == .confirming)

                    Text("You can do this later in Settings.")
                        .font(.system(size: 12))
                        .foregroundColor(MuffinTheme.secondaryText)
                }
                .foregroundColor(MuffinTheme.brownDarkest)
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
