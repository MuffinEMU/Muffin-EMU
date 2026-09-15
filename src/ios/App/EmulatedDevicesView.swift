import SwiftUI
import UniformTypeIdentifiers

/// The three toy-to-life peripherals nsyshid emulates (Cafe/OS/libs/nsyshid/Skylander.cpp,
/// Infinity.cpp, Dimensions.cpp) and the fixed slot layout each one exposes. Slot counts
/// and labels mirror the real hardware: 16 Skylanders on a portal, 9 Infinity positions
/// (a play set/power-disc row plus two players' own figure and two ability pieces each),
/// 7 Dimensions toypad positions across its left/center/right pads.
enum EmulatedDevice: Int, CaseIterable, Identifiable {
    case skylanders, infinity, dimensions

    var id: Int { rawValue }

    var bridgeDevice: CemuBridgeUSBDevice {
        switch self {
        case .skylanders: return CEMU_BRIDGE_USB_DEVICE_SKYLANDERS
        case .infinity: return CEMU_BRIDGE_USB_DEVICE_INFINITY
        case .dimensions: return CEMU_BRIDGE_USB_DEVICE_DIMENSIONS
        }
    }

    var name: String {
        switch self {
        case .skylanders: return "Skylanders Portal"
        case .infinity: return "Disney Infinity Base"
        case .dimensions: return "LEGO Dimensions Toypad"
        }
    }

    /// The Settings toggle this device's "Emulate Device" switch here mirrors - same
    /// UserDefaults key EmulatedDevicesSettingsSection.swift and ContentView.swift read,
    /// so flipping it from either place agrees with the other immediately.
    var enabledStorageKey: String {
        switch self {
        case .skylanders: return EmulatedDevicesSettings.skylanderPortalKey
        case .infinity: return EmulatedDevicesSettings.infinityBaseKey
        case .dimensions: return EmulatedDevicesSettings.dimensionsToypadKey
        }
    }

    func setEmulated(_ enabled: Bool) {
        switch self {
        case .skylanders: cemu_bridge_set_emulate_skylander_portal(enabled)
        case .infinity: cemu_bridge_set_emulate_infinity_base(enabled)
        case .dimensions: cemu_bridge_set_emulate_dimensions_toypad(enabled)
        }
    }

    /// Documents/Emulated Devices/<folderName>/ - kept distinct from `name` so a later
    /// label change can't silently move where existing figure files live on disk.
    var folderName: String { name }

    var fileExtension: String { self == .skylanders ? "sky" : "bin" }

    var slotLabels: [String] {
        switch self {
        case .skylanders:
            return (1...16).map { "Skylander \($0)" }
        case .infinity:
            return ["Play Set / Power Disc", "Power Disc Two", "Power Disc Three",
                    "Player One", "Player One Ability One", "Player One Ability Two",
                    "Player Two", "Player Two Ability One", "Player Two Ability Two"]
        case .dimensions:
            return ["Left Pad: Top", "Center Pad", "Right Pad: Top",
                    "Left Pad: Bottom Left", "Left Pad: Bottom Right",
                    "Right Pad: Bottom Left", "Right Pad: Bottom Right"]
        }
    }
}

/// A figure the core's own built-in table recognizes for a given device/slot - metadata
/// only (see cemu_bridge_usb_device_figure_list's doc comment). Not figure save data.
struct EmulatedFigureOption: Identifiable, Hashable {
    let figureID: UInt32
    let variant: UInt16
    let name: String
    var id: String { "\(figureID)-\(variant)" }
}

/// Where figure files live: Documents/Emulated Devices/<device>/, one UUID subfolder per
/// figure so two figures sharing a display name can't collide on the same filename - same
/// per-feature top-level folder convention SaveStateStore.swift uses for save states.
enum EmulatedFigureStore {
    static func directory(for device: EmulatedDevice) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents
            .appendingPathComponent("Emulated Devices", isDirectory: true)
            .appendingPathComponent(device.folderName, isDirectory: true)
    }

    @discardableResult
    private static func ensureDirectoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue
        }
        return (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)) != nil
    }

    /// A fresh, not-yet-existing path for a new figure file, sanitized so a figure name
    /// can never be read as a path component.
    static func newFileURL(for device: EmulatedDevice, name: String) -> URL? {
        guard ensureDirectoryExists(directory(for: device)) else { return nil }
        let folder = directory(for: device).appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard ensureDirectoryExists(folder) else { return nil }
        let safeName = name
            .components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return folder
            .appendingPathComponent(safeName.isEmpty ? "Figure" : safeName)
            .appendingPathExtension(device.fileExtension)
    }

    /// Copies a user-picked (possibly security-scoped) file into our own folder. Always
    /// copies rather than loading in place - DocumentImport hands back a URL outside our
    /// sandboxed storage, and cemu_bridge_usb_device_load()/Clear() below assume the path
    /// they were given keeps working for as long as the figure stays loaded.
    static func importFile(_ source: URL, device: EmulatedDevice) -> URL? {
        guard let destination = newFileURL(for: device, name: source.deletingPathExtension().lastPathComponent) else {
            return nil
        }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        guard (try? FileManager.default.copyItem(at: source, to: destination)) != nil else { return nil }
        return destination
    }
}

