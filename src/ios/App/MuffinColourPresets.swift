//
//  MuffinColourPresets.swift
//  Muffin - colour presets for the pad, plus the Custom picker and both file formats.
//
//  Wired into the preview showcase build (branch preview/showcase-sneak-peek). See the cull table in GAMEPAD_LAYOUT.md for exactly which of the
//  shipping 20 skins this replaces, and why - it is not a style opinion, it is a
//  measurement: several of them differ by less than 30/441 in their own A/B/X/Y colours,
//  which is not visible to a player at arm's length from an iPad.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Real colour, sampled off the hardware

/// Hex values pulled directly from the official Wii U GamePad illustration
/// (bward-dev1/Wiiuios) at the same pixel positions the geometry was measured from -
/// small patches averaged, not eyeballed. Where a value is a considered match rather than
/// a sample, it says so at its use site: there is no black-GamePad photograph in this
/// repository to sample from, so `wiiUBlack` is a companion built to the same relationships
/// the white one measures, not a second measurement.
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

    /// **Measured.** The GamePad exactly as photographed: white-ish face buttons, a
    /// visibly greyer d-pad and system row - that split is real, not a design choice, and
    /// keeping it is what makes this the "official white" rather than a flat recolour.
    static let wiiUWhite = MuffinColourFile(
        name: "Wii U White",
        fills: ["face": Sampled.faceFill, "dpad": Sampled.dpadFill, "start": Sampled.systemFill,
                "select": Sampled.systemFill, "shoulderL": Sampled.systemFill, "shoulderR": Sampled.systemFill,
                "stickL": Sampled.stickFill, "stickR": Sampled.stickFill, "home": .init("#FFFFFF"),
                "default": Sampled.faceFill],
        glyphs: ["default": Sampled.glyphGrey, "home": Sampled.homeGlyph],
        outline: Sampled.outlineGrey)

    /// **Measured, same source image.** Not a separate preset invented for variety - the
    /// d-pad and system-button plastic the White preset already keeps distinct, promoted
    /// to be the fill for every group. This is the one Wii U colour that needed no
    /// invention at all: it was already sitting in the reference photograph.
    static let wiiUGrey = MuffinColourFile(
        name: "Wii U Grey",
        fills: ["default": Sampled.dpadFill],
        glyphs: ["default": MuffinRGBA("#3A3A3C")],
        outline: MuffinRGBA("#8A8A8E"))

    /// **Derived, not measured.** There is no black-GamePad photograph in this repository.
    /// Built to the one relationship the white preset's measurement actually established -
    /// buttons a shade lighter than the housing around them, dark glyphs on a light
    /// button - inverted onto a dark housing rather than copied from a source that does
    /// not exist here. Flagged so nobody mistakes it for a second sampling pass.
    static let wiiUBlack = MuffinColourFile(
        name: "Wii U Black",
        fills: ["default": MuffinRGBA("#3A3A3D")],
        glyphs: ["default": MuffinRGBA("#D8D8DA")],
        outline: MuffinRGBA("#1C1C1E"),
        shell: MuffinRGBA("#151516"))

    /// **Approximate, not pixel-sampled** - there is no Super Famicom hardware in this
    /// repository either, so these are the widely-cited console colours rather than a
    /// measurement. Requested by name over a genuine "Wii U official coloured buttons"
    /// preset, because the Wii U GamePad was never sold with coloured face buttons - the
    /// closest real Nintendo colour scheme for a coloured A/B/X/Y is this one.
    static let superFamicom = MuffinColourFile(
        name: "Super Famicom",
        fills: ["A": .init("#5FB84E"), "B": .init("#E8C33B"), "X": .init("#4E7FD0"), "Y": .init("#D14B45"),
                "default": Sampled.dpadFill],
        glyphs: ["A": .init("#FFFFFF"), "B": .init("#FFFFFF"), "X": .init("#FFFFFF"), "Y": .init("#FFFFFF"),
                 "default": Sampled.glyphGrey],
        outline: Sampled.outlineGrey)

    /// **Inspired by description, not sourced** - built from "see-through white, like
    /// MelonX", which was given as a reference rather than a file this repository has
    /// access to. Low fill alpha rather than zero, so a control is still findable by eye
    /// before a thumb finds it by touch; the pressed-alpha boost carries more of the
    /// affordance here than anywhere else in the catalog, since idle it is close to
    /// invisible on purpose.
    static let frostedGlass = MuffinColourFile(
        name: "Frosted Glass",
        fills: ["default": MuffinRGBA(r: 1, g: 1, b: 1, a: 0.14)],
        glyphs: ["default": MuffinRGBA(r: 1, g: 1, b: 1, a: 0.55)],
        outline: MuffinRGBA(r: 1, g: 1, b: 1, a: 0.35),
        pressedAlphaBoost: 0.30)

    /// Splatoon shipped as a Wii U launch-window exclusive, so its ink colours are a
    /// closer fit to "a Wii U game's own palette" than a generic neon preset would be.
    static let inkling = MuffinColourFile(
        name: "Inkling",
        fills: ["A": .init("#0FF0C0"), "B": .init("#FF4E9E"), "X": .init("#FFE137"), "Y": .init("#8B3FFD"),
                "default": MuffinRGBA("#1B1B22")],
        glyphs: ["default": .init("#F4F4F5")],
        outline: MuffinRGBA(r: 1, g: 1, b: 1, a: 0.25))

    /// High-contrast rather than themed: pure black glyphs on pure white fills, a heavy
    /// outline, no colour anywhere. For low vision or a bright outdoor screen, where every
    /// other preset in this file is optimised for looking good, not for being findable.
    static let highContrast = MuffinColourFile(
        name: "High Contrast",
        fills: ["default": MuffinRGBA("#FFFFFF")],
        glyphs: ["default": MuffinRGBA("#000000")],
        outline: MuffinRGBA("#000000"),
        pressedAlphaBoost: 0)

    /// A terminal green, for the part of the audience playing an emulator because they
    /// like that a thing this old still runs at all.
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

    /// The interactive slot. `MuffinColourFile(name: "Custom", fills: [:], ...)` is the
    /// starting point `PadColourPickerView` edits in place - it is a real, saveable preset
    /// like every other one here, just one whose fills start empty and get written by a
    /// person instead of by this file.
    static let customStarter = MuffinColourFile(
        name: "Custom", fills: ["default": Sampled.faceFill],
        glyphs: ["default": Sampled.glyphGrey], outline: Sampled.outlineGrey)

    static let all: [MuffinColourFile] = [
        wiiUWhite, wiiUGrey, wiiUBlack, superFamicom, frostedGlass,
        inkling, highContrast, terminal, sunset, customStarter,
    ]
}

