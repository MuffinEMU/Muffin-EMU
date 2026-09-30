import SwiftUI

/// One numbered save-state slot for one game. `savedAt` is the slot file's modification date
/// (see `SaveStateStore.slots(for:)`), so there is no separate record to drift.
struct SaveStateSlot: Identifiable {
    let number: Int
    let fileURL: URL
    var savedAt: Date?

    var id: Int { number }
    var isOccupied: Bool { savedAt != nil }
}

/// Where save-state slot files live on disk and the numbering every game shares. Namespaced
/// by `GameMetadata.id` (the same key PerGameSettingsStore uses), which is always present,
/// unlike `titleId`.
enum SaveStateStore {
    /// Number of slots per game; nothing else assumes a specific count.
    static let slotCount = 4

    /// Documents/SaveStates/<game.id>/, separate from ROMs, covers and Documents/mlc.
    static func directory(for gameID: String) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents
            .appendingPathComponent("SaveStates", isDirectory: true)
            .appendingPathComponent(gameID, isDirectory: true)
    }

    static func fileURL(for gameID: String, slot: Int) -> URL {
        directory(for: gameID).appendingPathComponent("slot\(slot).sav", isDirectory: false)
    }

    /// Must run before the first save: `WriteSaveFile` (IOSSaveState.cpp) fails if the parent
    /// directory doesn't exist.
    @discardableResult
    static func ensureDirectoryExists(for gameID: String) -> Bool {
        let dir = directory(for: gameID)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue
        }
        return (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil
    }

    /// Every slot's occupancy and timestamp for one game, read from disk.
    static func slots(for gameID: String) -> [SaveStateSlot] {
        (1...slotCount).map { number in
            let url = fileURL(for: gameID, slot: number)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let savedAt = attributes?[.modificationDate] as? Date
            return SaveStateSlot(number: number, fileURL: url, savedAt: savedAt)
        }
    }

    static func delete(gameID: String, slot: Int) {
        try? FileManager.default.removeItem(at: fileURL(for: gameID, slot: slot))
    }
}

/// The result line shown at the top of the save-state sheet. `isWarning` is set by whoever
/// produced the result, so the tone never depends on the wording of the message.
struct SaveStateStatus {
    let message: String
    let isWarning: Bool
}

/// The in-game save-state sheet, opened from EmulatorViewOptimized's top bar. It only renders
/// the state it is given and reports taps through closures; bridge calls and file I/O happen in
/// the parent (off `Self.saveStateQueue`, to avoid main-thread deadlocks).
struct SaveStateSheet: View {
    let gameTitle: String
    let slots: [SaveStateSlot]
    /// Non-nil while a save/load for that slot is in flight. All rows disable meanwhile, since
    /// the bridge calls are synchronous and a second would sit blocked on the same queue.
    let busySlot: Int?
    /// Set after every completed save/load/delete; cleared when the sheet is reopened. This is
    /// where a refused load ("doesn't match this session") reaches the screen.
    let status: SaveStateStatus?
    let onSave: (Int) -> Void
    let onLoad: (Int) -> Void
    let onDelete: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var deleteTarget: SaveStateSlot?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient.ignoresSafeArea()

                List {
                    if let status {
                        Section {
                            // Refusals get a warning tone so they stand out from confirmations.
                            ScreenStatusCallout(
                                tone: status.isWarning ? .warning : .info,
                                message: status.message
                            )
                        }
                    }

                    Section {
                        ForEach(slots) { slot in
                            row(for: slot)
                        }
                    } header: {
                        // The game's name is here because a long title truncates in an inline nav bar.
                        Text(gameTitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(MuffinTheme.brownMid)
                            .textCase(nil)
                    } footer: {
                        Text("Swipe a slot left, or press and hold it, to delete.\n\nA save state only loads back while the same game is still running. Quitting or relaunching the game or the app invalidates it.\n\nAfter loading, some textures may briefly flash their old contents.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Save States")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete this save?",
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let slot = deleteTarget?.number { onDelete(slot) }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("Slot \(deleteTarget?.number ?? 0) will be gone for good.")
            }
        }
        .navigationViewStyle(.stack)
    }

    @ViewBuilder
    private func row(for slot: SaveStateSlot) -> some View {
        let canDelete = slot.isOccupied && busySlot == nil

        // Attach the context menu only when there is something to delete.
        if canDelete {
            rowContent(for: slot)
                .contextMenu {
                    Button(role: .destructive) { deleteTarget = slot } label: {
                        Label("Delete Slot \(slot.number)", systemImage: "trash")
                    }
                }
        } else {
            rowContent(for: slot)
        }
    }

    @ViewBuilder
    private func rowContent(for slot: SaveStateSlot) -> some View {
        let isBusy = busySlot == slot.number
        let disabled = busySlot != nil

        HStack(spacing: 12) {
            ScreenSlotBadge(label: "\(slot.number)", isFilled: slot.isOccupied)

            VStack(alignment: .leading, spacing: 2) {
                Text("Slot \(slot.number)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(MuffinTheme.brownDarkest)

                Text(subtitle(for: slot))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            if isBusy {
                ProgressView()
                    .padding(.trailing, 4)
            } else {
                // Delete is a swipe and a long-press menu, to keep it away from Load.
                if slot.isOccupied {
                    Button(action: { onLoad(slot.number) }) {
                        Text("Load")
                    }
                    .buttonStyle(ScreenRowActionStyle(isProminent: true))
                    .disabled(disabled)
                }

                Button(action: { onSave(slot.number) }) {
                    Text(slot.isOccupied ? "Overwrite" : "Save")
                }
                .buttonStyle(ScreenRowActionStyle())
                .disabled(disabled)
            }
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if slot.isOccupied && !disabled {
                Button(role: .destructive) { deleteTarget = slot } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func subtitle(for slot: SaveStateSlot) -> String {
        guard let savedAt = slot.savedAt else { return "Empty" }
        return "Saved \(Self.relativeFormatter.localizedString(for: savedAt, relativeTo: Date()))"
    }
}
