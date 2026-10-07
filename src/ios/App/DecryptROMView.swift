import SwiftUI

/// Exports a decrypted copy to Documents/Decrypted/<id>; the original is never modified.
struct DecryptProgress: Equatable {
    var isRunning = false
    var completed = false
    var resultStatus: Int32 = 0
    var bytesWritten: UInt64 = 0
    var filesWritten: UInt32 = 0

    static func read() -> DecryptProgress {
        var raw = CemuBridgeDecryptProgress()
        cemu_bridge_get_decrypt_progress(&raw)
        return DecryptProgress(
            isRunning: raw.is_running,
            completed: raw.completed,
            resultStatus: Int32(raw.result_status),
            bytesWritten: raw.bytes_written,
            filesWritten: raw.files_written)
    }

    /// Mirrors the IOS_DECRYPT_* enum in IOSTitleDecrypt.cpp.
    var isSuccess: Bool { completed && resultStatus == 0 }
}

/// Only encrypted sources actually go through FSTVolume's decryption - disc images and
/// encrypted game folders (title.tmd, title.tik and .app files). A folder dump is
/// already plain files, .rpx/.elf homebrew was never encrypted, and .wuhb is its own
/// container format FSTVolume doesn't open. Offering this action on any of those would
/// either no-op or fail in a way that looks like a bug rather than "not applicable."
func gameSupportsDecryptToFiles(romPath: String) -> Bool {
    let ext = (romPath as NSString).pathExtension.lowercased()
    if (romPath as NSString).lastPathComponent.lowercased() == "title.tmd" { return true }
    return ext == "wud" || ext == "wux" || ext == "wua"
}

/// The two shapes a decrypt can come out in - see cemu_bridge_start_decrypt's `toWua`
/// argument in CemuBridge.h for what each one actually produces on disk.
enum DecryptFormat {
    case rawSource
    case wua

    var toWua: Bool { self == .wua }
    var navigationTitle: String { self == .wua ? "Decrypt to WUA" : "Decrypt to Folder" }
}

struct DecryptROMView: View {
    let game: GameMetadata
    @Environment(\.dismiss) private var dismiss

    /// nil until the user picks one - see the format-choice screen in `body` below.
    @State private var format: DecryptFormat?
    @State private var progress = DecryptProgress()
    @State private var pollTimer: Timer?
    @State private var destinationPath: String = ""
    @State private var externalHold: ExternalLibrary.Hold?

    var body: some View {
        NavigationView {
            Group {
                if let chosenFormat = format {
                    decryptingBody(chosenFormat)
                } else {
                    formatChoiceBody
                }
            }
        }
        .navigationViewStyle(.stack)
        .onDisappear {
            if format != nil && !progress.completed { cemu_bridge_cancel_decrypt() }
            stopPolling()
        }
    }