// MARK: - The Custom picker

/// One row per control group, a `ColorPicker` for its fill and its glyph, live on the pad
/// behind the sheet. Grouped by `PadGroup` rather than by raw control id for the same
/// reason moving is grouped that way: nobody wants to colour X, Y, A and B one at a time
/// when they are, and always have been, one decision.
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

    /// Sticks and the menu row are left out of the per-group list, not because they
    /// cannot be recoloured - `fill(_:)` will still find them by id if someone edits the
    /// JSON by hand - but because the sheet already has nine sections without them and a
    /// stick's own base/knob split does not collapse into one swatch cleanly.
    private var colourableGroups: [PadGroup] { [.dpad, .face, .start, .select] }

    private func colourRow(_ label: String, key: String?, isGlyph: Bool, isOutline: Bool = false) -> some View {
        let binding = Binding<Color>(
            get: {
                let c = isOutline ? scheme.outline : (isGlyph ? (key.flatMap { scheme.glyphs[$0] } ?? scheme.glyph("default"))
                                                              : (key.flatMap { scheme.fills[$0] } ?? scheme.fill("default")))
                return Color(red: c.r, green: c.g, blue: c.b, opacity: c.a)
            },
            set: { newColor in
                guard let comps = newColor.cgColor?.components, comps.count >= 3 else { return }
                let rgba = MuffinRGBA(r: comps[0], g: comps[1], b: comps[2], a: comps.count > 3 ? comps[3] : 1)
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

//  ---------------------------------------------------------------------------------
//  WIRING
//
//  1. Move this file to src/ios/App/ alongside GamePadGeometry.swift and
//     MuffinPadCustomisation.swift.
//
//  2. Replace `ControllerSkinsLibrary.getSkin(by:)`'s catalog with `MuffinColourPresets.all`
//     plus whichever of the 14 non-duplicate shipping skins should stay (Standard, Wii U
//     Original, Nintendo 64, NES, Switch Pro, PlayStation, Arcade Cabinet, Sega Genesis,
//     Minimal, Glass, Neon, Mario Theme, Zelda Theme keep their current definitions
//     unchanged; GameCube, Super Nintendo, Xbox, Dark Mode, Light Mode and Steam Deck are
//     the ones the measurement found redundant - see GAMEPAD_LAYOUT.md's cull table for
//     the distance numbers and which surviving skin each name should redirect existing
//     users to). The shipping `WiiUControllerSkin` and this file's `MuffinColourFile` are
//     two different shapes - a small adapter converting one to the other is the rest of
//     this step, not a rewrite of ControllerPad's drawing code.
//
//  3. `.fileExporter`/`.fileImporter` with `MuffinColourDocument`/`MuffinLayoutDocument`
//     is the standard SwiftUI pattern; nothing here depends on anything else being wired
//     in first.
//
//  4. `@AppStorage` for "which preset is active" should store the preset's `name`, with
//     `MuffinColourPresets.all.first(where: { $0.name == stored })` as the lookup and the
//     Custom slot's own JSON blob as a separate key - the same shape
//     `ControllerCustomLayout` already uses for per-element overrides.
