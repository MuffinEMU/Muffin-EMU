import SwiftUI

/// One numbered save-state slot for one game. `savedAt` is the slot file's modification date
/// (see `SaveStateStore.slots(for:)`), so there is no separate record to drift.
struct SaveStateSlot: Identifiable {
    let number: Int
    let fileURL: URL
    var savedAt: Date?
    /// Size of the slot file in bytes. A save holds the game's memory, so a slot is large.
    var byteCount: Int64?

    /// Whether the file can be loaded into the game that is running now. Only meaningful when the slot is occupied.
    var availability: SaveStateAvailability = .loadable

    var id: Int { number }
    var isOccupied: Bool { savedAt != nil }
    var canLoad: Bool { isOccupied && availability == .loadable }
}

/// What a slot's file is, judged from its header by the bridge (`cemu_bridge_save_state_inspect`).
enum SaveStateAvailability {
    /// Taken in this launch of the running game.
    case loadable
    /// Taken before the game (or the app) was last started. Kept on disk, but a save state can't outlive its launch yet.
    case earlierSession
    /// Written by a different game.
    case otherGame
    /// Not a readable save state.
    case unreadable

    init(bridgeStatus: Int32) {
        switch bridgeStatus {
        case 1: self = .loadable
        case 2, 4: self = .earlierSession
        case 3: self = .otherGame
        default: self = .unreadable
        }
    }
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
            let byteCount = (attributes?[.size] as? NSNumber)?.int64Value
            var slot = SaveStateSlot(number: number, fileURL: url, savedAt: savedAt, byteCount: byteCount)
            if savedAt != nil {
                // Reads only the file's header, so this is cheap even though the file is large.
                slot.availability = SaveStateAvailability(bridgeStatus: url.path.withCString { cemu_bridge_save_state_inspect($0) })
            }
            return slot
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

    /// A destructive tap waiting for its confirmation. Both live in one value so the sheet
    /// has a single confirmation dialog; two on one view can swallow each other.
    private enum PendingAction {
        case delete(Int)
        case overwrite(Int)

        var slot: Int {
            switch self {
            case .delete(let slot), .overwrite(let slot): return slot
            }
        }
    }
    @State private var pending: PendingAction?

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

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
                        Text("Swipe a slot left, or press and hold it, to delete.\n\nA save state loads back only while the game keeps running from the launch it was saved in. After you quit or relaunch the game or the app, older saves stay in their slots but can't be loaded yet. Delete them, or save over them.\n\nAfter loading, some textures may briefly flash their old contents.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Save States")
            .muffinOpaqueNavigationBar(MuffinTheme.formGround)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                dialogTitle,
                isPresented: Binding(
                    get: { pending != nil },
                    set: { if !$0 { pending = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(dialogButton, role: .destructive) {
                    switch pending {
                    case .delete(let slot): onDelete(slot)
                    case .overwrite(let slot): onSave(slot)
                    case nil: break
                    }
                    pending = nil
                }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: {
                Text(dialogMessage)
            }
        }
        .navigationViewStyle(.stack)
    }

    private var dialogTitle: String {
        switch pending {
        case .overwrite: return "Overwrite this save?"
        default: return "Delete this save?"
        }
    }

    private var dialogButton: String {
        switch pending {
        case .overwrite: return "Overwrite"
        default: return "Delete"
        }
    }

    private var dialogMessage: String {
        let slot = pending?.slot ?? 0
        switch pending {
        case .overwrite: return "Slot \(slot) will be replaced with the game as it is now. The old save can't be brought back."
        default: return "Slot \(slot) will be gone for good."
        }
    }

    @ViewBuilder
    private func row(for slot: SaveStateSlot) -> some View {
        let canDelete = slot.isOccupied && busySlot == nil

        // Attach the context menu only when there is something to delete.
        if canDelete {
            rowContent(for: slot)
                .contextMenu {
                    Button(role: .destructive) { pending = .delete(slot.number) } label: {
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
                    .foregroundColor(MuffinTheme.secondaryText)
            }

            Spacer(minLength: 8)

            if isBusy {
                ProgressView()
                    .padding(.trailing, 4)
            } else {
                // Delete is a swipe and a long-press menu, to keep it away from Load.
                if slot.canLoad {
                    Button(action: { onLoad(slot.number) }) {
                        Text("Load")
                    }
                    .buttonStyle(ScreenRowActionStyle(isProminent: true))
                    .disabled(disabled)
                    .accessibilityLabel("Load slot \(slot.number)")
                }

                // Overwriting an occupied slot asks first: it sits right beside Load, and the old save is gone for good.
                Button(action: {
                    if slot.isOccupied {
                        pending = .overwrite(slot.number)
                    } else {
                        onSave(slot.number)
                    }
                }) {
                    Text(slot.isOccupied ? "Overwrite" : "Save")
                }
                .buttonStyle(ScreenRowActionStyle())
                .disabled(disabled)
                .accessibilityLabel(slot.isOccupied ? "Overwrite slot \(slot.number)" : "Save to slot \(slot.number)")
            }
        }
        .padding(.vertical, 6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if slot.isOccupied && !disabled {
                Button(role: .destructive) { pending = .delete(slot.number) } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func subtitle(for slot: SaveStateSlot) -> String {
        guard let savedAt = slot.savedAt else { return "Empty" }
        let when = "Saved \(Self.relativeFormatter.localizedString(for: savedAt, relativeTo: Date()))"
        var detail = when
        if let bytes = slot.byteCount, bytes > 0 {
            detail = "\(when) - \(Self.sizeFormatter.string(fromByteCount: bytes))"
        }
        switch slot.availability {
        case .loadable: return detail
        case .earlierSession: return "From an earlier session - can't be loaded yet\n\(detail)"
        case .otherGame: return "Saved by a different game - can't be loaded here\n\(detail)"
        case .unreadable: return "Not a readable save state\n\(detail)"
        }
    }
}
