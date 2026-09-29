//
//  MuffinColourPresets.swift
//  Muffin - colour presets for the pad, plus the Custom picker and both file formats.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

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

    /// Sampled: the d-pad and system-button plastic used as the fill for every group.
    static let wiiUGrey = MuffinColourFile(
        name: "Wii U Grey",
        fills: ["default": Sampled.dpadFill],
        glyphs: ["default": MuffinRGBA("#3A3A3C")],
        outline: MuffinRGBA("#8A8A8E"))

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

    /// See-through white. Low fill alpha (not zero) keeps controls findable by eye; the
    /// pressed-alpha boost carries most of the affordance.
    static let frostedGlass = MuffinColourFile(
        name: "Frosted Glass",
        fills: ["default": MuffinRGBA(r: 1, g: 1, b: 1, a: 0.14)],
        glyphs: ["default": MuffinRGBA(r: 1, g: 1, b: 1, a: 0.55)],
        outline: MuffinRGBA(r: 1, g: 1, b: 1, a: 0.35),
        pressedAlphaBoost: 0.30)

    /// Splatoon ink colours.
    static let inkling = MuffinColourFile(
        name: "Inkling",
        fills: ["A": .init("#0FF0C0"), "B": .init("#FF4E9E"), "X": .init("#FFE137"), "Y": .init("#8B3FFD"),
                "default": MuffinRGBA("#1B1B22")],
        glyphs: ["default": .init("#F4F4F5")],
        outline: MuffinRGBA(r: 1, g: 1, b: 1, a: 0.25))

    /// Pure black glyphs on pure white fills with a heavy outline, for low vision or bright
    /// outdoor screens.
    static let highContrast = MuffinColourFile(
        name: "High Contrast",
        fills: ["default": MuffinRGBA("#FFFFFF")],
        glyphs: ["default": MuffinRGBA("#000000")],
        outline: MuffinRGBA("#000000"),
        pressedAlphaBoost: 0)

    /// Terminal green.
    static let terminal = MuffinColourFile(
        name: "Terminal",
        fills: ["default": MuffinRGBA(r: 0.04, g: 0.10, b: 0.04, a: 0.9)],
        glyphs: ["default": MuffinRGBA("#33FF66")],
        outline: MuffinRGBA(r: 0.2, g: 1, b: 0.4, a: 0.4),
        shell: MuffinRGBA("#050805"))

    static let sunset = MuffinColourFile(
        name: "Sunset",
        fills: ["A": .init("#FF8A5C"), "B": .init("#FF5C8A"), "X": .init("#FFC15C"), "Y": .init("#C15CFF"),
                "default": MuffinRGBA("#3A2A3D")],
        glyphs: ["default": .init("#FFF4EC")],
        outline: MuffinRGBA(r: 1, g: 1, b: 1, a: 0.2))

    /// The starting point `PadColourPickerView` edits.
    static let customStarter = MuffinColourFile(
        name: "Custom", fills: ["default": Sampled.faceFill],
        glyphs: ["default": Sampled.glyphGrey], outline: Sampled.outlineGrey)

    static let all: [MuffinColourFile] = [
        wiiUWhite, wiiUGrey, wiiUBlack, superFamicom, frostedGlass,
        inkling, highContrast, terminal, sunset, customStarter,
    ]
}

// MARK: - The Custom picker

/// One row per control group, with a `ColorPicker` for its fill and its glyph, live on the pad
/// behind the sheet.
struct PadColourPickerView: View {
    @Binding var scheme: MuffinColourFile
    var onSave: (MuffinColourFile) -> Void
    var onExport: () -> Void
    var onImport: () -> Void

    var body: some View {
        Form {
            Section("Name") {
                TextField("Scheme name", text: $scheme.name)
            }
            Section("Every button, unless overridden below") {
                colourRow("Fill", key: "default", isGlyph: false)
                colourRow("Glyph", key: "default", isGlyph: true)
                colourRow("Outline", key: nil, isGlyph: false, isOutline: true)
            }
            ForEach(colourableGroups, id: \.self) { group in
                Section(group.title) {
                    colourRow("Fill", key: group.rawValue, isGlyph: false)
                    if group == .face {
                        ForEach(["A", "B", "X", "Y"], id: \.self) { id in
                            colourRow("\(id) glyph", key: id, isGlyph: true)
                        }
                    }
                }
            }
            Section {
                Stepper(String(format: "Pressed brightens by %.0f%%", scheme.pressedAlphaBoost * 100),
                       value: $scheme.pressedAlphaBoost, in: 0...0.4, step: 0.02)
            }
            Section {
                Button("Save") { onSave(scheme) }
                Button("Export as .muffinclr", action: onExport)
                Button("Import .muffinclr", action: onImport)
            }
        }
    }

    /// Sticks and the menu row are left out of the per-group list (a stick's base/knob split
    /// doesn't fit one swatch); `fill(_:)` still finds them by id.
    private var colourableGroups: [PadGroup] { [.dpad, .face, .start, .select] }

    private func colourRow(_ label: String, key: String?, isGlyph: Bool, isOutline: Bool = false) -> some View {
        let binding = Binding<Color>(
            get: {
                let c = isOutline ? scheme.outline : (isGlyph ? (key.flatMap { scheme.glyphs[$0] } ?? scheme.glyph("default"))
                                                              : (key.flatMap { scheme.fills[$0] } ?? scheme.fill("default")))
                return Color(red: c.r, green: c.g, blue: c.b, opacity: c.a)
            },
            set: { newColor in
                // getRed converts greyscale colours to RGB; cgColor.components would give
                // only (white, alpha) for a grey.
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                guard UIColor(newColor).getRed(&r, green: &g, blue: &b, alpha: &a) else { return }
                let rgba = MuffinRGBA(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
                if isOutline { scheme.outline = rgba }
                else if isGlyph { scheme.glyphs[key ?? "default"] = rgba }
                else { scheme.fills[key ?? "default"] = rgba }
            })
        return ColorPicker(label, selection: binding, supportsOpacity: true)
    }
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
