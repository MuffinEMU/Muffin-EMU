// MuffinEMU TouchLab — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: GPL-3.0-only
// This notice must be kept in any copy or modified version (GPL-3.0 §4 and §5).

import CoreGraphics
import Foundation

/// How far a player has moved and resized one control, or one group of controls, from where
/// the layout puts it. The same shape for every scheme that offers editing, so a scheme only
/// has to say what its targets are.
public struct PadEdit: Equatable, Sendable {
    /// Moved from the layout's own place, in button widths (right and down are positive), so
    /// the same edit means the same thing on every screen and at every size.
    public var dx: CGFloat
    public var dy: CGFloat
    /// Multiplier on the layout's own size; 1 = unchanged.
    public var scale: CGFloat

    public static let identity = PadEdit()
    public static let scaleRange: ClosedRange<CGFloat> = 0.7...1.6
    /// The furthest an offset may be stored. Far beyond any screen; it only keeps garbage out.
    public static let maxOffset: CGFloat = 40

    public init(dx: CGFloat = 0, dy: CGFloat = 0, scale: CGFloat = 1) {
        self.dx = dx
        self.dy = dy
        self.scale = scale
    }

    public var isIdentity: Bool { abs(dx) < 0.0005 && abs(dy) < 0.0005 && abs(scale - 1) < 0.0005 }

    /// In range and finite; anything unusable falls back to "unchanged" for that part.
    public var clamped: PadEdit {
        func offset(_ v: CGFloat) -> CGFloat { v.isFinite ? min(max(v, -Self.maxOffset), Self.maxOffset) : 0 }
        let s = scale.isFinite ? min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound) : 1
        return PadEdit(dx: offset(dx), dy: offset(dy), scale: s)
    }

    /// This edit a fraction `t` of the way from "unchanged" (0) to itself (1).
    func eased(_ t: CGFloat) -> PadEdit {
        PadEdit(dx: dx * t, dy: dy * t, scale: 1 + (scale - 1) * t)
    }

    func lerp(to other: PadEdit, _ t: CGFloat) -> PadEdit {
        PadEdit(dx: dx + (other.dx - dx) * t, dy: dy + (other.dy - dy) * t, scale: scale + (other.scale - scale) * t)
    }
}

/// Every edit a player has made, keyed by target. Keys are the scheme's own strings
/// (`GamePadEditing` has Zone's); this type neither knows nor cares what they mean.
public struct PadEdits: Equatable, Sendable {
    public var entries: [String: PadEdit]

    public init(_ entries: [String: PadEdit] = [:]) {
        self.entries = entries.filter { !$0.value.isIdentity }
    }

    public var isEmpty: Bool { entries.isEmpty }

    public subscript(key: String) -> PadEdit {
        get { entries[key] ?? .identity }
        set {
            let v = newValue.clamped
            if v.isIdentity { entries[key] = nil } else { entries[key] = v }
        }
    }

    func eased(_ t: CGFloat) -> PadEdits {
        var out = PadEdits()
        for (k, v) in entries { out[k] = v.eased(t) }
        return out
    }

    /// The stored form: JSON like {"c.a":[0.5,-0.25,1.1]}, empty when there are no edits.
    public var encoded: String {
        guard !entries.isEmpty else { return "" }
        let plain = entries.mapValues { e in [e.dx, e.dy, e.scale].map { (Double($0) * 10000).rounded() / 10000 } }
        guard let data = try? JSONSerialization.data(withJSONObject: plain, options: [.sortedKeys]) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    public init(encoded: String) {
        guard !encoded.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: [Double]] else {
            self.init()
            return
        }
        var out = PadEdits()
        for (k, v) in obj where v.count == 3 && v.allSatisfy({ $0.isFinite }) {
            out[k] = PadEdit(dx: CGFloat(v[0]), dy: CGFloat(v[1]), scale: CGFloat(v[2]))
        }
        self = out
    }
}

/// Which kind of thing a tap selects while editing: one control, or its whole cluster.
public enum PadEditGranularity: String, Sendable, CaseIterable {
    case control, group
}