/// The in-game figure manager, opened from EmulatorViewOptimized's top bar (ContentView.swift)
/// while any of the three peripherals is on, and reachable from Settings' "Manage Figures"
/// link regardless. Ported from MeloCafe's EmulatedDevicesView.swift onto this app's own
/// cemu_bridge_usb_device_* bridge and Documents-file storage convention.
struct EmulatedDevicesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var device = EmulatedDevice.skylanders

    var body: some View {
        NavigationView {
            ZStack {
                MuffinTheme.backgroundGradient.ignoresSafeArea()

                List {
                    Section {
                        Picker("Device", selection: $device) {
                            ForEach(EmulatedDevice.allCases) { device in
                                Text(device.name).tag(device)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(MuffinTheme.pixelBlue)
                        Toggle(isOn: deviceEnabled) {
                            Text("Emulate Device")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .tint(MuffinTheme.pixelBlue)
                    }

                    EmulatedDeviceSlotsSection(device: device)
                        .id(device)
                }
            }
            .navigationTitle("Emulated Devices")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var deviceEnabled: Binding<Bool> {
        Binding(
            get: {
                UserDefaults.standard.object(forKey: device.enabledStorageKey) as? Bool
                    ?? EmulatedDevicesSettings.defaultEnabled
            },
            set: { newValue in
                UserDefaults.standard.set(newValue, forKey: device.enabledStorageKey)
                device.setEmulated(newValue)
            }
        )
    }
}

private struct EmulatedDeviceSlotsSection: View {
    let device: EmulatedDevice
    @State private var slotNames: [String] = []
    @State private var errorMessage: String?

    var body: some View {
        Section {
            ForEach(device.slotLabels.indices, id: \.self) { slot in
                VStack(alignment: .leading, spacing: 8) {
                    Text(device.slotLabels[slot])
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(name(at: slot).isEmpty ? "None" : name(at: slot))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    HStack(spacing: 20) {
                        Button("Load") { load(slot: slot) }
                        NavigationLink("Create") {
                            CreateEmulatedFigureView(device: device, slot: slot, onCreated: refresh)
                        }
                        if device == .dimensions {
                            Menu("Move") {
                                ForEach(device.slotLabels.indices, id: \.self) { destination in
                                    if destination != slot && name(at: destination).isEmpty {
                                        Button(device.slotLabels[destination]) {
                                            let error = cemu_bridge_usb_device_move_dimensions(Int32(slot), Int32(destination))
                                            errorMessage = error.map { String(cString: $0) }
                                            refresh()
                                        }
                                    }
                                }
                            }
                            .disabled(name(at: slot).isEmpty || !slotNames.contains(""))
                        }
                        Spacer(minLength: 0)
                        Button("Clear", role: .destructive) {
                            let error = cemu_bridge_usb_device_clear(device.bridgeDevice, Int32(slot))
                            errorMessage = error.map { String(cString: $0) }
                            refresh()
                        }
                        .disabled(name(at: slot).isEmpty)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Figures")
        } footer: {
            Text("Load a .\(device.fileExtension) figure dump or create a figure. Files and game progress are saved in Documents/Emulated Devices. Clear removes a figure from the device and keeps its file.")
        }
        .onAppear(perform: refresh)
        .alert("Emulated Devices", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func name(at slot: Int) -> String {
        slotNames.indices.contains(slot) ? slotNames[slot] : ""
    }

    private func refresh() {
        // Fixed slot count per device (7-16), never zero, so - unlike
        // GraphicPacksView's pack list - there is no legitimate empty-string case to
        // guard against: an all-empty device still yields one record per slot,
        // separated by 0x1E.
        let raw = String(cString: cemu_bridge_usb_device_slot_names(device.bridgeDevice))
        slotNames = raw.components(separatedBy: "\u{1E}")
    }

    private func load(slot: Int) {
        DocumentImport.present(contentTypes: [.item]) { result in
            switch result {
            case .success(let urls):
                guard let source = urls.first else { return }
                guard let file = EmulatedFigureStore.importFile(source, device: device) else {
                    errorMessage = "Couldn't copy that file into Documents/Emulated Devices."
                    return
                }
                let error = file.path.withCString { cemu_bridge_usb_device_load(device.bridgeDevice, Int32(slot), $0) }
                errorMessage = error.map { String(cString: $0) }
                refresh()
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct CreateEmulatedFigureView: View {
    let device: EmulatedDevice
    let slot: Int
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var figures: [EmulatedFigureOption] = []
    @State private var selectedName = "Choose a Figure"
    @State private var figureID = ""
    @State private var variant = "0"
    @State private var fileName = ""
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            MuffinTheme.backgroundGradient.ignoresSafeArea()

            Form {
                Section("Figure") {
                    NavigationLink(selectedName) {
                        EmulatedFigurePicker(figures: figures) { figure in
                            selectedName = figure.name
                            figureID = String(figure.figureID)
                            variant = String(figure.variant)
                            fileName = figure.name
                        }
                    }

                    TextField("Figure ID", text: $figureID)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    if device == .skylanders {
                        TextField("Variant", text: $variant)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }
                Section {
                    TextField("File Name", text: $fileName)
                        .autocorrectionDisabled()
                } footer: {
                    Text("A new .\(device.fileExtension) file will be saved in Documents/Emulated Devices and loaded into \(device.slotLabels[slot]).")
                }
                if device == .dimensions {
                    Section {
                        Text("Use figure ID 0 to create a blank vehicle or gadget tag for the game to write.")
                            .foregroundColor(.secondary)
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundColor(MuffinTheme.blushPink)
                    }
                }
            }
            .navigationTitle("Create Figure")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(figureID.isEmpty)
                }
            }
            .onAppear {
                if figures.isEmpty {
                    figures = parseFigures(String(cString: cemu_bridge_usb_device_figure_list(device.bridgeDevice, Int32(slot))))
                }
            }
        }
    }

    private func parseFigures(_ raw: String) -> [EmulatedFigureOption] {
        guard !raw.isEmpty else { return [] }
        return raw.components(separatedBy: "\u{1E}").compactMap { record in
            let fields = record.components(separatedBy: "\u{1F}")
            guard fields.count >= 3, let id = UInt32(fields[0]), let variant = UInt16(fields[1]) else { return nil }
            return EmulatedFigureOption(figureID: id, variant: variant, name: fields[2])
        }
    }

    private func create() {
        guard let id = UInt32(figureID), device == .infinity || id <= UInt16.max else {
            errorMessage = device == .infinity ? "Enter a valid 32-bit figure ID." : "Enter a figure ID between 0 and 65535."
            return
        }
        guard let variantNumber = UInt16(variant) else {
            errorMessage = "Enter a variant between 0 and 65535."
            return
        }
        guard let file = EmulatedFigureStore.newFileURL(for: device, name: fileName.isEmpty ? "Figure \(id)" : fileName) else {
            errorMessage = "Couldn't create a file in Documents/Emulated Devices."
            return
        }

        if let error = file.path.withCString({ path in
            cemu_bridge_usb_device_create(device.bridgeDevice, id, variantNumber, path)
        }) {
            errorMessage = String(cString: error)
            return
        }

        if let error = file.path.withCString({ cemu_bridge_usb_device_load(device.bridgeDevice, Int32(slot), $0) }) {
            errorMessage = "The figure was saved, but could not be loaded: \(String(cString: error))"
            return
        }

        onCreated()
        dismiss()
    }
}

private struct EmulatedFigurePicker: View {
    let figures: [EmulatedFigureOption]
    let onSelect: (EmulatedFigureOption) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filteredFigures: [EmulatedFigureOption] {
        figures.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || String($0.figureID).contains(search)
        }
    }

    var body: some View {
        ZStack {
            MuffinTheme.backgroundGradient.ignoresSafeArea()

            List(filteredFigures) { figure in
                Button {
                    onSelect(figure)
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(figure.name)
                        Text("ID: \(figure.figureID)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Choose a Figure")
        .searchable(text: $search, prompt: "Search names or IDs")
    }
}
