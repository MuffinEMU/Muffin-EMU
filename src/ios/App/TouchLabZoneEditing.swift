// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI
import TouchLabCore
import TouchLabUI

// Zone's per-button and per-group editing: where the edits are kept, the session the live pad
// is given while the player edits, and the rows in the Move controls panel.
//
// Kept to its own file so the layout panels and the pad overlay change by a line or two each.
// It imports the package (the one place besides TouchLabPads.swift that does) because the store
// speaks the package's edit types.

/// The edits to Zone's controls, and what is being edited right now.
///
/// Edits are saved once for every game, or, if the player asks, separately for one game
/// (a copy of the shared edits that then changes on its own). The pad reads `edits`; the panel
/// reads and drives the rest. Nothing here is written from the pad's input path except the
/// pad's own edit callbacks, which only run while the player is editing and the pad is inert.
final class ZoneEditStore: ObservableObject {
    static let shared = ZoneEditStore()

    /// Every game's edits, as PadEdits' stored form.
    static let globalKey = "muffin.touchlab.zone.edits"
    /// One game's own edits, present only once the player has chosen a separate layout for it.
    static func gameKey(_ gameID: String) -> String { globalKey + "." + gameID }

    @Published private(set) var edits = PadEdits()
    @Published private(set) var isEditing = false
    @Published private(set) var granularity = PadEditGranularity.control
    @Published private(set) var selection: String?
    @Published private(set) var gameID: String?
    @Published private(set) var isPerGame = false

    /// The live Zone pad, for sizing a pick against the real layout (see `setSelectedScale`).
    weak var scheme: ZonePad?

    private var defaults: UserDefaults { .standard }

    /// Loads the edits that apply to `gameID` (its own, if it has them, else the shared ones).
    func activate(gameID: String?) {
        self.gameID = gameID
        if let gameID, let raw = defaults.string(forKey: Self.gameKey(gameID)) {
            isPerGame = true
            setEdits(PadEdits(encoded: raw))
        } else {
            isPerGame = false
            setEdits(PadEdits(encoded: defaults.string(forKey: Self.globalKey) ?? ""))
        }
    }

    private func setEdits(_ next: PadEdits) {
        if edits != next { edits = next }
    }

    private func persist() {
        let raw = edits.encoded
        if isPerGame, let gameID {
            // Kept even when empty: an empty game layout is "no edits for this game", not "use the shared ones".
            defaults.set(raw, forKey: Self.gameKey(gameID))
        } else if raw.isEmpty {
            defaults.removeObject(forKey: Self.globalKey)
        } else {
            defaults.set(raw, forKey: Self.globalKey)
        }
    }

    // MARK: Editing

    var hasEdits: Bool { !edits.isEmpty }

    func setEditing(_ on: Bool) {
        guard isEditing != on else { return }
        isEditing = on
        if !on { selection = nil }
    }

    func setGranularity(_ next: PadEditGranularity) {
        guard granularity != next else { return }
        granularity = next
        selection = nil
    }

    func select(_ key: String?) {
        if selection != key { selection = key }
    }

    /// The pad's own report: the edits changed, and `final` once the finger lifted.
    fileprivate func padChanged(_ next: PadEdits, final: Bool) {
        setEdits(next)
        if final { persist() }
    }

    /// What the pad needs while editing; nil when not editing.
    var session: PadEditSession? {
        guard isEditing else { return nil }
        return PadEditSession(granularity: granularity, selection: selection,
                              onSelect: { [weak self] in self?.select($0) },
                              onEdits: { [weak self] edits, final in self?.padChanged(edits, final: final) })
    }

    // MARK: The selected control

    var selectionTitle: String? {
        guard let selection else { return nil }
        return scheme?.editTitle(for: selection)
    }

    /// The selected control's (or group's) size as a multiple of its usual one.
    var selectedScale: Double {
        guard let selection else { return 1 }
        return Double(edits[selection].scale)
    }

    static let scaleRange: ClosedRange<Double> = Double(PadEdit.scaleRange.lowerBound)...Double(PadEdit.scaleRange.upperBound)

