import SwiftUI

/// One numbered save-state slot for one game.
///
/// Deliberately thin: `savedAt` is read straight off the slot file's own modification
/// date (see `SaveStateStore.slots(for:)`) rather than kept in a separate sidecar record
/// that could drift from what is actually on disk - the same "ask the filesystem, don't
/// keep a second copy of the answer" reasoning `GameContextMenu`'s DLC/update removal
/// already uses in PerGameSettings.swift.
struct SaveStateSlot: Identifiable {
    let number: Int
    let fileURL: URL
    var savedAt: Date?

    var id: Int { number }
    var isOccupied: Bool { savedAt != nil }
}

/// Where save-state slot files live on disk, and the numbering every game shares.
///
/// Namespaced by `GameMetadata.id` - the same string `PerGameSettingsStore` and
/// `MeloControlsOverlay` already key per-game state by (see PerGameSettings.swift and
/// MeloControls.swift's `gameID` parameter) - rather than by `titleId`. `id` is always
/// present (it's the ROM/dump's own filename, assigned in GameManager.loadGames()) while
/// `titleId` is nil whenever the bridge couldn't derive one, and a homebrew build or an
/// unrecognized dump is exactly the kind of thing that would fall into a shared "no title
/// ID" bucket and collide with every other such game's slots. Matching the established
/// convention avoids that for free.
enum SaveStateStore {
    /// "e.g. 1-4" - a small fixed number of slots, not an open-ended list. Raising this
    /// is a one-line change; nothing else here assumes 4 specifically.
    static let slotCount = 4

    /// Documents/SaveStates/<game.id>/ - its own top-level folder, not mixed into ROMs,
    /// covers, or Documents/mlc (the installed-title tree DlcUpdateImport.swift owns),
    /// so nothing here can collide with or complicate cleanup of those.
    static func directory(for gameID: String) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents
            .appendingPathComponent("SaveStates", isDirectory: true)
            .appendingPathComponent(gameID, isDirectory: true)
    }

    static func fileURL(for gameID: String, slot: Int) -> URL {
        directory(for: gameID).appendingPathComponent("slot\(slot).sav", isDirectory: false)
    }

    /// Must run before the first save for a game. `cemu_bridge_save_state`'s own
    /// `WriteSaveFile` (IOSSaveState.cpp) does a plain `fopen(path, "wb")`, which fails
    /// outright - and therefore makes the whole bridge call return false - if the parent
    /// directory doesn't exist yet.
    @discardableResult
    static func ensureDirectoryExists(for gameID: String) -> Bool {
        let dir = directory(for: gameID)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue
        }
        return (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil
    }

    /// Every slot's occupancy + timestamp for one game, read straight from whatever is
    /// actually on disk right now.
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

/// The in-game save-state sheet, opened from EmulatorViewOptimized's top bar. All the
/// actual bridge calls and file I/O happen in the parent view (see its
/// `performSaveState`/`performLoadState` - both dispatch off `Self.saveStateQueue`,
/// never straight from a button action, for the same main-thread-deadlock reason the
/// pause button next to this one already routes through `titlePauseQueue`); this view
/// only renders whatever state it's handed and reports taps back through closures.
struct SaveStateSheet: View {
    let gameTitle: String
    let slots: [SaveStateSlot]
    /// Non-nil while a save/load for that slot number is in flight. Every row's buttons
    /// disable while this is set - not just the busy row's - because the bridge calls
    /// are synchronous and a second one dispatched on the same serial queue would just
    /// sit blocked behind the first, which would read as an unresponsive button if it
    /// were left tappable.
    let busySlot: Int?
    /// Set after every completed save/load/delete, cleared when the sheet is reopened.
    /// This is the one place the "doesn't match this session" refusal reason actually
    /// reaches the screen - without it, a refused load looks identical to a load nobody
    /// ever asked for.
    let statusMessage: String?
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
            List {
                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(MuffinTheme.brownDarkest)
                    }
                }

                Section {
                    ForEach(slots) { slot in
                        row(for: slot)
                    }
                } footer: {
                    // The one place the whole feature's real scope limits are spelled
                    // out honestly, rather than only living in code comments nobody
                    // playing the game will ever read. See cemu_bridge_save_state/
                    // cemu_bridge_load_state's doc comments in CemuBridge.h and the
                    // file-level comment at the top of IOSSaveState.cpp for the full
                    // reasoning behind both sentences below.
                    Text("A save only loads back into this same running game - quitting or relaunching the game (or restarting the app) breaks the match, and a save from before that always fails to load. That's expected, not a bug.\n\nRight after loading, a texture or shader that changed since the save may flash its old contents for a moment. That's a brief visual glitch, not lost data.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Save States - \(gameTitle)")
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
    }

    @ViewBuilder
    private func row(for slot: SaveStateSlot) -> some View {
        let isBusy = busySlot == slot.number
        let disabled = busySlot != nil

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Slot \(slot.number)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(MuffinTheme.brownDarkest)

                Text(subtitle(for: slot))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isBusy {
                ProgressView()
                    .padding(.trailing, 4)
            } else {
                if slot.isOccupied {
                    Button(action: { onLoad(slot.number) }) {
                        Text("Load")
                    }
                    .buttonStyle(MuffinSecondaryButtonStyle())
                    .disabled(disabled)

                    Button(role: .destructive, action: { deleteTarget = slot }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(disabled)
                }

                Button(action: { onSave(slot.number) }) {
                    Text(slot.isOccupied ? "Overwrite" : "Save")
                }
                .buttonStyle(MuffinSecondaryButtonStyle())
                .disabled(disabled)
            }
        }
        .padding(.vertical, 2)
    }

    private func subtitle(for slot: SaveStateSlot) -> String {
        guard let savedAt = slot.savedAt else { return "Empty" }
        return "Saved \(Self.relativeFormatter.localizedString(for: savedAt, relativeTo: Date()))"
    }
}
