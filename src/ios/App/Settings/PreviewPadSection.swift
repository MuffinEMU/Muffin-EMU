import SwiftUI
import UniformTypeIdentifiers

/// Off by default. Everything else in Settings and the shipping app is unaffected
/// by whatever is chosen here - see EmulatorViewOptimized's branch on
/// PreviewPadStore.enabledKey for exactly what turning this on changes and what
/// stays untouched. The header carries an icon and a distinct colour, not just the
/// word "Preview" in plain text, because every other section header in this Form
/// looks the same and this is the one section that is not shipping-quality yet.
struct PreviewPadSection: View {
    // A real ObservedObject on the shared store, not a second set of @AppStorage vars
    // pointed at the same keys - PreviewPadStore only reads UserDefaults once, at
    // launch, so a separate @AppStorage binding here would write the key correctly but
    // leave the store's own @Published value - the thing the live pad actually reads -
    // stale until relaunch. Binding straight to the store is what makes a change here
    // reach a game already running with the pad on screen.
    @AppStorage(PreviewPadStore.enabledKey) private var previewPadEnabled = PreviewPadStore.defaultEnabled
    @ObservedObject private var previewPad = PreviewPadStore.shared
    @State private var showingLayoutExporter = false
    @State private var showingLayoutImporter = false
    @State private var showingColourExporter = false
    @State private var showingColourImporter = false
    @State private var previewFileErrorMessage: String?

    private var previewLayoutPresetBinding: Binding<String> {
        Binding(get: { previewPad.layoutPreset.rawValue },
               set: { previewPad.layoutPreset = PreviewLayoutPreset(rawValue: $0) ?? .iPadPro2020 })
    }
    private var previewColourPresetBinding: Binding<String> {
        Binding(get: { previewPad.colourPreset.rawValue },
               set: { previewPad.colourPreset = PreviewColourPreset(rawValue: $0) ?? .wiiUWhite })
    }
    private var previewDisplayModeBinding: Binding<String> {
        Binding(get: { previewPad.displayMode.rawValue },
               set: { previewPad.displayMode = PadLayout.DisplayMode(rawValue: $0) ?? .fit })
    }
    private var previewLayoutPreset: PreviewLayoutPreset { previewPad.layoutPreset }
    private var previewColourPreset: PreviewColourPreset { previewPad.colourPreset }

    var body: some View {
        Section {
            Toggle(isOn: $previewPadEnabled) {
                Text("Use the new pad system")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .tint(MuffinTheme.pixelBlue)

            if previewPadEnabled {
                previewControls
            }
        } header: {
            Label("Preview: New Pad System", systemImage: "wrench.and.screwdriver")
                .foregroundColor(.orange)
        } footer: {
            InfoButton.footer(
                "Every control group can be dragged and pinch-resized once this is on, the same way the shipping pad's edit mode works. This hasn't run on a real device yet - turn it back off if something looks wrong; nothing else in the app depends on it.",
                title: "Preview: New Pad System",
                text: "Every group - both shoulders, both sticks, the d-pad, A/B/X/Y, Start, Select, HOME - can be dragged and pinch-resized once this is on: tap the move icon in the top bar during a game, the same way the shipping pad's edit mode works.\n\nFit fills the screen with controls floating on top. Native sizes the picture to whatever the clusters leave room for and never lets a control cover it - small and letterboxed on a phone, life-size and framed on an iPad.\n\nThis has not run on a real device yet. If something looks wrong, turn it back off - nothing else in the app depends on it.")
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        .fileExporter(isPresented: $showingLayoutExporter,
                     document: MuffinLayoutDocument(currentLayoutFile()),
                     contentType: .muffinLayout,
                     defaultFilename: previewLayoutPreset.title) { _ in }
        .fileImporter(isPresented: $showingLayoutImporter, allowedContentTypes: [.muffinLayout]) { result in
            importLayout(result)
        }
        .fileExporter(isPresented: $showingColourExporter,
                     document: MuffinColourDocument(previewColourPreset.file),
                     contentType: .muffinColour,
                     defaultFilename: previewColourPreset.file.name) { _ in }
        .fileImporter(isPresented: $showingColourImporter, allowedContentTypes: [.muffinColour]) { result in
            importColour(result)
        }
        .alert("Error", isPresented: .constant(previewFileErrorMessage != nil),
              presenting: previewFileErrorMessage) { _ in
            Button("OK", role: .cancel) { previewFileErrorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder private var previewControls: some View {
        Picker("Layout", selection: previewLayoutPresetBinding) {
            ForEach(PreviewLayoutPreset.allCases) { preset in
                Text(preset.title).tag(preset.rawValue)
            }
        }
        .pickerStyle(.menu)
        .tint(MuffinTheme.pixelBlue)
        Text(previewLayoutPreset.summary)
            .font(.system(size: 12))
            .foregroundColor(.secondary)

        Picker("Colours", selection: previewColourPresetBinding) {
            ForEach(PreviewColourPreset.allCases) { preset in
                Text(preset.file.name).tag(preset.rawValue)
            }
        }
        .pickerStyle(.menu)
        .tint(MuffinTheme.pixelBlue)

        Picker("Picture", selection: previewDisplayModeBinding) {
            Text("Fit").tag(PadLayout.DisplayMode.fit.rawValue)
            Text("Native").tag(PadLayout.DisplayMode.native.rawValue)
        }
        .pickerStyle(.segmented)

        Button(role: .destructive) {
            PreviewPadStore.shared.resetAdjustments()
        } label: {
            Label("Reset dragged/resized groups", systemImage: "arrow.counterclockwise")
        }

        Button {
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
                previewFileErrorMessage = "Couldn't access that file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let file = try MuffinLayoutFile.decode(data)
            PreviewPadStore.shared.applyImportedLayout(file)
        } catch {
            previewFileErrorMessage = "Couldn't import that .muffinlyt file: \(error.localizedDescription)"
        }
    }

    private func importColour(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                previewFileErrorMessage = "Couldn't access that file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            _ = try MuffinColourFile.decode(data)
            // The three shipping presets in this preview are a fixed set (white/black/
            // Super Famicom); a genuinely custom imported palette is what
            // MuffinColourPresets.customStarter and PadColourPickerView exist for in the
            // full colour system - out of scope for this showcase build's 3-preset
            // picker, so this only validates the file rather than pretending to apply it.
            previewFileErrorMessage = "Imported and verified - custom colour slots aren't in this preview build's 3-preset picker yet."
        } catch {
            previewFileErrorMessage = "Couldn't import that .muffinclr file: \(error.localizedDescription)"
        }
    }
}
