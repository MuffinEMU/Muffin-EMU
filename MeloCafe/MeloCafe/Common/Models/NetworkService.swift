//
//  NetworkService.swift
//  MeloCafe
//
//  Created by Stossy11 on 8/3/2026.
//

import Foundation

enum NetworkService: Int, CaseIterable, Identifiable {
    case offline = 0
    case nintendo = 1
    case pretendo = 2
    case custom = 3

    var id: Int { rawValue }
    static let onlineCases: [NetworkService] = [.nintendo, .pretendo, .custom]

    init(_ config: ObjCNetworkService) {
        self = NetworkService(rawValue: config.rawValue) ?? .offline
    }

    var config: ObjCNetworkService {
        ObjCNetworkService(rawValue: self.rawValue) ?? .offline
    }

    var string: String {
        switch self {
        case .offline: return "Offline"
        case .nintendo: return "Nintendo Network"
        case .pretendo: return "Pretendo Network"
        case .custom: return "Custom"
        }
    }
}
