import Foundation

/// Which backend an account's online traffic goes to - ported verbatim (by value) from
/// MeloCafe's NetworkService.swift. Only the bridging changes: MeloCafe crosses this as
/// its own ObjCNetworkService Obj-C enum through the CemuConfigWrapper class; this app's
/// plain-C bridge exposes the identical four cases as CemuBridgeNetworkService instead,
/// converted with an explicit switch the same way ContentView.swift/MeloControls.swift
/// already convert CemuBridgeButton, rather than relying on the two enums sharing a
/// raw value representation.
enum NetworkService: Int, CaseIterable, Identifiable {
    case offline = 0
    case nintendo = 1
    case pretendo = 2
    case custom = 3

    var id: Int { rawValue }
    static let onlineCases: [NetworkService] = [.nintendo, .pretendo, .custom]

    init(_ service: CemuBridgeNetworkService) {
        switch service {
        case CEMU_BRIDGE_NETWORK_NINTENDO: self = .nintendo
        case CEMU_BRIDGE_NETWORK_PRETENDO: self = .pretendo
        case CEMU_BRIDGE_NETWORK_CUSTOM: self = .custom
        default: self = .offline
        }
    }

    var bridgeValue: CemuBridgeNetworkService {
        switch self {
        case .offline: return CEMU_BRIDGE_NETWORK_OFFLINE
        case .nintendo: return CEMU_BRIDGE_NETWORK_NINTENDO
        case .pretendo: return CEMU_BRIDGE_NETWORK_PRETENDO
        case .custom: return CEMU_BRIDGE_NETWORK_CUSTOM
        }
    }

    var string: String {
        switch self {
        case .offline: return "Offline"
        case .nintendo: return "Nintendo Network"
        case .pretendo: return "Pretendo Network"
        case .custom: return "Custom"
        }
    }

    /// Pretendo is a community-run reimplementation of Nintendo's original Wii U online
    /// services (pretendo.network), not a MuffinEMU- or MeloCafe-specific idea - its
    /// server hostnames are already built into the engine (PretendoURLs in
    /// config/NetworkSettings.h), so selecting it needs nothing else from the user.
    var accountHelp: String {
        switch self {
        case .offline: return "Online functionality disabled for this account"
        case .nintendo: return "Connect to the official Nintendo Network Service"
        case .pretendo: return "Connect to the Pretendo Network Service, a community-run reimplementation of Nintendo's original Wii U online services"
        case .custom: return "Connect to a custom Network Service (configured via network_services.xml)"
        }
    }
}
