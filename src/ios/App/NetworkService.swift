// MuffinEMU — code by the MuffinEMU Development Team.
// Copyright (c) 2026 MuffinEMU Development Team (Void).
// SPDX-License-Identifier: GPL-3.0-only
// Additional terms under GPL-3.0 section 7(b) and 7(c) apply: see ATTRIBUTION.md in the repository root.

import Foundation

/// Which backend an account's online traffic goes to. The plain-C bridge exposes the same
/// four cases as CemuBridgeNetworkService, converted with explicit switches below.
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
        case .offline: return "Offline".localized
        case .nintendo: return "Nintendo Network (shut down)".localized
        case .pretendo: return "Pretendo Network".localized
        case .custom: return "Custom".localized
        }
    }

    /// Pretendo is a community-run reimplementation of Nintendo's Wii U online services; its
    /// server hostnames are built into the engine (PretendoURLs in config/NetworkSettings.h).
    var accountHelp: String {
        switch self {
        case .offline: return "Online play is off for this account.".localized
        case .nintendo: return "Connect to Nintendo's original Wii U servers, which are no longer running.".localized
        case .pretendo: return "Connect to the Pretendo Network Service, a community-run replacement for Nintendo's original Wii U online services.".localized
        case .custom: return "Connect to a custom Network Service, set up in network_services.xml.".localized
        }
    }
}
