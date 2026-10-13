// MuffinEMU TouchLab — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: GPL-3.0-only
// This notice must be kept in any copy or modified version (GPL-3.0 §4 and §5).

import CoreGraphics

/// What can be edited on the GamePad arrangement (Zone's), and how a touch finds it.
///
/// A target is one control (`c.<id>`) or a group that moves and resizes as one (`g.<id>`).
/// The d-pad and each stick are their own whole cluster, so they have no separate group: picking
/// "the group" there picks the control. Groups are applied first, then controls, so a control
/// edited inside a moved group keeps its place in it.
public enum GamePadEditing {
    public enum Key {
        public static let face = "g.face"
        public static let leftShoulders = "g.shoulders.left"
        public static let rightShoulders = "g.shoulders.right"
        public static let system = "g.system"
        public static let dpad = "c.dpad"
        public static let leftStick = "c.stick.left"
        public static let rightStick = "c.stick.right"
        public static func button(_ b: PadButton) -> String? {
            switch b {
            case .a: return "c.a"
            case .b: return "c.b"
            case .x: return "c.x"
            case .y: return "c.y"
            case .l: return "c.l"
            case .r: return "c.r"
            case .zl: return "c.zl"
            case .zr: return "c.zr"
            case .plus: return "c.plus"
            case .minus: return "c.minus"
            case .home: return "c.home"
            default: return nil
            }
        }
    }

    /// The control key and the group key a control belongs to (either may be nil).
    static func keys(of c: PadControl) -> (control: String?, group: String?) {
        switch c.kind {
        case .dpad: return (Key.dpad, nil)
        case .stick(let s, _, _): return (s == .left ? Key.leftStick : Key.rightStick, nil)
        case .button(let b):
            if c.role == .dot { return (nil, Key.face) }
            let own = Key.button(b)
            switch b {
            case .a, .b, .x, .y: return (own, Key.face)
            case .zl, .l: return (own, Key.leftShoulders)
            case .zr, .r: return (own, Key.rightShoulders)
            case .plus, .minus, .home: return (own, Key.system)
            default: return (own, nil)
            }
        default: return (nil, nil)
        }
    }

    static let titles: [String: String] = [
        Key.face: "Face buttons", Key.leftShoulders: "Left shoulders", Key.rightShoulders: "Right shoulders",
        Key.system: "Minus, plus and HOME", Key.dpad: "D-pad", Key.leftStick: "Left stick", Key.rightStick: "Right stick",
        "c.a": "A", "c.b": "B", "c.x": "X", "c.y": "Y", "c.zl": "ZL", "c.l": "L", "c.r": "R", "c.zr": "ZR",
        "c.minus": "Minus", "c.plus": "Plus", "c.home": "HOME",
    ]

    /// Groups first, then controls, each in a fixed order. `spreads` is off for the system buttons
    /// (they sit far apart; growing them should not push them further), on for the rest.
    static let order: [String] = [Key.face, Key.leftShoulders, Key.rightShoulders, Key.system,
                                  Key.dpad, Key.leftStick, Key.rightStick,
                                  "c.a", "c.b", "c.x", "c.y", "c.zl", "c.l", "c.r", "c.zr", "c.minus", "c.plus", "c.home"]

    public static func targets(for controls: [PadControl]) -> [PadEditTarget] {
        var members: [String: [Int]] = [:]
        for (i, c) in controls.enumerated() {
            let k = keys(of: c)
            if let g = k.group { members[g, default: []].append(i) }
            if let own = k.control { members[own, default: []].append(i) }
        }
        return order.compactMap { key in
            guard let m = members[key], !m.isEmpty else { return nil }
            let isGroup = key.hasPrefix("g.")
            let anchor = key == Key.face ? m.first { controls[$0].role == .dot } : nil
            return PadEditTarget(key: key, title: titles[key] ?? key, isGroup: isGroup, members: m,
                                 spreads: key != Key.system, anchor: anchor)
        }
    }

    /// The targets a tap can select: every control, or every whole cluster.
    public static func selectable(_ granularity: PadEditGranularity, in targets: [PadEditTarget]) -> [PadEditTarget] {
        switch granularity {
        case .control:
            return targets.filter { !$0.isGroup }
        case .group:
            let order = [Key.dpad, Key.face, Key.leftStick, Key.rightStick, Key.leftShoulders, Key.rightShoulders, Key.system]
            return order.compactMap { k in targets.first { $0.key == k } }
        }
    }

    /// What is drawn of a control, which is not always what it catches touches with: the d-pad's
    /// catchment is a circle past its arms.
    static func drawnBox(of c: PadControl) -> CGRect {
        if case let .dpad(_, _, arm, size) = c.kind {
            let o = c.shape.center
            let w = arm.x + size / 2, h = arm.y + size / 2
            return CGRect(x: o.x - w, y: o.y - h, width: 2 * w, height: 2 * h)
        }
        return c.shape.boundingBox
    }
}
