// MuffinEMU TouchLab — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: GPL-3.0-only
// This notice must be kept in any copy or modified version (GPL-3.0 §4 and §5).

import CoreGraphics

/// Scheme 1 - Zone Pad.
///
/// The conservative replacement: the real GamePad's arrangement (sticks above the
/// d-pad and face buttons, shoulders along the top edge), with the input rebuilt so a
/// thumb that is roughly right counts:
///
/// - Every control has catchment past its drawn edge and the nearest one wins, so there
///   are no dead gaps between buttons and nothing depends on SwiftUI hit testing.
/// - The d-pad is one eight-way control read from the thumb's angle, with wider
///   sectors for the four cardinals - diagonals are deliberate, not accidental.
/// - Rolling a thumb across A/B/X/Y (or L/ZL) moves the press without lifting, and a thumb
///   resting in the gap between two face buttons presses both.
/// - Pressing the d-pad's centre dot is L3, the face diamond's is R3, as on the shipping pad.
///
/// Zone can be edited: every control, and each cluster as a whole, can be moved and resized
/// (`LayoutContext.edits`, `PadEdit`). With no edits the layout is the one described above, to
/// the point. See `PadEditor` for how an edit that would collide is cut back.
public final class ZonePad: ControlScheme {
    public static let schemeInfo = SchemeInfo(
        id: "zone",
        name: "Zone",
        summary: "The GamePad's own layout with forgiving, gap-free touch zones, slide between buttons and two-button presses.")

    /// A's size as a multiple of its usual one (1...1.8), with a wider catchment; the other
    /// face buttons shrink a little to make room and the diamond moves in to stay on screen.
    public let aScale: CGFloat

    public init(aScale: CGFloat = 1) {
        self.aScale = aScale
        super.init(info: Self.schemeInfo)
    }

    // MARK: Editing

    /// True while the player is moving and resizing controls: the host takes the touches itself
    /// (a drag moves a control instead of pressing it) and draws the outlines.
    public var isEditing = false
    /// What a tap selects: one control or its whole cluster.
    public var editGranularity: PadEditGranularity = .control
    /// The selected target's key, if any.
    public var editSelection: String?

    /// The arrangement before any edit, kept while only the edits change (a drag), so moving a
    /// control does not re-fit the whole pad every frame.
    private var home: (context: LayoutContext, controls: [PadControl], unit: CGFloat)?
    private var targets: [PadEditTarget] = []
    private var space: PadEditor.Space?
    private var homeControls: [PadControl] = []
    private var homeUnit: CGFloat = 1

    override public func makeControls(_ context: LayoutContext) -> [PadControl] {
        var key = context
        key.edits = PadEdits()
        if home?.context != key {
            let built = GamePadArrangement.buildWithUnit(context, aScale: aScale)
            home = (key, built.controls, built.unit)
        }
        let h = home!
        homeControls = h.controls
        homeUnit = h.unit
        targets = GamePadEditing.targets(for: h.controls)
        let screens = ([context.touchscreenRect].compactMap { $0 }) + context.videoRects
        let space = PadEditor.Space(home: h.controls, bounds: context.safeBounds, screens: screens)
        self.space = space
        return PadEditor.apply(context.edits, to: h.controls, targets: targets, unit: h.unit, in: space)
    }

    /// One button width as the layout settled on it: what `PadEdit` offsets are measured in.
    public var editUnit: CGFloat { homeUnit }

    /// The edit stored for a target.
    public func currentEdit(for key: String) -> PadEdit { context.edits[key] }

    /// What the player's request for `key` becomes: the request if it fits, otherwise the nearest
    /// edit that does (see `PadEditor.resolve`). `start` is the edit before the drag began.
    public func resolveEdit(_ requested: PadEdit, for key: String, start: PadEdit) -> PadEdit {
        guard let space else { return requested.clamped }
        return PadEditor.resolve(requested, for: key, start: start, among: context.edits,
                                 home: homeControls, targets: targets, unit: homeUnit, in: space)
    }

    /// What a touch at `point` would select, at the current granularity.
    public func editTarget(at point: CGPoint) -> String? {
        guard let i = resolve(point) else { return nil }
        let k = GamePadEditing.keys(of: controls[i])
        switch editGranularity {
        case .control: return k.control ?? k.group
        case .group: return k.group ?? k.control
        }
    }

    /// The targets that can be selected now, with where each is on screen.
    public func editOutlines() -> [PadEditOutline] {
        GamePadEditing.selectable(editGranularity, in: targets).map { t in
            let box = t.members.filter { controls.indices.contains($0) }
                .reduce(CGRect.null) { $0.union(GamePadEditing.drawnBox(of: controls[$1])) }
            return PadEditOutline(key: t.key, title: t.title, rect: box, selected: t.key == editSelection)
        }
    }

    /// The title of a target, for the host's panel.
    public func editTitle(for key: String) -> String { GamePadEditing.titles[key] ?? key }
}