/// One thing that can be edited: a control, or a group of controls that move and resize together.
public struct PadEditTarget: Equatable, Sendable {
    public var key: String
    public var title: String
    public var isGroup: Bool
    /// Indices into the scheme's control list.
    public var members: [Int]
    /// A group's scale spreads its members' positions as well as growing them (a d-pad's arms, a
    /// shoulder pair). Off, each member grows in place and only the move is shared.
    public var spreads: Bool
    /// The member a spreading group scales around; nil = the middle of the members.
    public var anchor: Int?

    public init(key: String, title: String, isGroup: Bool, members: [Int], spreads: Bool = true, anchor: Int? = nil) {
        self.key = key
        self.title = title
        self.isGroup = isGroup
        self.members = members
        self.spreads = spreads
        self.anchor = anchor
    }
}

/// Where a target is on screen right now, for drawing handles and picking.
public struct PadEditOutline: Equatable, Sendable {
    public var key: String
    public var title: String
    public var rect: CGRect
    public var selected: Bool
}

/// Applies edits to a finished arrangement, and keeps the result inside the rules every
/// layout already obeys: inside the safe area, no two controls overlapping, and nothing moved
/// onto a screen it was not already over. An edit that would break them is cut back to the
/// furthest one that does not, so the layout is valid however it was edited.
public enum PadEditor {
    /// Everything an edit has to respect.
    public struct Space {
        var bounds: CGRect
        /// Per control: rects it began clear of and so must not be moved onto.
        var blocked: [[CGRect]]
        /// What the unedited arrangement already got wrong (a layout squeezed past what fits), which
        /// an edit is not blamed for.
        var baseline: Set<String>

        /// `home` is the arrangement before any edit; `screens` the GamePad touchscreen and the video,
        /// which a control that was clear of one at home is never moved onto.
        public init(home: [PadControl], bounds: CGRect, screens: [CGRect]) {
            self.bounds = bounds
            blocked = home.map { c in
                let box = c.shape.boundingBox
                return screens.filter { !$0.intersects(box) }
            }
            baseline = Set(LayoutCheck.problems(home.map(PadEditor.drawn), in: bounds))
        }

        func isValid(_ set: [PadControl]) -> Bool {
            for (i, c) in set.enumerated() where i < blocked.count && !blocked[i].isEmpty {
                let box = c.shape.boundingBox
                if blocked[i].contains(where: { $0.intersects(box) }) { return false }
            }
            return LayoutCheck.problems(set.map(PadEditor.drawn), in: bounds).allSatisfy { baseline.contains($0) }
        }
    }

    /// The control as it is drawn, for the collision test. The d-pad's shape is its catchment, a circle
    /// past its arms; a d-pad that has to keep that margin clear of its neighbours could barely be made
    /// bigger, and the margin is only extra reach, which the nearest-edge rule already shares out.
    public static func drawn(_ c: PadControl) -> PadControl {
        guard case let .dpad(_, _, arm, size) = c.kind else { return c }
        var out = c
        out.shape = .circle(center: c.shape.center, radius: max(arm.x, arm.y) + size / 2)
        return out
    }

    /// The arrangement with every edit applied exactly as asked.
    static func raw(_ home: [PadControl], _ targets: [PadEditTarget], _ edits: PadEdits, unit u: CGFloat) -> [PadControl] {
        var set = home
        for t in targets {
            let e = edits[t.key]
            if e.isIdentity { continue }
            var pivot: CGPoint?
            if t.isGroup, t.spreads {
                if let a = t.anchor, set.indices.contains(a) {
                    pivot = set[a].shape.center
                } else {
                    let box = t.members.filter { set.indices.contains($0) }
                        .reduce(CGRect.null) { $0.union(set[$1].shape.boundingBox) }
                    pivot = box.isNull ? nil : box.center
                }
            }
            for i in t.members where set.indices.contains(i) {
                set[i] = transform(set[i], about: pivot, by: e, unit: u)
            }
        }
        return set
    }

