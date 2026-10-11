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

    // MARK: Hardware variants and tasteful extras
    //
    // Same file format as the first three (`.muffinclr`), no new keys. "Approximate" marks colours
    // matched by eye to photographs, not sampled.

    /// Approximate: the black GamePad of the Wii U Premium set with the gold accents of the
    /// Zelda limited edition: black plastic, warm gold lettering and outline.
    public static let zeldaGold = ShowcaseColourFile(
        name: "Black and Gold",
        fills: ["default": ShowcaseRGBA("#2E2D2B"), "home": ShowcaseRGBA("#3A3835")],
        glyphs: ["default": ShowcaseRGBA("#D9B45B")],
        outline: ShowcaseRGBA("#8C7231"),
        shell: ShowcaseRGBA("#121110"))

    /// Approximate: the Famicom - a red face, cream d-pad and system row, dark outlines.
    public static let famicom = ShowcaseColourFile(
        name: "Famicom",
        fills: ["face": ShowcaseRGBA("#B3262D"), "dpad": ShowcaseRGBA("#2B2A2A"), "stickL": ShowcaseRGBA("#E9DFC7"),
                "stickR": ShowcaseRGBA("#E9DFC7"), "default": ShowcaseRGBA("#E9DFC7")],
        glyphs: ["face": ShowcaseRGBA("#F4E9D2"), "dpad": ShowcaseRGBA("#E9DFC7"), "default": ShowcaseRGBA("#6B2A22")],
        outline: ShowcaseRGBA("#7B6F5B"),
        shell: ShowcaseRGBA("#D9CFB8"))

    /// Approximate: the North American SNES - lavender buttons with the purple d-pad and the
    /// four coloured face buttons (Y green, X blue, B yellow, A red).
    public static let snesAmerica = ShowcaseColourFile(
        name: "Super Nintendo",
        fills: ["A": .init("#C0392F"), "B": .init("#E3B93A"), "X": .init("#3D63B8"), "Y": .init("#3E9A57"),
                "dpad": .init("#6C6C74"), "default": .init("#B7B1C9")],
        glyphs: ["A": .init("#FFFFFF"), "B": .init("#3A2E10"), "X": .init("#FFFFFF"), "Y": .init("#FFFFFF"),
                 "dpad": .init("#F0EEF6"), "default": .init("#4E4A63")],
        outline: ShowcaseRGBA("#8D88A3"))

    /// Extra: deep navy with soft blue lettering. Pairs well with the glass look.
    public static let midnight = ShowcaseColourFile(
        name: "Midnight",
        fills: ["default": ShowcaseRGBA("#1F2A44"), "home": ShowcaseRGBA("#2B3A5E")],
        glyphs: ["default": ShowcaseRGBA("#B7C6EA")],
        outline: ShowcaseRGBA("#0E1424"),
        shell: ShowcaseRGBA("#0B101D"))

    /// Extra: a cool mint on pale grey-green.
    public static let mint = ShowcaseColourFile(
        name: "Mint",
        fills: ["default": ShowcaseRGBA("#CFEBDD"), "face": ShowcaseRGBA("#E7F6EE"), "dpad": ShowcaseRGBA("#A9D4C0")],
        glyphs: ["default": ShowcaseRGBA("#2F6B55")],
        outline: ShowcaseRGBA("#7FB39B"))

    /// Extra: a translucent smoky grey that lets the picture show through; meant for low opacity.
    public static let smoke = ShowcaseColourFile(
        name: "Smoke",
        fills: ["default": ShowcaseRGBA("#4A4D55", 0.78), "home": ShowcaseRGBA("#5A5E68", 0.85)],
        glyphs: ["default": ShowcaseRGBA("#F2F3F5")],
        outline: ShowcaseRGBA("#FFFFFF", 0.55),
        pressedAlphaBoost: 0.14)

    /// Extra: warm rose gold.
    public static let roseGold = ShowcaseColourFile(
        name: "Rose Gold",
        fills: ["default": ShowcaseRGBA("#E9C4B8"), "face": ShowcaseRGBA("#F4DAD0"), "dpad": ShowcaseRGBA("#D3A99B")],
        glyphs: ["default": ShowcaseRGBA("#7A4A3F")],
        outline: ShowcaseRGBA("#B98676"))
}

/// Every preset the showcase pad offers: the Wii U's own colours first, then variants and extras.
public enum ShowcaseColourPreset: String, CaseIterable, Identifiable, Sendable {
    case wiiUWhite, wiiUBlack, superFamicom
    case zeldaGold, famicom, snesAmerica
    case midnight, mint, smoke, roseGold

    public var id: String { rawValue }

    public var file: ShowcaseColourFile {
        switch self {
        case .wiiUWhite:    return ShowcaseColourPresets.wiiUWhite
        case .wiiUBlack:    return ShowcaseColourPresets.wiiUBlack
        case .superFamicom: return ShowcaseColourPresets.superFamicom
        case .zeldaGold:    return ShowcaseColourPresets.zeldaGold
        case .famicom:      return ShowcaseColourPresets.famicom
        case .snesAmerica:  return ShowcaseColourPresets.snesAmerica
        case .midnight:     return ShowcaseColourPresets.midnight
        case .mint:         return ShowcaseColourPresets.mint
        case .smoke:        return ShowcaseColourPresets.smoke
        case .roseGold:     return ShowcaseColourPresets.roseGold
        }
    }
}
