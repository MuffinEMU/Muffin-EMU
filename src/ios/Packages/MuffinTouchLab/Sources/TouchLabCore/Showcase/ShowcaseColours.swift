// Ported from MuffinEMU's showcase pad (src/ios/App/MuffinPadCustomisation.swift).
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

import CoreGraphics
import Foundation

// MARK: - Colour

/// Straight RGBA, 0...1, Codable as a hex string plus alpha so a `.muffinclr` stays
/// readable and hand-editable rather than turning into a wall of floats.
public struct ShowcaseRGBA: Codable, Equatable {
    public var r: Double, g: Double, b: Double, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    public init(_ hex: String, _ alpha: Double = 1) {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt32(s, radix: 16) ?? 0
        self.init(r: Double((v >> 16) & 0xFF) / 255,
                  g: Double((v >> 8) & 0xFF) / 255,
                  b: Double(v & 0xFF) / 255, a: alpha)
    }

    public var hex: String { String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255)) }

    enum CodingKeys: String, CodingKey { case hex, alpha }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        self.init(try c.decode(String.self, forKey: .hex),
                  try c.decodeIfPresent(Double.self, forKey: .alpha) ?? 1)
    }
    public func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: CodingKeys.self)
        try c.encode(hex, forKey: .hex)
        if a != 1 { try c.encode(a, forKey: .alpha) }
    }
}


/// `.muffinclr` - a colour scheme.
///
/// Keyed by control id, not by group, because A/B/X/Y want four different colours and
/// everything else usually wants one. `fills["default"]` catches anything unlisted, so a
/// three-line file is a valid scheme.
public struct ShowcaseColourFile: Codable, Equatable {
    public static let fileExtension = "muffinclr"
    public static let currentVersion = 1

    public var version: Int = currentVersion
    public var name: String
    public var fills: [String: ShowcaseRGBA]
    public var glyphs: [String: ShowcaseRGBA]
    public var outline: ShowcaseRGBA
    /// How much more opaque a control goes while held. The shipping pad does this by
    /// jumping fill alpha from 0.88 to 1.0; expressing it as a boost keeps that behaviour
    /// for a translucent scheme, where jumping straight to 1.0 would look like a flash.
    public var pressedAlphaBoost: Double = 0.12
    /// Painted behind the pad in framed and shell modes, where there is a bezel to paint.
    public var shell: ShowcaseRGBA?

    public func fill(_ controlID: String) -> ShowcaseRGBA {
        fills[controlID] ?? fills[ShowcaseGroup.group(containing: controlID)?.rawValue ?? ""]
            ?? fills["default"] ?? ShowcaseRGBA("#CDCDCD")
    }
    public func glyph(_ controlID: String) -> ShowcaseRGBA {
        glyphs[controlID] ?? glyphs[ShowcaseGroup.group(containing: controlID)?.rawValue ?? ""]
            ?? glyphs["default"] ?? ShowcaseRGBA("#333333")
    }
    /// The alpha a control is actually painted at, given whether it is held.
    public func alpha(_ controlID: String, pressed: Bool) -> Double {
        min(1, fill(controlID).a + (pressed ? pressedAlphaBoost : 0))
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }
    public static func decode(_ data: Data) throws -> ShowcaseColourFile {
        let f = try JSONDecoder().decode(ShowcaseColourFile.self, from: data)
        guard f.version <= currentVersion else { throw CocoaError(.fileReadCorruptFile) }
        return f
    }
}


// MARK: - Real colour, sampled off the hardware

/// Hex values sampled from the official Wii U GamePad illustration at the positions the
/// geometry was measured from. `wiiUBlack` is derived from the same relationships, not
/// sampled.
private enum Sampled {
    static let shellWhite   = ShowcaseRGBA("#F4F4F5")   // body plastic
    static let faceFill     = ShowcaseRGBA("#F1F1F1")   // A/B/X/Y plastic - visibly whiter than...
    static let dpadFill     = ShowcaseRGBA("#BDBDC1")   // ...the d-pad and system-button plastic
    static let systemFill   = ShowcaseRGBA("#CDCDCD")   // shoulders, +/-
    static let stickFill    = ShowcaseRGBA("#EAEAEA")
    static let glyphGrey    = ShowcaseRGBA("#6A6A6A")   // the letters on A/B/X/Y
    static let outlineGrey  = ShowcaseRGBA("#ACADAE")
    static let homeGlyph    = ShowcaseRGBA("#757D80")
}

/// The colour presets of the showcase pad (MuffinColourPresets.swift), same values.
public enum ShowcaseColourPresets {
    /// Sampled: white-ish face buttons and a visibly greyer d-pad and system row.
    public static let wiiUWhite = ShowcaseColourFile(
        name: "Wii U White",
        fills: ["face": Sampled.faceFill, "dpad": Sampled.dpadFill, "start": Sampled.systemFill,
                "select": Sampled.systemFill, "shoulderL": Sampled.systemFill, "shoulderR": Sampled.systemFill,
                "stickL": Sampled.stickFill, "stickR": Sampled.stickFill, "home": .init("#FFFFFF"),
                "default": Sampled.faceFill],
        glyphs: ["default": Sampled.glyphGrey, "home": Sampled.homeGlyph],
        outline: Sampled.outlineGrey)

    /// Derived: the white preset's relationships inverted onto a dark housing.
    public static let wiiUBlack = ShowcaseColourFile(
        name: "Wii U Black",
        fills: ["default": ShowcaseRGBA("#3A3A3D")],
        glyphs: ["default": ShowcaseRGBA("#D8D8DA")],
        outline: ShowcaseRGBA("#1C1C1E"),
        shell: ShowcaseRGBA("#151516"))

    /// Approximate: the widely-cited Super Famicom face-button colours.
    public static let superFamicom = ShowcaseColourFile(
        name: "Super Famicom",
        fills: ["A": .init("#5FB84E"), "B": .init("#E8C33B"), "X": .init("#4E7FD0"), "Y": .init("#D14B45"),
                "default": Sampled.dpadFill],
        glyphs: ["A": .init("#FFFFFF"), "B": .init("#FFFFFF"), "X": .init("#FFFFFF"), "Y": .init("#FFFFFF"),
                 "default": Sampled.glyphGrey],
        outline: Sampled.outlineGrey)
}

/// Exactly the three the showcase pad offers.
public enum ShowcaseColourPreset: String, CaseIterable, Identifiable {
    case wiiUWhite, wiiUBlack, superFamicom

    public var id: String { rawValue }

    public var file: ShowcaseColourFile {
        switch self {
        case .wiiUWhite:    return ShowcaseColourPresets.wiiUWhite
        case .wiiUBlack:    return ShowcaseColourPresets.wiiUBlack
        case .superFamicom: return ShowcaseColourPresets.superFamicom
        }
    }
}