    static func transform(_ c: PadControl, about pivot: CGPoint?, by e: PadEdit, unit u: CGFloat) -> PadControl {
        let k = e.scale
        let d = CGPoint(x: e.dx * u, y: e.dy * u)
        let from = c.shape.center
        // Where its centre goes: around the group's pivot when the group spreads, else just moved.
        let to: CGPoint
        if let p = pivot { to = p + (from - p) * k + d } else { to = from + d }
        var out = c
        switch c.shape {
        case .circle(_, let r):
            out.shape = .circle(center: to, radius: r * k)
        case .roundedRect(let rect, let cr):
            out.shape = .roundedRect(CGRect(center: to, size: CGSize(width: rect.width * k, height: rect.height * k)),
                                     cornerRadius: cr * k)
        }
        out.reach = c.reach * k
        if let knob = c.knob { out.knob = knob * k }
        switch c.kind {
        case let .dpad(click, clickRadius, armOffset, armSize):
            out.kind = .dpad(click: click, clickRadius: clickRadius * k, armOffset: armOffset * k, armSize: armSize * k)
        case let .stick(s, travel, click):
            out.kind = .stick(s, travel: travel * k, click: click)
        default:
            break
        }
        return out
    }

    /// The arrangement with the edits applied. Valid as asked, they are applied as they are. If a
    /// stored set no longer fits (another screen, another size, a different shoulder drop), all of
    /// them are eased back together by the largest fraction that does, so the layout keeps its
    /// shape instead of one control snapping somewhere else.
    public static func apply(_ edits: PadEdits, to home: [PadControl], targets: [PadEditTarget],
                             unit u: CGFloat, in space: Space) -> [PadControl] {
        guard !edits.isEmpty else { return home }
        let full = raw(home, targets, edits, unit: u)
        if space.isValid(full) { return full }
        var good: CGFloat = 0, bad: CGFloat = 1
        for step in stride(from: 15, through: 1, by: -1) {
            let t = CGFloat(step) / 16
            if space.isValid(raw(home, targets, edits.eased(t), unit: u)) { good = t; break }
            bad = t
        }
        for _ in 0..<10 {
            let mid = (good + bad) / 2
            if space.isValid(raw(home, targets, edits.eased(mid), unit: u)) { good = mid } else { bad = mid }
        }
        return good > 0 ? raw(home, targets, edits.eased(good), unit: u) : home
    }

    /// What `requested` becomes for `key` once the rest of `edits` is held fixed: the requested edit
    /// itself if the layout can take it, else the nearest one it can, found by walking size, then
    /// sideways, then up and down from `start` (an edit known to fit - the one it was before the
    /// drag) toward the request and stopping where something is in the way. Sideways and vertical
    /// are tried in both orders and the closer result kept, so a control pushed into a wall slides
    /// along it. Stored as returned, an edit can never be one the layout has to cut back later.
    public static func resolve(_ requested: PadEdit, for key: String, start: PadEdit, among edits: PadEdits,
                               home: [PadControl], targets: [PadEditTarget], unit u: CGFloat, in space: Space) -> PadEdit {
        let want = requested.clamped
        func fits(_ e: PadEdit) -> Bool {
            var all = edits
            all[key] = e
            return space.isValid(raw(home, targets, all, unit: u))
        }
        if fits(want) { return want }
        var origin = start.clamped
        if !fits(origin) { origin = .identity }

        /// The farthest point from `a` toward `b` (a fits) that fits: scan in sixteenths, then bisect.
        func walk(_ a: PadEdit, to b: PadEdit) -> PadEdit {
            if a == b || fits(b) { return b }
            var good: CGFloat = 0, bad: CGFloat = 1
            for step in 1..<16 {
                let t = CGFloat(step) / 16
                if fits(a.lerp(to: b, t)) { good = t } else { bad = t; break }
            }
            for _ in 0..<10 {
                let mid = (good + bad) / 2
                if fits(a.lerp(to: b, mid)) { good = mid } else { bad = mid }
            }
            return a.lerp(to: b, good)
        }

        var base = origin
        base = walk(base, to: PadEdit(dx: base.dx, dy: base.dy, scale: want.scale))
        func axes(_ first: WritableKeyPath<PadEdit, CGFloat>, _ second: WritableKeyPath<PadEdit, CGFloat>) -> PadEdit {
            var e = base
            for _ in 0..<2 {
                var next = e; next[keyPath: first] = want[keyPath: first]
                e = walk(e, to: next)
                next = e; next[keyPath: second] = want[keyPath: second]
                e = walk(e, to: next)
            }
            return e
        }
        let a = axes(\.dx, \.dy), b = axes(\.dy, \.dx)
        func miss(_ e: PadEdit) -> CGFloat { hypot(e.dx - want.dx, e.dy - want.dy) + abs(e.scale - want.scale) }
        return miss(a) <= miss(b) ? a : b
    }
}
