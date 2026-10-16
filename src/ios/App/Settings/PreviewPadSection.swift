// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import SwiftUI
import UniformTypeIdentifiers

/// Off by default. While on, the experimental pad replaces the normal one; everything
/// else in Settings is unaffected. Its header is orange, the `.preview` accent, to mark
/// the one section that isn't finished.
struct PreviewPadSection: View {
    // Bound to the shared store directly (not separate @AppStorage vars), because the store
    // only reads UserDefaults at launch and the live pad reads its @Published values.
    @AppStorage(PreviewPadStore.enabledKey) private var previewPadEnabled = PreviewPadStore.defaultEnabled
    @ObservedObject private var previewPad = PreviewPadStore.shared
    // Either of these wins over the Preview pad (ContentView's padSystem), so say so here.
    @AppStorage(MeloControlsSetting.storageKey) private var useMeloControls = MeloControlsSetting.defaultValue
    @AppStorage(TouchLabSettings.schemeKey) private var touchLabScheme = TouchLabSettings.defaultScheme
    @State private var showingLayoutExporter = false
    /// Filled by the Export button, so the layout is captured once on tap, not on every render.
    @State private var layoutDocument = LazyLayoutDocument(file: nil)
    @State private var showingLayoutImporter = false
    @State private var showingColourExporter = false
    @State private var showingColourImporter = false
    @State private var previewFileErrorMessage: String?
    @State private var previewFileAlertTitle = "Import failed"
    @State private var showingResetAdjustmentsConfirmation = false

    private var previewLayoutPresetBinding: Binding<String> {
        Binding(get: { previewPad.layoutPreset.rawValue },
               set: { previewPad.layoutPreset = PreviewLayoutPreset(rawValue: $0) ?? .native })
    }
    private var previewColourPresetBinding: Binding<String> {
        Binding(get: { previewPad.customColours == nil ? previewPad.colourPreset.rawValue : Self.customColourTag },
               set: { if $0 != Self.customColourTag { previewPad.colourPreset = PreviewColourPreset(rawValue: $0) ?? .wiiUWhite } })
    }
    private var previewDisplayModeBinding: Binding<String> {
        Binding(get: { previewPad.displayMode.rawValue },
               set: { previewPad.displayMode = PadLayout.DisplayMode(rawValue: $0) ?? .fit })
    }
    private var previewLayoutPreset: PreviewLayoutPreset { previewPad.layoutPreset }
    /// The picker's extra row while imported colours are in effect.
    private static let customColourTag = "custom"

    private var otherPadChosen: Bool {
        (useMeloControls && MeloControlsSetting.isAvailable) || TouchLabSettings.isTouchLab(touchLabScheme)
    }

    private var toggleCaption: String {
        if previewPadEnabled && otherPadChosen {
            return "Not active: Melo-Controller or a control style is chosen under On-screen controls, and takes priority."
        }
        return previewPadEnabled
            ? "Replaces the normal pad. If controls don't respond, turn this off."
            : "Experimental. Replaces the normal pad while on."
    }

