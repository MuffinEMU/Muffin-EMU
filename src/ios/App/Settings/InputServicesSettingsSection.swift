import SwiftUI

/// MFi/Bluetooth physical controllers and which Wii U role each is assigned - the
/// GamePad, a Pro Controller, a Classic Controller, or a Wiimote. Entirely separate
/// from OnScreenControlsSection: the on-screen pad is its own always-present input
/// path (ControllerPad.swift/MeloControls.swift) and isn't listed or configured here.
///
/// UX mirrors MeloCafe's own Controllers section (UI/Settings/SettingsView.swift):
/// a reorderable, deletable list of connected controllers, each with a context menu to
/// pick its role, plus a menu of disconnected-but-recently-seen controllers to bring
/// back. State and the actual core registration live in PhysicalControllerManager.
struct InputServicesSettingsSection: View {
    @ObservedObject private var controllerManager = PhysicalControllerManager.shared

    var body: some View {
        Section {
            if controllerManager.controllers.isEmpty {
                Text("No physical controllers connected")
                    .foregroundColor(MuffinTheme.brownMid)
            }

            ForEach(controllerManager.controllers) { entry in
                InputServicesControllerRow(entry: entry)
                    .contextMenu {
                        ForEach(ControllerType.allCases) { type in
                            Button {
                                controllerManager.setControllerType(id: entry.id, to: type)
                            } label: {
                                if entry.controllerType == type {
                                    Label(type.name, systemImage: "checkmark")
                                } else {
                                    Text(type.name)
                                }
                            }
                            .disabled(!controllerManager.canSelectType(type, for: entry.id))
                        }
                    }
            }
            .onMove { source, destination in
                controllerManager.move(from: source, to: destination)
            }
            .onDelete { offsets in
                let ids = offsets.map { controllerManager.controllers[$0].id }
                for id in ids { controllerManager.remove(id: id) }
            }

            Button(action: { controllerManager.rescan() }) {
                Label("Scan for Controllers", systemImage: "arrow.clockwise")
            }
            .foregroundColor(MuffinTheme.brownDarkest)
        } header: {
            Text("Input Services")
        } footer: {
            InfoButton.footer(
                "MFi/Bluetooth controllers pair like any other Bluetooth accessory - press A on it, or use Settings > Bluetooth, then assign its Wii U role here. Long-press a row to change its role; swipe to remove it; drag to reorder player slots.",
                title: "Input Services",
                text: "Connect a physical controller (a GameSir, a PS5/Xbox pad, or any Bluetooth/MFi controller) the same way you'd pair it with any other device - through iOS's own Bluetooth settings, or by pressing its pairing button while the app is open. It appears in this list automatically.\n\nEach connected controller can be assigned a Wii U role: the GamePad, a Pro Controller, a Classic Controller, or a Wiimote. Only one controller can hold the GamePad role at a time; up to four more can hold the others. Long-press a controller's row to change its role, drag to reorder which player slot it occupies, or swipe to remove it entirely.\n\nThis is separate from MuffinEMU's own on-screen touch controls, which stay on regardless of what's connected here and work at the same time as a physical controller."
            )
        }
        .foregroundColor(MuffinTheme.brownDarkest)
        // Forces the list's drag handles and delete buttons on unconditionally - this
        // Form has no app-wide Edit button (see SettingsView.swift), and MeloCafe's own
        // Controllers section does the same for the same reason.
        .environment(\.editMode, .constant(.active))
    }
}

private struct InputServicesControllerRow: View {
    let entry: PhysicalControllerEntry

    var body: some View {
        HStack {
            Image(systemName: "gamecontroller")
                .foregroundColor(MuffinTheme.brownMid)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                HStack(spacing: 6) {
                    if entry.hasMotion {
                        Image(systemName: "gyroscope")
                            .font(.caption2)
                    }
                    if entry.hasRumble {
                        Image(systemName: "waveform")
                            .font(.caption2)
                    }
                }
                .foregroundColor(.secondary)
            }
            Spacer()
            Text(entry.controllerType.name)
                .foregroundColor(MuffinTheme.brownMid)
        }
    }
}
