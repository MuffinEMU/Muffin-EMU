//
//  UpscalingFilter.swift
//  MeloCafe
//
//  Created by Stossy11 on 11/4/2026.
//

import Foundation

enum UpscalingFilter: Int, CaseIterable {
    case linear = 0
    case bicubic = 1
    case bicubicHermite = 2
    case nearestNeighbor = 3

    init(_ config: ObjCUpscalingFilter) {
        self = UpscalingFilter(rawValue: config.rawValue) ?? .linear
    }

    var config: ObjCUpscalingFilter {
        ObjCUpscalingFilter(rawValue: self.rawValue) ?? .linear
    }

    var string: String {
        switch self {
        case .linear: return "Linear"
        case .bicubic: return "Bicubic"
        case .bicubicHermite: return "Bicubic Hermite"
        case .nearestNeighbor: return "Nearest Neighbor"
        }
    }
}