    /// Resizes the selection, held to what the layout can take: the slider stops where the next
    /// size would touch a neighbour or leave the screen, as a pinch does.
    func setSelectedScale(_ value: Double) {
        guard let selection else { return }
        let now = edits[selection]
        let want = PadEdit(dx: now.dx, dy: now.dy, scale: CGFloat(value))
        let got = scheme?.resolveEdit(want, for: selection, start: now) ?? want.clamped
        guard got != now else { return }
        var next = edits
        next[selection] = got
        edits = next
        persist()
    }

    func resetSelected() {
        guard let selection, edits[selection] != .identity else { return }
        var next = edits
        next[selection] = .identity
        edits = next
        persist()
    }

    func resetAll() {
        edits = PadEdits()
        selection = nil
        persist()
    }

    // MARK: Per game

    /// Turns a separate layout for this game on (starting as a copy of what it has now) or off (back to the shared one).
    func setPerGame(_ on: Bool) {
        guard let gameID, on != isPerGame else { return }
        if on {
            isPerGame = true
            persist()
        } else {
            defaults.removeObject(forKey: Self.gameKey(gameID))
            isPerGame = false
            setEdits(PadEdits(encoded: defaults.string(forKey: Self.globalKey) ?? ""))
        }
        selection = nil
    }
}

/// The rows Zone adds to the Move controls panel.
struct ZoneEditRows: View {
    let gameID: String?

    @ObservedObject private var store = ZoneEditStore.shared
    @State private var confirmingResetAll = false

    var body: some View {
        VStack(spacing: 10) {
            PanelToggle(title: "Move and resize buttons",
                        isOn: Binding(get: { store.isEditing }, set: { store.setEditing($0) }))

            if store.isEditing {
                Picker("Pick", selection: Binding(get: { store.granularity }, set: { store.setGranularity($0) })) {
                    Text("One button").tag(PadEditGranularity.control)
                    Text("Whole group").tag(PadEditGranularity.group)
                }
                .pickerStyle(.segmented)

                PanelCaption(text: store.granularity == .control
                             ? "Tap a button to pick it, then drag it to move it, pinch it or use Size to resize it. It stops where it would touch another button or leave the screen."
                             : "Tap a button to pick its whole group (the d-pad, the face buttons, a stick, a pair of shoulder buttons, or plus, minus and HOME), then drag or pinch it as one.")

                PanelCaption(text: store.selectionTitle.map { "Picked: \($0)" } ?? "Nothing picked yet.", prominent: false)

                PanelSliderRow("Size of the picked button", title: "Size",
                               leadingIcon: "minus.magnifyingglass", trailingIcon: "plus.magnifyingglass",
                               value: Binding(get: { store.selectedScale }, set: { store.setSelectedScale($0) }),
                               range: ZoneEditStore.scaleRange,
                               spokenValue: "\(Int((store.selectedScale * 100).rounded())) percent",
                               readout: "\(Int((store.selectedScale * 100).rounded()))%")
                    .disabled(store.selection == nil)
                    .opacity(store.selection == nil ? 0.5 : 1)

                HStack(spacing: 12) {
                    Button("Reset this") { store.resetSelected() }
                        .buttonStyle(MuffinSecondaryButtonStyle())
                        .disabled(store.selection == nil)
                    Button("Reset all") { confirmingResetAll = true }
                        .buttonStyle(MuffinSecondaryButtonStyle())
                        .disabled(!store.hasEdits)
                }
            } else if store.hasEdits {
                Button("Reset moved and resized buttons") { confirmingResetAll = true }
                    .buttonStyle(MuffinSecondaryButtonStyle())
            }

            if gameID != nil {
                PanelToggle(title: "Own layout for this game",
                            isOn: Binding(get: { store.isPerGame }, set: { store.setPerGame($0) }))
                PanelCaption(text: store.isPerGame
                             ? "Moves and sizes here belong to this game only."
                             : "Moves and sizes here apply to every game.", prominent: false)
            }
        }
        .onAppear { store.activate(gameID: gameID) }
        // Closing the panel (or switching style) ends editing, so the pad is playable again.
        .onDisappear { store.setEditing(false) }
        .confirmationDialog("Reset moved and resized buttons?", isPresented: $confirmingResetAll, titleVisibility: .visible) {
            Button("Reset all", role: .destructive) { store.resetAll() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(store.isPerGame
                 ? "Every button goes back to where Zone puts it, in this game."
                 : "Every button goes back to where Zone puts it, in every game that doesn't have its own layout.")
        }
    }
}