    var body: some View {
        Section {
            Toggle(isOn: $previewPadEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use the new pad")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(toggleCaption)
                        .font(.system(size: 12))
                        .foregroundColor(previewPadEnabled && !otherPadChosen ? MuffinTheme.cautionText : MuffinTheme.secondaryText)
                }
            }
            .tint(MuffinTheme.accentText)

            // Hidden while another pad wins over this one: the options wouldn't change anything on screen.
            if previewPadEnabled && !otherPadChosen {
                previewControls
            }
        } header: {
            SettingsSectionHeader("New pad (preview)",
                                  icon: "wrench.and.screwdriver", accent: .preview)
        } footer: {
            InfoButton.footer(
                "Try a new movable, resizable pad layout. It replaces the normal pad while on, so turn it off if controls stop responding.",
                title: "New pad (preview)",
                text: "You can drag and pinch-resize every group of controls (shoulders, sticks, d-pad, A/B/X/Y, Start, Select, HOME). Tap the move icon in the top bar during a game.\n\nFit floats the controls over the screen. Native makes the picture fit around the controls: small on a phone, life-size on an iPad.\n\nThis pad is experimental.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .fileExporter(isPresented: $showingLayoutExporter,
                     document: layoutDocument,
                     contentType: .muffinLayout,
                     defaultFilename: previewLayoutPreset.title) { _ in }
        .fileImporter(isPresented: $showingLayoutImporter, allowedContentTypes: [.muffinLayout]) { result in
            importLayout(result)
        }
        .fileExporter(isPresented: $showingColourExporter,
                     document: MuffinColourDocument(previewPad.colourFile),
                     contentType: .muffinColour,
                     defaultFilename: previewPad.colourFile.name) { _ in }
        .fileImporter(isPresented: $showingColourImporter, allowedContentTypes: [.muffinColour]) { result in
            importColour(result)
        }
        .alert(previewFileAlertTitle,
              isPresented: Binding(get: { previewFileErrorMessage != nil },
                                   set: { if !$0 { previewFileErrorMessage = nil } }),
              presenting: previewFileErrorMessage) { _ in
            Button("OK", role: .cancel) { previewFileErrorMessage = nil }
        } message: { message in
            Text(message)
        }
        .confirmationDialog("Reset moved and resized groups?", isPresented: $showingResetAdjustmentsConfirmation, titleVisibility: .visible) {
            Button("Reset moved and resized groups", role: .destructive) {
                PreviewPadStore.shared.resetAdjustments()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Every group goes back to the preset's positions and sizes. Your preset, colours and picture mode stay.")
        }
    }

    @ViewBuilder private var previewControls: some View {
        Picker("Layout", selection: previewLayoutPresetBinding) {
            ForEach(PreviewLayoutPreset.allCases) { preset in
                Text(preset.title).tag(preset.rawValue)
            }
        }
        .pickerStyle(.menu)
        .tint(MuffinTheme.accentText)
        Text(previewLayoutPreset.summary)
            .font(.system(size: 12))
            .foregroundColor(MuffinTheme.secondaryText)

        Picker("Colours", selection: previewColourPresetBinding) {
            ForEach(PreviewColourPreset.allCases) { preset in
                Text(preset.file.name).tag(preset.rawValue)
            }
            if let custom = previewPad.customColours {
                Text(custom.name).tag(Self.customColourTag)
            }
        }
        .pickerStyle(.menu)
        .tint(MuffinTheme.accentText)

        Picker("Picture", selection: previewDisplayModeBinding) {
            Text("Fit").tag(PadLayout.DisplayMode.fit.rawValue)
            Text("Native").tag(PadLayout.DisplayMode.native.rawValue)
        }
        .pickerStyle(.segmented)

        Button(role: .destructive) {
            showingResetAdjustmentsConfirmation = true
        } label: {
            DestructiveSettingsLabel(title: "Reset moved and resized groups", systemImage: "arrow.counterclockwise")
        }

        Button {
            layoutDocument = LazyLayoutDocument(file: currentLayoutFile())
            showingLayoutExporter = true
        } label: {
            Label("Export layout (.muffinlyt)", systemImage: "square.and.arrow.up")
        }
        Button {
            showingLayoutImporter = true
        } label: {
            Label("Import layout (.muffinlyt)", systemImage: "square.and.arrow.down")
        }
        Button {
            showingColourExporter = true
        } label: {
            Label("Export colours (.muffinclr)", systemImage: "square.and.arrow.up")
        }
        Button {
            showingColourImporter = true
        } label: {
            Label("Import colours (.muffinclr)", systemImage: "square.and.arrow.down")
        }
    }

    /// A representative container/safe-area to export against when there is no live game
    /// view to measure - the exact reference profile PreviewLayoutPreset.iPadPro2020
    /// itself captures from, so an export made from Settings and one made mid-game agree.
    private func currentLayoutFile() -> MuffinLayoutFile {
        PreviewPadStore.shared.effectiveLayoutFile(
            container: CGSize(width: 1366, height: 1024),
            safeArea: CGRect(x: 0, y: 0, width: 1366, height: 1004),
            pointsPerInch: 132)
    }

    private func importLayout(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                previewFileAlertTitle = "Import failed"
                previewFileErrorMessage = "Couldn't access that file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let file = try MuffinLayoutFile.decode(data)
            PreviewPadStore.shared.applyImportedLayout(file)
        } catch {
            previewFileAlertTitle = "Import failed"
            previewFileErrorMessage = "Couldn't import that .muffinlyt file: \(error.localizedDescription)"
        }
    }

    private func importColour(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                previewFileAlertTitle = "Import failed"
                previewFileErrorMessage = "Couldn't access that file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let file = try MuffinColourFile.decode(data)
            PreviewPadStore.shared.applyImportedColours(file)
        } catch {
            previewFileAlertTitle = "Import failed"
            previewFileErrorMessage = "Couldn't import that .muffinclr file: \(error.localizedDescription)"
        }
    }
}

/// Layout document whose contents are set when export is requested. Empty until then.
private struct LazyLayoutDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.muffinLayout] }
    var file: MuffinLayoutFile?

    init(file: MuffinLayoutFile?) { self.file = file }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        file = try MuffinLayoutFile.decode(data)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let file else { throw CocoaError(.fileWriteUnknown) }
        return FileWrapper(regularFileWithContents: try file.encoded())
    }
}
