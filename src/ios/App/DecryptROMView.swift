import SwiftUI

/// Decrypt-to-Files: Void's ask was either replace the encrypted ROM in place, or
/// export a decrypted copy and keep using the encrypted original. Only the second is
/// implemented - replacing a user's only copy of a legally-owned dump in place, where a
/// crash or a full disk mid-write could destroy it with nothing left to recover, isn't
/// something to ship without a device to actually test the failure paths on. Exporting
/// leaves the encrypted original completely untouched and gets the same practical
/// result (a plain copy you can move, share, or open in another app) at a fraction of
/// the risk.
///
/// Destination is a fixed, predictable place - Documents/Decrypted/<gameID>/ - rather
/// than a folder picker: UIFileSharingEnabled is already on (see the AlternateIcons
/// plist comment), so it's already visible and movable from Files without building a
/// second picker flow that would need its own security-scoped-URL handling.
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

    /// Mirrors the IOS_DECRYPT_* enum in IOSTitleDecrypt.cpp - kept as a duplicated
    /// literal rather than a shared header constant because the C bridge only exposes
    /// the raw int (see CemuBridgeDecryptProgress.result_status), the same tradeoff
    /// CemuBridgeStatus's Swift-side callers already accept.
    var isSuccess: Bool { completed && resultStatus == 0 }
}

/// Only disc images actually go through FSTVolume's decryption - a folder dump is
/// already plain files, .rpx/.elf homebrew was never encrypted, and .wuhb is its own
/// container format FSTVolume doesn't open. Offering this action on any of those would
/// either no-op or fail in a way that looks like a bug rather than "not applicable."
func gameSupportsDecryptToFiles(romPath: String) -> Bool {
    let ext = (romPath as NSString).pathExtension.lowercased()
    return ext == "wud" || ext == "wux" || ext == "wua"
}

/// The two shapes a decrypt can come out in - see cemu_bridge_start_decrypt's `toWua`
/// argument in CemuBridge.h for what each one actually produces on disk.
enum DecryptFormat {
    case rawSource
    case wua

    var toWua: Bool { self == .wua }
    var navigationTitle: String { self == .wua ? "Decrypt to WUA" : "Decrypt to Raw Source" }
}

struct DecryptROMView: View {
    let game: GameMetadata
    @Environment(\.dismiss) private var dismiss

    /// nil until the user picks one - see the format-choice screen in `body` below.
    @State private var format: DecryptFormat?
    @State private var progress = DecryptProgress()
    @State private var pollTimer: Timer?
    @State private var destinationPath: String = ""

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
        .onDisappear { stopPolling() }
    }

    /// Shown first, before anything starts: "decrypt to raw source" (the existing
    /// folder-tree export) vs. "decrypt to wua" (a single portable archive file).
    private var formatChoiceBody: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "lock.open.fill")
                .font(.system(size: 40))
                .foregroundColor(MuffinTheme.pixelBlue)
            Text("Decrypt \(game.title)")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("The encrypted original is never touched either way.")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Button {
                    format = .rawSource
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Decrypt to Raw Source")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("A code/, content/, meta/ folder - importable and bootable as-is.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(MuffinSecondaryButtonStyle())

                Button {
                    format = .wua
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Decrypt to WUA")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("A single portable .wua archive file.")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(MuffinSecondaryButtonStyle())
            }
            .padding(.horizontal, 24)

            Spacer()

            Button("Cancel", role: .cancel) { dismiss() }
                .padding(.bottom, 8)
        }
        .padding()
        .navigationTitle("Decrypt")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func decryptingBody(_ chosenFormat: DecryptFormat) -> some View {
        VStack(spacing: 20) {
                Spacer()

                if progress.completed {
                    Image(systemName: progress.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(progress.isSuccess ? .green : MuffinTheme.blushPink)
                    Text(progress.isSuccess ? "Decrypted" : "Couldn't Finish")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    if progress.isSuccess {
                        Text("\(progress.filesWritten) files, \(byteCountFormatted(progress.bytesWritten))")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.secondary)
                        Text(chosenFormat.toWua
                            ? "Saved to Files \u{2192} On My iPad/iPhone \u{2192} Muffin \u{2192} Decrypted \u{2192} \(game.id).wua"
                            : "Saved to Files \u{2192} On My iPad/iPhone \u{2192} Muffin \u{2192} Decrypted \u{2192} \(game.title)")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    } else {
                        Text(failureReason(for: progress.resultStatus))
                            .font(.system(size: 13, design: .rounded))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(1.3)
                    Text("Decrypting \(game.title)\u{2026}")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                    Text("\(progress.filesWritten) files, \(byteCountFormatted(progress.bytesWritten)) written")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                    Text("The encrypted original is untouched the whole time.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !progress.completed {
                    Button(role: .destructive) {
                        cemu_bridge_cancel_decrypt()
                    } label: {
                        Text("Cancel")
                    }
                    .padding(.bottom, 8)
                }
            }
        .padding()
        .navigationTitle(chosenFormat.navigationTitle)
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
    }

    private func start(_ chosenFormat: DecryptFormat) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? ""
        destinationPath = chosenFormat.toWua
            ? "\(documentsPath)/Decrypted/\(game.id).wua"
            : "\(documentsPath)/Decrypted/\(game.id)"
        guard cemu_bridge_start_decrypt(game.romPath, destinationPath, chosenFormat.toWua) else {
            // Already running (shouldn't happen - this view owns the one decrypt slot) or
            // a bad path. Either way, show it as a poll result rather than silently doing
            // nothing.
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
        default: return "Something went wrong before decryption could start."
        }
    }
}
