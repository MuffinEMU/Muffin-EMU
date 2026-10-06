import Foundation
import Network
import SwiftUI

/// Watches the device's network path and tells the core, so the emulated Wii U goes online
/// and offline with the iPhone or iPad. Traffic itself already uses the device's own
/// connection, so there is nothing to configure here.
final class DeviceConnection: ObservableObject {
    static let shared = DeviceConnection()

    enum Kind { case offline, wifi, cellular, other }

    @Published private(set) var kind: Kind = .wifi

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "muffin.device-connection")
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let kind: Kind
            if path.status != .satisfied {
                kind = .offline
            } else if path.usesInterfaceType(.wifi) {
                kind = .wifi
            } else if path.usesInterfaceType(.cellular) {
                kind = .cellular
            } else {
                kind = .other
            }
            cemu_bridge_set_device_network(Self.bridgeValue(kind))
            DispatchQueue.main.async { self?.kind = kind }
        }
        monitor.start(queue: queue)
    }

    private static func bridgeValue(_ kind: Kind) -> CemuBridgeDeviceNetwork {
        switch kind {
        case .offline: return CEMU_BRIDGE_DEVICE_NETWORK_OFFLINE
        case .wifi: return CEMU_BRIDGE_DEVICE_NETWORK_WIFI
        case .cellular: return CEMU_BRIDGE_DEVICE_NETWORK_CELLULAR
        case .other: return CEMU_BRIDGE_DEVICE_NETWORK_OTHER
        }
    }
}

/// One status line for the Network Service section: the device's connection, and whether the
/// console will appear connected.
struct DeviceConnectionStatusRow: View {
    @ObservedObject private var connection = DeviceConnection.shared

    private var deviceText: String {
        switch connection.kind {
        case .offline: return "Offline"
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        case .other: return "Connected"
        }
    }

    private var consoleText: String {
        // Read here so it refreshes whenever the device connection changes.
        _ = connection.kind
        let status = cemu_bridge_console_appears_connected()
            ? "The console will appear connected."
            : "The console will appear offline."
        return cemu_bridge_online_play_enabled()
            ? status
            : status + " Online play still needs a linked account and Pretendo."
    }

    var body: some View {
        HStack {
            Text("This device")
            Spacer()
            Text("\(deviceText). \(consoleText)")
                .font(.footnote)
                .multilineTextAlignment(.trailing)
                .opacity(0.7)
        }
        .onAppear { DeviceConnection.shared.start() }
    }
}
