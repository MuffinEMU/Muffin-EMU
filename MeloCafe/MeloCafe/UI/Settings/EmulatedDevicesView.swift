//
//  EmulatedDevicesView.swift
//  MeloCafe
//
//  Created by Stossy11 on 14/9/2026.
//

import SwiftUI
import UniformTypeIdentifiers

enum EmulatedDevice: Int, CaseIterable, Identifiable {
    case skylanders, infinity, dimensions
    
    var id: Int { rawValue }
    var bridge: CemuUSBDevice { CemuUSBDevice(rawValue: rawValue)! }
    
    var name: String {
        switch self {
        case .skylanders: return "Skylanders Portal"
        case .infinity: return "Disney Infinity Base"
        case .dimensions: return "LEGO Dimensions Toypad"
        }
    }
    
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
    
    var enabled: Binding<Bool> {
        switch self {
        case .skylanders: return ConfigManager.shared.emulateSkylanderPortal
        case .infinity: return ConfigManager.shared.emulateInfinityBase
        case .dimensions: return ConfigManager.shared.emulateDimensionsToypad
        }
    }
}

struct EmulatedDevicesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var configManager = ConfigManager.shared
    @State private var device = EmulatedDevice.skylanders
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Device", selection: $device) {
                        ForEach(EmulatedDevice.allCases) { device in
                            Text(device.name).tag(device)
                        }
                    }
                    Toggle("Emulate Device", isOn: device.enabled)
                }
                
                EmulatedDeviceSlotsView(device: device)
                    .id(device)
            }
            .navigationTitle("Emulated Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            device = EmulatedDevice.allCases.first { $0.enabled.wrappedValue } ?? .skylanders
        }
    }
}

private struct EmulatedDeviceSlotsView: View {
    let device: EmulatedDevice
    @State private var names: [String] = []
    @State private var errorMessage: String?
    
    var body: some View {
        Section {
            ForEach(device.slotLabels.indices, id: \.self) { slot in
                VStack(alignment: .leading, spacing: 8) {
                    Text(device.slotLabels[slot])
                        .font(.subheadline.weight(.semibold))
                    Text(name(at: slot).isEmpty ? "None" : name(at: slot))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 20) {
                        Button("Load") { load(slot: slot) }
                        NavigationLink("Create") {
                            CreateEmulatedFigureView(device: device, slot: slot) { refresh() }
                        }
                        if device == .dimensions {
                            Menu("Move") {
                                ForEach(device.slotLabels.indices, id: \.self) { destination in
                                    if destination != slot && name(at: destination).isEmpty {
                                        Button(device.slotLabels[destination]) {
                                            errorMessage = CemuEmulatedUSBDevices.moveDimensions(from: slot, to: destination)
                                            refresh()
                                        }
                                    }
                                }
                            }
                            .disabled(name(at: slot).isEmpty || !names.contains(""))
                        }
                        Spacer(minLength: 0)
                        Button("Clear", role: .destructive) {
                            errorMessage = CemuEmulatedUSBDevices.clear(device.bridge, slot: slot)
                            refresh()
                        }
                        .disabled(name(at: slot).isEmpty)
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Figures")
        } footer: {
            Text("Load a .\(device.fileExtension) figure dump or create a figure. Files and game progress are saved in Documents/Emulated Devices. Clear removes a figure from the device and keeps its file.")
        }
        .onAppear { refresh() }
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
        names.indices.contains(slot) ? names[slot] : ""
    }
    
    private func refresh() {
        names = CemuEmulatedUSBDevices.slotNames(for: device.bridge)
    }
    
    private func load(slot: Int) {
        FileImporterManager.shared.importFiles(types: [.item]) { result in
            switch result {
            case .success(let urls):
                guard let source = urls.first else { return }
                do {
                    let file = try EmulatedFigureFiles.importFigure(source, device: device)
                    errorMessage = CemuEmulatedUSBDevices.load(device.bridge, slot: slot, path: file.path)
                    refresh()
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                let error = error as NSError
                if error.domain != "FileImporterManager" || error.code != 2 {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct CreateEmulatedFigureView: View {
    let device: EmulatedDevice
    let slot: Int
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var figures: [CemuUSBFigure] = []
    @State private var selectedName = "Choose a Figure"
    @State private var figureID = ""
    @State private var variant = "0"
    @State private var fileName = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Figure") {
                NavigationLink {
                    EmulatedFigurePicker(figures: figures) { figure in
                        selectedName = figure.name
                        figureID = String(figure.figureID)
                        variant = String(figure.variant)
                        fileName = figure.name
                    }
                } label: {
                    Text(selectedName)
                }
                
                TextField("Figure ID", text: $figureID)
                    .keyboardType(.numberPad)
                if device == .skylanders {
                    TextField("Variant", text: $variant)
                        .keyboardType(.numberPad)
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
                        .foregroundStyle(.secondary)
                }
            }
            if let errorMessage = errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Create Figure")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { create() }
                    .disabled(figureID.isEmpty)
            }
        }
        .onAppear {
            if figures.isEmpty {
                figures = CemuEmulatedUSBDevices.figures(for: device.bridge, slot: slot)
            }
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
        do {
            let file = try EmulatedFigureFiles.newFile(device: device, name: fileName.isEmpty ? "Figure \(id)" : fileName)
            if let error = CemuEmulatedUSBDevices.create(device.bridge, figureID: id, variant: variantNumber, path: file.path) {
                errorMessage = error
                return
            }
            
            if let error = CemuEmulatedUSBDevices.load(device.bridge, slot: slot, path: file.path) {
                errorMessage = "The figure was saved, but could not be loaded: \(error)"
                return
            }
            
            onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EmulatedFigurePicker: View {
    let figures: [CemuUSBFigure]
    let onSelect: (CemuUSBFigure) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filteredFigures: [CemuUSBFigure] {
        figures.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || String($0.figureID).contains(search) }
    }

    var body: some View {
        List(filteredFigures, id: \.self) { figure in
            Button {
                onSelect(figure)
                dismiss()
            } label: {
                VStack(alignment: .leading) {
                    Text(figure.name)
                    Text("ID: \(figure.figureID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Choose a Figure")
        .searchable(text: $search, prompt: "Search names or IDs")
    }
}

private enum EmulatedFigureFiles {
    private static func directory(device: EmulatedDevice) throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        
        let folder = documents.appendingPathComponent("Emulated Devices", isDirectory: true).appendingPathComponent(device.name, isDirectory: true)
        
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        
        return folder
    }
    
    static func newFile(device: EmulatedDevice, name: String) throws -> URL {
        let folder = try directory(device: device).appendingPathComponent(UUID().uuidString, isDirectory: true)
        
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        
        let safeName = name.components(separatedBy: CharacterSet(charactersIn: "/:\\").union(.controlCharacters)).joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        
        return folder.appendingPathComponent(safeName.isEmpty ? "Figure" : safeName).appendingPathExtension(device.fileExtension)
    }
    
    static func importFigure(_ source: URL, device: EmulatedDevice) throws -> URL {
        let folder = try directory(device: device).resolvingSymlinksInPath()
        let resolved = source.resolvingSymlinksInPath()
        
        if resolved.path.hasPrefix(folder.path + "/") { return resolved }
        
        let destination = try newFile(device: device, name: source.deletingPathExtension().lastPathComponent)
        
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }
}