    /// Shown first, before anything starts: "decrypt to raw source" (the existing
    /// folder-tree export) vs. "decrypt to wua" (a single portable archive file).
    private var formatChoiceBody: some View {
        ZStack {
            MuffinTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // Straight on the gradient, so the gradient's own inks.
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 40))
                    .foregroundColor(MuffinTheme.onBackgroundAccent)
                Text("Decrypt \(game.title)")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(MuffinTheme.onBackground)
                    .multilineTextAlignment(.center)
                Text("Your original file isn't changed.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundColor(MuffinTheme.onBackgroundMuted)

                // Cards rather than capsule buttons: each choice has a title and a description.
                VStack(spacing: 12) {
                    formatChoice(
                        title: "Decrypt to Folder",
                        detail: "A folder you can import and play directly.",
                        systemImage: "folder.fill"
                    ) { format = .rawSource }

                    formatChoice(
                        title: "Decrypt to WUA",
                        detail: "A single .wua file that's easy to move around.",
                        systemImage: "doc.zipper"
                    ) { format = .wua }
                }
                .padding(.horizontal, 24)

                Spacer()

                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(MuffinSecondaryButtonStyle())
                    .padding(.bottom, 8)
            }
            // Inside the ZStack: padding the ZStack itself pulled the gradient in from the
            // screen edges, leaving a band of plain background around it.
            .padding()
        }
        .navigationTitle("Decrypt")
        .muffinOpaqueNavigationBar()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func formatChoice(title: String,
                             detail: String,
                             systemImage: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            MuffinCard {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(MuffinTheme.accentText)
                        .frame(width: 26)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(MuffinTheme.brownDarkest)
                        Text(detail)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(MuffinTheme.brownMid)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(MuffinTheme.brownMid)
                        .accessibilityHidden(true)
                }
                .padding(14)
            }
        }
        .buttonStyle(ScreenCardButtonStyle())
        .accessibilityLabel("\(title). \(detail)")
    }

    private func decryptingBody(_ chosenFormat: DecryptFormat) -> some View {
        ZStack {
            MuffinTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                // The result on a card, not the bare gradient: it's the part that has to be
                // read (where the file went, or why it failed), and no single text colour
                // reads across every theme's gradient.
                MuffinCard {
                    VStack(spacing: 14) {
                        if progress.completed {
                            Image(systemName: progress.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(progress.isSuccess ? .green : MuffinTheme.alertText)
                            Text(progress.isSuccess ? "Decrypted" : "Couldn't Finish")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(MuffinTheme.brownDarkest)
                            if progress.isSuccess {
                                Text("\(progress.filesWritten) files, \(byteCountFormatted(progress.bytesWritten))")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(MuffinTheme.brownMid)
                                Text(chosenFormat.toWua
                                    ? "Saved to Files \u{2192} On My iPad/iPhone \u{2192} MuffinEMU \u{2192} Decrypted \u{2192} \(game.id).wua"
                                    : "Saved to Files \u{2192} On My iPad/iPhone \u{2192} MuffinEMU \u{2192} Decrypted \u{2192} \(game.title)")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundColor(MuffinTheme.brownMid)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            } else {
                                Text(failureReason(for: progress.resultStatus))
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(MuffinTheme.brownMid)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }
                        } else {
                            ProgressView()
                                .scaleEffect(1.3)
                            Text("Decrypting \(game.title)\u{2026}")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(MuffinTheme.brownDarkest)
                                .multilineTextAlignment(.center)
                            Text("\(progress.filesWritten) files, \(byteCountFormatted(progress.bytesWritten)) written")
                                .font(.system(size: 13, design: .rounded))
                                .foregroundColor(MuffinTheme.brownMid)
                                .monospacedDigit()
                            Text("Your original file isn't changed.")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundColor(MuffinTheme.brownMid)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 520)
                }

                Spacer()

                if !progress.completed {
                    Button(role: .destructive) {
                        cemu_bridge_cancel_decrypt()
                    } label: {
                        Text("Cancel")
                    }
                    .buttonStyle(MuffinSecondaryButtonStyle())
                    .padding(.bottom, 8)
                }
            }
            .padding()
        }
        .navigationTitle(chosenFormat.navigationTitle)
        .muffinOpaqueNavigationBar()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .disabled(!progress.completed)
            }
        }
        .onAppear { start(chosenFormat) }
        .onDisappear {
            if let hold = externalHold { ExternalLibrary.shared.release(hold); externalHold = nil }
        }
    }

    private func start(_ chosenFormat: DecryptFormat) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
        destinationPath = chosenFormat.toWua
            ? "\(documentsPath)/Decrypted/\(game.id).wua"
            : "\(documentsPath)/Decrypted/\(game.id)"
        // A linked game is read off its drive for as long as the decrypt runs.
        if let locationID = game.externalLocationID, externalHold == nil {
            externalHold = ExternalLibrary.shared.acquire(locationID)
        }
        guard cemu_bridge_start_decrypt(game.romPath, destinationPath, chosenFormat.toWua) else {
            if let hold = externalHold { ExternalLibrary.shared.release(hold); externalHold = nil }
            // Already running or a bad path; show it as a failed result.
            progress = DecryptProgress(isRunning: false, completed: true, resultStatus: -1)
            return
        }
        startPolling()
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                let snapshot = DecryptProgress.read()
                if snapshot != progress {
                    progress = snapshot
                }
                if snapshot.completed {
                    stopPolling()
                }
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func byteCountFormatted(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func failureReason(for status: Int32) -> String {
        switch status {
        case 1: return "Couldn't open this file - it may not be a valid disc image."
        case 2: return "No matching key in keys.txt for this disc. Import the right key and try again."
        case 3: return "Couldn't write the decrypted output."
        case 4: return "Cancelled."
        case 6: return "This game folder is missing a readable title.tmd or title.tik, which MuffinEMU needs to decrypt it."
        case 7: return "MuffinEMU couldn't decrypt this game folder. Its title.tik doesn't unlock the .app files - check that title.tmd, title.tik and the .app files are from the same download."
        case 8: return "This game folder is missing one or more .app files listed in its title.tmd."
        case 5: return "Some files couldn't be copied, so the decrypted copy is incomplete. Your original wasn't changed. Free up some space and try again."
        default: return "Decryption couldn't start."
        }
    }
}
