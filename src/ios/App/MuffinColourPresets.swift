// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team.
// SPDX-License-Identifier: MPL-2.0
// This notice must be kept in any copy or derivative (MPL-2.0 §3.4).

//
//  MuffinColourPresets.swift
//  Muffin - colour presets for the pad, plus both file formats.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Real colour, sampled off the hardware

/// Hex values sampled from the official Wii U GamePad illustration at the positions the
/// geometry was measured from. `wiiUBlack` is derived from the same relationships, not
/// sampled.
private enum Sampled {
    static let shellWhite   = MuffinRGBA("#F4F4F5")   // body plastic
    static let faceFill     = MuffinRGBA("#F1F1F1")   // A/B/X/Y plastic - visibly whiter than...
    static let dpadFill     = MuffinRGBA("#BDBDC1")   // ...the d-pad and system-button plastic
    static let systemFill   = MuffinRGBA("#CDCDCD")   // shoulders, +/-
    static let stickFill    = MuffinRGBA("#EAEAEA")
    static let glyphGrey    = MuffinRGBA("#6A6A6A")   // the letters on A/B/X/Y
    static let outlineGrey  = MuffinRGBA("#ACADAE")
    static let homeGlyph    = MuffinRGBA("#757D80")
}

// MARK: - The catalog

enum MuffinColourPresets {

    /// Sampled: white-ish face buttons and a visibly greyer d-pad and system row.
    static let wiiUWhite = MuffinColourFile(
        name: "Wii U White",
        fills: ["face": Sampled.faceFill, "dpad": Sampled.dpadFill, "start": Sampled.systemFill,
                "select": Sampled.systemFill, "shoulderL": Sampled.systemFill, "shoulderR": Sampled.systemFill,
                "stickL": Sampled.stickFill, "stickR": Sampled.stickFill, "home": .init("#FFFFFF"),
                "default": Sampled.faceFill],
        glyphs: ["default": Sampled.glyphGrey, "home": Sampled.homeGlyph],
        outline: Sampled.outlineGrey)

    /// Derived: the white preset's relationships (buttons a shade lighter than the housing,
    /// dark glyphs on light buttons) inverted onto a dark housing.
    static let wiiUBlack = MuffinColourFile(
        name: "Wii U Black",
        fills: ["default": MuffinRGBA("#3A3A3D")],
        glyphs: ["default": MuffinRGBA("#D8D8DA")],
        outline: MuffinRGBA("#1C1C1E"),
        shell: MuffinRGBA("#151516"))

    /// Approximate: the widely-cited Super Famicom face-button colours.
    static let superFamicom = MuffinColourFile(
        name: "Super Famicom",
        fills: ["A": .init("#5FB84E"), "B": .init("#E8C33B"), "X": .init("#4E7FD0"), "Y": .init("#D14B45"),
                "default": Sampled.dpadFill],
        glyphs: ["A": .init("#FFFFFF"), "B": .init("#FFFFFF"), "X": .init("#FFFFFF"), "Y": .init("#FFFFFF"),
                 "default": Sampled.glyphGrey],
        outline: Sampled.outlineGrey)
}

// MARK: - The two file formats, as real documents

extension UTType {
    /// Both are plain JSON under the hood - `MuffinLayoutFile`/`MuffinColourFile` already
    /// encode as such - so the type just needs its own extension and identifier to be
    /// distinguishable in the Files app and in a share sheet, not a new serialisation.
    static let muffinLayout = UTType(exportedAs: "com.kiddreads.muffin.layout", conformingTo: .json)
    static let muffinColour = UTType(exportedAs: "com.kiddreads.muffin.colour", conformingTo: .json)
}

struct MuffinLayoutDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.muffinLayout] }
    var file: MuffinLayoutFile

    init(_ file: MuffinLayoutFile) { self.file = file }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        file = try MuffinLayoutFile.decode(data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try file.encoded())
    }
}

struct MuffinColourDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.muffinColour] }
    var file: MuffinColourFile

    init(_ file: MuffinColourFile) { self.file = file }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        file = try MuffinColourFile.decode(data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try file.encoded())
    }
}
